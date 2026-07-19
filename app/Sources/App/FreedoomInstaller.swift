import Foundation
import ZIPFoundation

/// Downloads the official Freedoom release and installs freedoom1.wad / freedoom2.wad
/// into the local WAD directory. Freedoom is freely redistributable (BSD-style license),
/// so unlike the commercial IWADs it's fine to fetch automatically.
enum FreedoomInstaller {

    // Pin a specific release so the URL is stable; bump as new versions ship.
    static let releaseURL = URL(string:
        "https://github.com/freedoom/freedoom/releases/download/v0.13.0/freedoom-0.13.0.zip")!

    static func install(into wadDirectory: URL,
                        status: @Sendable (String) -> Void) async throws {
        try FileManager.default.createDirectory(at: wadDirectory, withIntermediateDirectories: true)

        status("Downloading Freedoom 0.13.0…")
        let (tempFile, response) = try await URLSession.shared.download(from: releaseURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        status("Unpacking…")
        let archive = try Archive(url: tempFile, accessMode: .read)
        var installed = 0
        for entry in archive {
            let name = (entry.path as NSString).lastPathComponent.uppercased()
            guard name == "FREEDOOM1.WAD" || name == "FREEDOOM2.WAD" else { continue }
            let dest = wadDirectory.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dest)
            _ = try archive.extract(entry, to: dest)
            installed += 1
        }
        try? FileManager.default.removeItem(at: tempFile)

        guard installed > 0 else {
            throw NSError(domain: "FreedoomInstaller", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Archive layout unexpected — no Freedoom WADs found."
            ])
        }
    }
}
