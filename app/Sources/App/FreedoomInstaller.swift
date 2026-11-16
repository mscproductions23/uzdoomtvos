import Foundation
import CryptoKit
import ZIPFoundation

/// Downloads the official Freedoom release and installs freedoom1.wad / freedoom2.wad
/// into the local WAD directory. Freedoom is freely redistributable (BSD-style license),
/// so unlike the commercial IWADs it's fine to fetch automatically.
enum FreedoomInstaller {

    // Pin a specific release so the URL is stable; bump as new versions ship.
    static let releaseURL = URL(string:
        "https://github.com/freedoom/freedoom/releases/download/v0.13.0/freedoom-0.13.0.zip")!

    // releaseURL and releaseSHA256 must be bumped together. Any version change needs both updated.
    // The SHA-256 was computed from the official GitHub release asset at releaseURL.
    static let releaseSHA256 = "3f9b264f3e3ce503b4fb7f6bdcb1f419d93c7b546f4df3e874dd878db9688f59"

    static func install(into wadDirectory: URL,
                        status: @Sendable (String) -> Void) async throws {
        try FileManager.default.createDirectory(at: wadDirectory, withIntermediateDirectories: true)

        status("Downloading Freedoom 0.13.0…")
        let (tempFile, response) = try await URLSession.shared.download(from: releaseURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        // Verify the downloaded file's integrity
        let digest = try SHA256.hash(data: Data(contentsOf: tempFile, options: .mappedIfSafe))
        let actualSHA256 = digest.map { String(format: "%02x", $0) }.joined()
        guard actualSHA256 == releaseSHA256 else {
            try? FileManager.default.removeItem(at: tempFile)
            throw NSError(domain: "FreedoomInstaller", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "The Freedoom download didn't match its expected checksum, so it was not installed."
            ])
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
