import Foundation
import SwiftUI

/// One playable game entry shown in the launcher.
struct GameEntry: Identifiable, Hashable {
    enum Source: String { case bundle = "Built-in", local = "On this Apple TV", cloud = "iCloud" }
    let id: String            // uppercased filename, e.g. "DOOM2.WAD"
    let displayName: String
    let url: URL?             // nil until downloaded from iCloud
    let source: Source
}

@MainActor
final class WadLibrary: ObservableObject {

    @Published var games: [GameEntry] = []
    @Published var busyMessage: String? = nil
    @Published var beamAddress: String? = nil
    @Published var lastError: String? = nil

    var lastLaunchedIwad: String? {
        get { UserDefaults.standard.string(forKey: "lastLaunchedIwad") }
        set { UserDefaults.standard.set(newValue, forKey: "lastLaunchedIwad") }
    }

    private let beamServer = BeamServer()
    private var beamTimeout: Task<Void, Never>?

    private static let knownIwads: [String: String] = [
        "DOOM.WAD": "The Ultimate DOOM",
        "DOOM1.WAD": "DOOM (Shareware)",
        "DOOM2.WAD": "DOOM II: Hell on Earth",
        "TNT.WAD": "Final DOOM: TNT Evilution",
        "PLUTONIA.WAD": "Final DOOM: The Plutonia Experiment",
        "FREEDOOM1.WAD": "Freedoom: Phase 1",
        "FREEDOOM2.WAD": "Freedoom: Phase 2",
        "HERETIC.WAD": "Heretic",
        "HEXEN.WAD": "Hexen",
    ]

    // MARK: Discovery

    func refresh() async {
        var found: [String: GameEntry] = [:]

        // 1. Bundle-embedded WADs (your personal testing path — just drag them into Resources/)
        if let urls = Bundle.main.urls(forResourcesWithExtension: "wad", subdirectory: nil) {
            for url in urls {
                let key = url.lastPathComponent.uppercased()
                found[key] = entry(key: key, url: url, source: .bundle)
            }
        }

        // 2. Local Caches mirror (beamed or previously downloaded)
        let dir = DoomCloudStore.localWadDirectory
        if let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) {
            for url in urls where url.pathExtension.lowercased() == "wad" {
                let key = url.lastPathComponent.uppercased()
                found[key] = entry(key: key, url: url, source: .local)  // local shadows bundle
            }
        }

        // 3. iCloud (listed but not yet downloaded)
        if let cloud = try? await DoomCloudStore.shared.listWads() {
            for wad in cloud where found[wad.name] == nil {
                found[wad.name] = entry(key: wad.name, url: nil, source: .cloud)
            }
        }

        games = found.values.sorted { $0.displayName < $1.displayName }

        // 4. Freedoom fallback: nothing playable at all -> fetch Freedoom automatically.
        if games.isEmpty {
            await installFreedoom()
        }
    }

    private func entry(key: String, url: URL?, source: GameEntry.Source) -> GameEntry {
        GameEntry(id: key,
                  displayName: Self.knownIwads[key] ?? key,
                  url: url,
                  source: source)
    }

    // MARK: Actions

    /// Resolve a launch: download from iCloud if needed, sync saves down, then hand off to the engine.
    func play(_ game: GameEntry) async {
        do {
            busyMessage = "Preparing \(game.displayName)…"
            defer { busyMessage = nil }

            let urls = try await DoomCloudStore.shared.ensureWadsPresent([game.id]) { name in
                Task { @MainActor in self.busyMessage = "Downloading \(name) from iCloud…" }
            }
            guard let iwadURL = urls.first else { return }

            try? await DoomCloudStore.shared.syncSavesDown(iwadName: game.id)
            lastLaunchedIwad = game.id

            EngineBridge.shared.launch(iwad: iwadURL,
                                       saveDirectory: DoomCloudStore.localSaveDirectory)
        } catch {
            lastError = error.localizedDescription
        }
    }

    func installFreedoom() async {
        do {
            busyMessage = "Downloading Freedoom…"
            defer { busyMessage = nil }
            try await FreedoomInstaller.install(into: DoomCloudStore.localWadDirectory) { status in
                Task { @MainActor in self.busyMessage = status }
            }
            await refresh()
        } catch {
            lastError = "Freedoom download failed: \(error.localizedDescription)"
        }
    }

    func toggleBeam() {
        if beamAddress != nil {
            beamServer.stop()
            beamAddress = nil
            beamTimeout?.cancel()
            beamTimeout = nil
            Task { await refresh() }
        } else {
            do {
                let address = try beamServer.start { [weak self] in
                    Task { await self?.refresh() }
                }
                beamAddress = address
                beamTimeout?.cancel()
                beamTimeout = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(15 * 60))   // don't leave the receiver open by accident
                    guard !Task.isCancelled, let self, self.beamAddress != nil else { return }
                    self.toggleBeam()
                }
            } catch {
                lastError = "Could not start receiver: \(error.localizedDescription)"
            }
        }
    }
}
