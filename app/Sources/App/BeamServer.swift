import Foundation
import Network
import ZIPFoundation

/// Minimal HTTP receiver so files can be "beamed" from an iPhone on the same Wi-Fi:
///   GET  /              -> serves a small upload page
///   PUT  /upload/<name> -> raw file body written to the right directory
///   GET  /saves.json    -> list of save files
///   GET  /saves/<name>  -> one save file
///   GET  /saves.zip     -> all saves zipped
/// .wad/.pk3 files land in the WAD directory; .zds saves land in the save directory.
/// No companion app needed — Safari + the page's JavaScript does the upload.
final class BeamServer {

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var onFileReceived: (() -> Void)?
    private let queue = DispatchQueue(label: "beam-server")
    private var accessKey = ""
    private var padListener: NWListener?
    private var padConnection: NWConnection?          // the one authenticated phone controller
    private var onPadChanged: ((Bool) -> Void)?

    /// Starts the server; returns the URL to show on screen, e.g. "http://192.168.1.40:8080/?key=…"
    func start(onFileReceived: @escaping () -> Void, onPadChanged: @escaping (Bool) -> Void) throws -> String {
        self.onFileReceived = onFileReceived
        self.onPadChanged = onPadChanged
        let listener = try NWListener(using: .tcp, on: 8080)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        var rng = SystemRandomNumberGenerator()
        let key = (0..<16).map { _ in String(format: "%02x", UInt8.random(in: 0...255, using: &rng)) }.joined()
        queue.sync { accessKey = key }   // requests read accessKey on `queue`
        listener.start(queue: queue)
        self.listener = listener

        let wsParams = NWParameters.tcp
        let wsOptions = NWProtocolWebSocket.Options()
        wsOptions.autoReplyPing = true
        wsParams.defaultProtocolStack.applicationProtocols.insert(wsOptions, at: 0)
        let padListener: NWListener
        do {
            padListener = try NWListener(using: wsParams, on: 8081)
        } catch {
            stop()   // don't leave the file server running without its controller port
            throw error
        }
        padListener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: self?.queue ?? .main)
            self?.receivePad(on: connection, authenticated: false)
        }
        padListener.start(queue: queue)
        self.padListener = padListener

        let ip = Self.localIPAddress() ?? "<this-apple-tv's-IP>"
        return "http://\(ip):8080/?key=\(key)"
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
        padListener?.cancel()
        padListener = nil
        var wasConnected = false
        queue.sync {   // padConnection is only touched on `queue`
            wasConnected = padConnection != nil
            padConnection?.cancel()
            padConnection = nil
            uzdoom_set_touch_pad(nil, 0, 0)
        }
        if wasConnected {
            DispatchQueue.main.async { [weak self] in self?.onPadChanged?(false) }
        }
        queue.sync { accessKey = "" }
    }

    // MARK: Connection handling

    private func accept(_ connection: NWConnection) {
        connections[ObjectIdentifier(connection)] = connection
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, complete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let request = HTTPRequest(parsing: buffer) {
                self.handle(request, on: connection)
            } else if error != nil || complete {
                self.close(connection)
            } else {
                self.receive(on: connection, buffer: buffer)   // need more bytes
            }
        }
    }

    private func handle(_ request: HTTPRequest, on connection: NWConnection) {
        let parts = request.path.split(separator: "?", maxSplits: 1).map(String.init)
        let path = parts.first ?? "/"
        let query = parts.count > 1 ? parts[1] : ""
        let key = URLComponents(string: "/?" + query)?.queryItems?.first { $0.name == "key" }?.value ?? ""
        guard !accessKey.isEmpty, Self.constantTimeEquals(key, accessKey) else {
            respond(connection, status: "403 Forbidden", contentType: "text/html; charset=utf-8",
                    body: Data(Self.expiredPage.utf8))
            return
        }
        switch (request.method, path) {
        case ("GET", "/"):
            respond(connection, status: "200 OK", contentType: "text/html; charset=utf-8", body: Data(Self.uploadPage.utf8))

        case ("GET", "/saves.json"):
            let items = Self.saveFiles().map { url -> [String: Any] in
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                return [
                    "name": url.lastPathComponent,
                    "size": values?.fileSize ?? 0,
                    "modified": (values?.contentModificationDate ?? .distantPast).timeIntervalSince1970,
                ]
            }
            let json = (try? JSONSerialization.data(withJSONObject: items)) ?? Data("[]".utf8)
            respond(connection, status: "200 OK", contentType: "application/json", body: json)

        case ("GET", "/saves.zip"):
            let saves = Self.saveFiles()
            guard !saves.isEmpty else {
                respond(connection, status: "404 Not Found", contentType: "text/plain", body: Data("No saves yet.".utf8))
                return
            }
            let zipURL = FileManager.default.temporaryDirectory.appendingPathComponent("uzdoom-saves.zip")
            do {
                try? FileManager.default.removeItem(at: zipURL)
                let archive = try Archive(url: zipURL, accessMode: .create)
                for save in saves {
                    try archive.addEntry(with: save.lastPathComponent, relativeTo: DoomCloudStore.localSaveDirectory)
                }
                let data = try Data(contentsOf: zipURL)
                try? FileManager.default.removeItem(at: zipURL)
                respond(connection, status: "200 OK", contentType: "application/zip", body: data,
                        extraHeaders: ["Content-Disposition": "attachment; filename=\"uzdoom-saves.zip\""])
            } catch {
                respond(connection, status: "500 Internal Server Error", contentType: "text/plain",
                        body: Data(error.localizedDescription.utf8))
            }

        case ("GET", let p) where p.hasPrefix("/saves/"):
            let rawName = String(p.dropFirst("/saves/".count)).removingPercentEncoding ?? ""
            let name = (rawName as NSString).lastPathComponent   // no path traversal
            let file = DoomCloudStore.localSaveDirectory.appendingPathComponent(name)
            guard (name as NSString).pathExtension.lowercased() == "zds",
                  let data = try? Data(contentsOf: file) else {
                respond(connection, status: "404 Not Found", contentType: "text/plain", body: Data("No such save.".utf8))
                return
            }
            respond(connection, status: "200 OK", contentType: "application/octet-stream", body: data,
                    extraHeaders: ["Content-Disposition": "attachment; filename=\"\(name)\""])

        case ("PUT", let p) where p.hasPrefix("/upload/"):
            let rawName = String(p.dropFirst("/upload/".count))
                .removingPercentEncoding ?? ""
            // Sanitize: no path separators, known extensions only.
            let name = (rawName as NSString).lastPathComponent
            let ext = (name as NSString).pathExtension.lowercased()
            let destDir: URL?
            switch ext {
            case "wad", "pk3", "ipk3": destDir = DoomCloudStore.localWadDirectory
            case "zds":                destDir = DoomCloudStore.localSaveDirectory
            default:                   destDir = nil
            }
            guard let destDir, !name.isEmpty else {
                respond(connection, status: "400 Bad Request", contentType: "text/plain",
                        body: Data("Only .wad, .pk3, .ipk3 and .zds files are accepted.".utf8))
                return
            }
            do {
                try FileManager.default.createDirectory(at: destDir, withIntermediateDirectories: true)
                try request.body.write(to: destDir.appendingPathComponent(name))
                onFileReceived?()
                respond(connection, status: "200 OK", contentType: "text/plain", body: Data("OK".utf8))
            } catch {
                respond(connection, status: "500 Internal Server Error", contentType: "text/plain",
                        body: Data(error.localizedDescription.utf8))
            }

        case ("GET", "/pad"):
            respond(connection, status: "200 OK", contentType: "text/html; charset=utf-8", body: Data(PadPage.html.utf8))

        default:
            respond(connection, status: "404 Not Found", contentType: "text/plain", body: Data("Not found".utf8))
        }
    }

    private func respond(_ connection: NWConnection, status: String, contentType: String, body: Data, extraHeaders: [String: String] = [:]) {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
        for (key, value) in extraHeaders {
            head += "\(key): \(value)\r\n"
        }
        head += "Connection: close\r\n\r\n"
        var response = Data(head.utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { [weak self] _ in
            self?.close(connection)
        })
    }

    private func close(_ connection: NWConnection) {
        connection.cancel()
        connections[ObjectIdentifier(connection)] = nil
    }

    // MARK: Touch pad (WebSocket, port 8081)

    /// First text message must be the access key; after that, messages are JSON
    /// {"a":[lx,ly,rx,ry,lt,rt],"b":buttons}. Runs on `queue`.
    private func receivePad(on connection: NWConnection, authenticated: Bool) {
        connection.receiveMessage { [weak self] data, _, _, error in
            guard let self else { return }
            if error != nil || data == nil {
                self.dropPad(connection)
                return
            }
            let text = String(decoding: data ?? Data(), as: UTF8.self)
            if !authenticated {
                guard !self.accessKey.isEmpty, Self.constantTimeEquals(text, self.accessKey) else {
                    connection.cancel()
                    return
                }
                // One phone at a time: a new controller replaces the old one.
                if let old = self.padConnection, old !== connection { old.cancel() }
                self.padConnection = connection
                self.sendPadText("ok", on: connection)
                DispatchQueue.main.async { self.onPadChanged?(true) }
                self.receivePad(on: connection, authenticated: true)
                return
            }
            if connection === self.padConnection,
               let obj = try? JSONSerialization.jsonObject(with: data ?? Data()) as? [String: Any],
               let a = obj["a"] as? [Double], a.count == 6 {
                let axes = a.map { Float(max(-1, min(1, $0))) }
                let buttons = (obj["b"] as? Int).map { UInt32(truncatingIfNeeded: $0) } ?? 0
                axes.withUnsafeBufferPointer { uzdoom_set_touch_pad($0.baseAddress, buttons, 1) }
            }
            self.receivePad(on: connection, authenticated: true)
        }
    }

    private func sendPadText(_ text: String, on connection: NWConnection) {
        let meta = NWProtocolWebSocket.Metadata(opcode: .text)
        let context = NWConnection.ContentContext(identifier: "pad", metadata: [meta])
        connection.send(content: Data(text.utf8), contentContext: context, isComplete: true, completion: .idempotent)
    }

    private func dropPad(_ connection: NWConnection) {
        connection.cancel()
        guard connection === padConnection else { return }
        padConnection = nil
        uzdoom_set_touch_pad(nil, 0, 0)   // release everything the phone was holding
        DispatchQueue.main.async { [weak self] in self?.onPadChanged?(false) }
    }

    // MARK: Helpers

    private static func localIPAddress() -> String? {
        var address: String?
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let interface = ptr.pointee
            guard interface.ifa_addr.pointee.sa_family == UInt8(AF_INET) else { continue }
            let name = String(cString: interface.ifa_name)
            guard name == "en0" || name == "en1" else { continue }
            var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
            getnameinfo(interface.ifa_addr, socklen_t(interface.ifa_addr.pointee.sa_len),
                        &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
            address = String(cString: host)
        }
        return address
    }

    /// Compares without returning early, so response timing doesn't reveal how much of a key matched.
    private static func constantTimeEquals(_ a: String, _ b: String) -> Bool {
        let x = Array(a.utf8), y = Array(b.utf8)
        guard x.count == y.count else { return false }
        var diff: UInt8 = 0
        for i in 0..<x.count { diff |= x[i] ^ y[i] }
        return diff == 0
    }

    private static let expiredPage = """
    <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
    <title>UZDoom TV</title>
    <style>body{font-family:-apple-system,sans-serif;margin:1.5rem;background:#111;color:#eee}h1{color:#e33}</style>
    </head><body><h1>Link expired</h1>
    <p>On the Apple TV, choose <b>Beam from iPhone…</b> and scan the new QR code.</p>
    </body></html>
    """

    /// The .zds save files in the save folder, newest first.
    private static func saveFiles() -> [URL] {
        let dir = DoomCloudStore.localSaveDirectory
        let files = (try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        return files
            .filter { $0.pathExtension.lowercased() == "zds" }
            .sorted {
                let a = (try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                let b = (try? $1.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
                return a > b
            }
    }

    private static let uploadPage = """
    <!doctype html><html><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
    <title>UZDoom TV</title>
    <style>
    body{font-family:-apple-system,sans-serif;margin:1.5rem;background:#111;color:#eee;line-height:1.4}
    h1{color:#e33;margin-bottom:.2rem} h2{margin-top:2rem;border-top:1px solid #333;padding-top:1rem}
    .hint{color:#999;font-size:.9rem}
    input,button,a.button{font-size:1.05rem;margin:.4rem 0}
    button,a.button{background:#e33;color:#fff;border:0;border-radius:8px;padding:.55rem 1rem;text-decoration:none;display:inline-block}
    ul{list-style:none;padding:0} li{display:flex;justify-content:space-between;align-items:center;padding:.6rem 0;border-bottom:1px solid #222}
    li a{color:#6af} .meta{color:#999;font-size:.85rem}
    #log{margin-top:1rem;white-space:pre-line}
    </style>
    </head><body>
    <h1>UZDoom TV</h1>
    <p class="hint">Keep this page open on the same Wi-Fi as the Apple TV.</p>
    <p><a class="button" id="padlink" href="/pad">🎮 Use this phone as a controller</a></p>

    <h2>Send files to the Apple TV</h2>
    <p>Pick .wad / .pk3 games or .zds saves:</p>
    <input type="file" id="files" multiple>
    <button onclick="send()">Send to Apple TV</button>
    <div id="log"></div>

    <h2>Back up your saves</h2>
    <p class="hint">Download saves to this phone. To restore them later, send them back with the section above.</p>
    <a class="button" id="all" href="/saves.zip">Download all saves (.zip)</a>
    <ul id="saves"><li class="meta">Loading…</li></ul>

    <script>
    const KEY = new URLSearchParams(location.search).get('key') || '';
    const withKey = (p) => p + '?key=' + encodeURIComponent(KEY);
    document.getElementById('padlink').href = withKey('/pad');
    async function send(){
      const log = document.getElementById('log');
      for (const f of document.getElementById('files').files){
        log.textContent += `Sending ${f.name}… `;
        try {
          const r = await fetch(withKey('/upload/' + encodeURIComponent(f.name)), {method:'PUT', body:f});
          log.textContent += r.ok ? 'done\\n' : `failed (${r.status})\\n`;
        } catch(e){ log.textContent += 'failed: ' + e + '\\n'; }
      }
      log.textContent += 'All transfers finished.';
      loadSaves();
    }
    async function loadSaves(){
      const list = document.getElementById('saves');
      try {
        const saves = await (await fetch(withKey('/saves.json'))).json();
        document.getElementById('all').href = withKey('/saves.zip');
        document.getElementById('all').style.display = saves.length ? '' : 'none';
        if (!saves.length){ list.innerHTML = '<li class="meta">No saves on the Apple TV yet.</li>'; return; }
        list.innerHTML = '';
        for (const s of saves){
          const li = document.createElement('li');
          const a = document.createElement('a');
          a.href = withKey('/saves/' + encodeURIComponent(s.name));
          a.textContent = s.name;
          a.setAttribute('download', s.name);
          const meta = document.createElement('span');
          meta.className = 'meta';
          meta.textContent = new Date(s.modified * 1000).toLocaleString() + ' · ' + Math.max(1, Math.round(s.size / 1024)) + ' KB';
          li.append(a, meta);
          list.append(li);
        }
      } catch(e){ list.innerHTML = '<li class="meta">Couldn\\'t load the save list: ' + e + '</li>'; }
    }
    loadSaves();
    </script></body></html>
    """
}

/// Tiny HTTP request parser — just enough for GET and raw-body PUT with Content-Length.
private struct HTTPRequest {
    let method: String
    let path: String
    let body: Data

    init?(parsing data: Data) {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return nil }
        guard let headerText = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else { return nil }
        let lines = headerText.components(separatedBy: "\r\n")
        let requestParts = lines[0].components(separatedBy: " ")
        guard requestParts.count >= 2 else { return nil }

        var contentLength = 0
        for line in lines.dropFirst() {
            let kv = line.split(separator: ":", maxSplits: 1)
            if kv.count == 2, kv[0].lowercased() == "content-length" {
                contentLength = Int(kv[1].trimmingCharacters(in: .whitespaces)) ?? 0
            }
        }

        let bodyStart = headerEnd.upperBound
        let bodyAvailable = data.count - bodyStart
        guard bodyAvailable >= contentLength else { return nil }   // wait for more bytes

        self.method = requestParts[0]
        self.path = requestParts[1]
        self.body = data.subdata(in: bodyStart..<(bodyStart + contentLength))
    }
}
