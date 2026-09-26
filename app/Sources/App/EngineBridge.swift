import Foundation
import GameController

/// Bridges the Swift launcher to the UZDoom engine.
/// Engine is shipped as UZDoomEngine.framework with SDL2 embedded.
/// The engine's program directory is derived from argv[0], which points to the app bundle root where data files and frameworks reside.
/// The engine must be called on the main thread, which hands control to SDL's run loop. The launcher UI is suspended from that point.
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

        let bundle = Bundle.main

        // Verify uzdoom.pk3 exists in bundle root (engine finds it automatically).
        let pk3Path = bundle.bundleURL.appendingPathComponent("uzdoom.pk3").path
        if !FileManager.default.fileExists(atPath: pk3Path) {
            print("[EngineBridge] Error: uzdoom.pk3 not found in bundle root")
            self.isRunning = false
            return
        }

        // Config file lives in Caches alongside saves so it's writable on tvOS.
        let configURL = saveDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("uzdoom.ini")

        // Get log file path in Caches directory.
        let cachesDirURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let logFilePath = cachesDirURL.appendingPathComponent("uzdoom.log").path

        // Build the argument list exactly as you would on desktop.
        // argv[0] must point to bundle root so engine's program directory is correct.
        var args: [String] = [bundle.bundleURL.appendingPathComponent("uzdoom").path]

        args += [
            "-iwad",    iwad.path,
            "-savedir", saveDirectory.path,
            "-config",  configURL.path,
            "+vid_preferbackend", "1",   // Vulkan → MoltenVK → Metal
            "+vid_fullscreen",    "1",
            "+use_joystick",      "1",   // a controller is required; older configs saved it off
            "+logfile", logFilePath,
        ]

        // Set SDL_VULKAN_LIBRARY to embedded MoltenVK so both SDL and engine use it.
        let moltenVKPath = bundle.privateFrameworksURL!.appendingPathComponent("MoltenVK.framework/MoltenVK").path
        if !FileManager.default.fileExists(atPath: moltenVKPath) {
            print("[EngineBridge] Warning: MoltenVK not found at \(moltenVKPath)")
        }
        setenv("SDL_VULKAN_LIBRARY", moltenVKPath, 1)

        print("[EngineBridge] Launching UZDoom")
        print("  iwad:    \(iwad.path)")
        print("  savedir: \(saveDirectory.path)")
        print("  config:  \(configURL.path)")
        print("  logfile: \(logFilePath)")
        print("  moltenvk: \(moltenVKPath)")
        print("  controller: \(isControllerConnected)")

        // Must run on the main thread: SDL's UIKit backend creates its window
        // there and pumps this run loop from inside the engine's game loop.
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
