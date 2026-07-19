import Foundation
import GameController

// Declare the C entry point directly — bypasses bridging header entirely.
@_silgen_name("uzdoom_launch")
func uzdoom_launch(_ argc: Int32, _ argv: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> Int32

/// Bridges the Swift launcher to the UZDoom engine.
/// SDL requires UIApplicationMain to already be running before it can create
/// a Metal window — so the engine must be called on the main thread, which
/// hands control to SDL's run loop. The launcher UI is suspended from that point.
final class EngineBridge {

    static let shared = EngineBridge()

    @Published private(set) var isRunning = false
    private(set) var isControllerConnected = GCController.controllers().isEmpty == false

    private init() {
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidConnect, object: nil, queue: .main) { [weak self] _ in
                self?.isControllerConnected = true
        }
        NotificationCenter.default.addObserver(
            forName: .GCControllerDidDisconnect, object: nil, queue: .main) { [weak self] _ in
                self?.isControllerConnected = GCController.controllers().isEmpty == false
        }
    }

    func launch(iwad: URL, saveDirectory: URL) {
        guard !isRunning else { return }
        isRunning = true

        // Locate the engine's own pk3 data files from the app bundle.
        let bundle = Bundle.main
        let enginePk3s: [String] = ["uzdoom", "game_support", "game_widescreen_gfx"]
            .compactMap { bundle.path(forResource: $0, ofType: "pk3") }

        // Config file lives in Caches alongside saves so it's writable on tvOS.
        let configURL = saveDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("uzdoom.ini")

        // Build the argument list exactly as you would on desktop.
        var args: [String] = ["uzdoom"]

        // Engine data files — must come before the IWAD.
        for pk3 in enginePk3s {
            args += ["-file", pk3]
        }

        args += [
            "-iwad",    iwad.path,
            "-savedir", saveDirectory.path,
            "-config",  configURL.path,
            "+vid_preferbackend", "1",   // Vulkan → MoltenVK → Metal
            "+vid_fullscreen",    "1",
        ]

        print("[EngineBridge] Launching UZDoom")
        print("  iwad:    \(iwad.path)")
        print("  savedir: \(saveDirectory.path)")
        print("  config:  \(configURL.path)")
        print("  pk3s:    \(enginePk3s)")
        print("  controller: \(isControllerConnected)")

        // Must run on the main thread — SDL's UIKit Metal layer requires
        // UIApplicationMain to already own the run loop before SDL_Init
        // can create a CAMetalLayer-backed window on tvOS.
        DispatchQueue.main.async {
            var cargs = args.map { strdup($0) }
            cargs.append(nil)

            // This call does not return until the user quits the game.
            let ret = uzdoom_launch(Int32(args.count), &cargs)
            cargs.compactMap { $0 }.forEach { free($0) }

            print("[EngineBridge] Engine exited with code \(ret)")
            self.isRunning = false
            // Engine quit — restart the app so the launcher reappears.
            exit(0)
        }
    }
}
