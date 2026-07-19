import Foundation
import Network

/// Minimal HTTP receiver so files can be "beamed" from an iPhone on the same Wi-Fi:
///   GET  /              -> serves a small upload page
///   PUT  /upload/<name> -> raw file body written to the right directory
/// .wad/.pk3 files land in the WAD directory; .zds saves land in the save directory.
/// No companion app needed — Safari + the page's JavaScript does the upload.
final class BeamServer {

    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var onFileReceived: (() -> Void)?
    private let queue = DispatchQueue(label: "beam-server")

    /// Starts the server; returns the URL to show on screen, e.g. "http://192.168.1.40:8080"
    func start(onFileReceived: @escaping () -> Void) throws -> String {
        self.onFileReceived = onFileReceived
        let listener = try NWListener(using: .tcp, on: 8080)
        listener.newConnectionHandler = { [weak self] connection in
            self?.accept(connection)
        }
        listener.start(queue: queue)
        self.listener = listener
        let ip = Self.localIPAddress() ?? "<this-apple-tv's-IP>"
        return "http://\(ip):8080"
    }

    func stop() {
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
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
        switch (request.method, request.path) {
        case ("GET", "/"):
            respond(connection, status: "200 OK", contentType: "text/html", body: Data(Self.uploadPage.utf8))

        case ("PUT", let path) where path.hasPrefix("/upload/"):
            let rawName = String(path.dropFirst("/upload/".count))
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

        default:
            respond(connection, status: "404 Not Found", contentType: "text/plain", body: Data("Not found".utf8))
        }
    }

    private func respond(_ connection: NWConnection, status: String, contentType: String, body: Data) {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: \(contentType)\r\n"
        head += "Content-Length: \(body.count)\r\n"
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

    private static let uploadPage = """
    <!doctype html><html><head><meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Beam to UZDoom TV</title>
    <style>body{font-family:-apple-system,sans-serif;margin:2rem;background:#111;color:#eee}
    h1{color:#e33} input,button{font-size:1.1rem;margin:.5rem 0} #log{margin-top:1rem;white-space:pre-line}</style>
    </head><body>
    <h1>Beam to UZDoom TV</h1>
    <p>Pick your .wad / .pk3 / .zds files:</p>
    <input type="file" id="files" multiple>
    <button onclick="send()">Send to Apple TV</button>
    <div id="log"></div>
    <script>
    async function send(){
      const log = document.getElementById('log');
      for (const f of document.getElementById('files').files){
        log.textContent += `Sending ${f.name}… `;
        try {
          const r = await fetch('/upload/' + encodeURIComponent(f.name), {method:'PUT', body:f});
          log.textContent += r.ok ? 'done\\n' : `failed (${r.status})\\n`;
        } catch(e){ log.textContent += 'failed: ' + e + '\\n'; }
      }
      log.textContent += 'All transfers finished.';
    }
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
