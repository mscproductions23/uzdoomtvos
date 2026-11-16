import Foundation
import GameController

/// Bridges the Swift launcher to the UZDoom engine.
/// Engine is shipped as UZDoomEngine.framework with SDL2 embedded.
/// The engine's program directory is derived from argv[0], which points to the app bundle root where data files and frameworks reside.
/// The engine must be called on the main thread, which hands control to SDL's run loop. The launcher UI is suspended from that point.
final class EngineBridge {

    static let shared = EngineBridge()

    /// Launcher switch: show the engine's frame-rate counter.
    static let showFrameRateKey = "showFrameRate"

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

    /// Written as uzdoom.ini when none exists. Version=234 matches UZDoom 5.0.3's engine config
    /// version, so the engine doesn't run its old-config upgrade steps on this file.
    private static let starterConfig = """
        [LastRun]
        Version=234

        [GlobalSettings]
        use_joystick=true
        cl_run=true
        vid_rendermode=0
        vid_scalemode=5
        vid_scale_customwidth=1920
        vid_scale_customheight=1080
        vid_scale_linear=true
        vid_vsync=false
        r_magfilter=true
        gl_texture_filter=0
        gl_texture_filter_anisotropic=1

        [Doom.ConsoleVariables]
        screenblocks=11
        hud_oldscale=false
        ui_screenborder_classic_scaling=false
        r_skymode=0

        """

    /// One-time changes to configs written by older builds. Each runs once, so the player
    /// can change the setting back afterwards.
    private static func migrateConfig(at url: URL) {
        let key = "configMigration.alwaysRun"
        guard !UserDefaults.standard.bool(forKey: key),
              var text = try? String(contentsOf: url, encoding: .utf8) else { return }
        // Always run on by default (cl_run lives in [GlobalSettings]).
        text = text.replacingOccurrences(of: "\ncl_run=false\n", with: "\ncl_run=true\n")
        if (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil {
            UserDefaults.standard.set(true, forKey: key)
        }
    }

    /// Developer override: KEY=VALUE lines from Caches/engine.env are exported before the engine starts.
    private static func applyEnvOverrides(from cachesDirURL: URL) {
        let envURL = cachesDirURL.appendingPathComponent("engine.env")
        guard let content = try? String(contentsOf: envURL, encoding: .utf8) else { return }

        for line in content.split(whereSeparator: { $0.isNewline }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty || trimmed.hasPrefix("#") { continue }

            let parts = trimmed.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2 else { continue }

            let key = parts[0].trimmingCharacters(in: .whitespaces)
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }

            setenv(key, value, 1)
            print("[EngineBridge] env override: \(key)=\(value)")
        }
    }

    /// Developer override: whitespace-separated arguments from Caches/engine.args are appended to the engine args.
    private static func extraEngineArgs(from cachesDirURL: URL) -> [String] {
        let argsURL = cachesDirURL.appendingPathComponent("engine.args")
        guard let content = try? String(contentsOf: argsURL, encoding: .utf8) else { return [] }

        let extra = content.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        if !extra.isEmpty {
            print("[EngineBridge] extra engine args: \(extra.joined(separator: " "))")
        }
        return extra
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

        // First launch: start from settings tuned on an Apple TV 4K (A12) to hold 60 fps.
        // The engine adds everything else and saves the result.
        if !FileManager.default.fileExists(atPath: configURL.path) {
            try? Self.starterConfig.write(to: configURL, atomically: true, encoding: .utf8)
        } else {
            Self.migrateConfig(at: configURL)
        }

        // Get log file path in Caches directory.
        let cachesDirURL = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        // UZDoom 5.x writes "log-<name>.txt" into the current directory (it no longer takes a
        // path), and the app bundle is read-only, so run from Caches: Caches/log-uzdoom.txt.
        FileManager.default.changeCurrentDirectoryPath(cachesDirURL.path)
        let logFilePath = cachesDirURL.appendingPathComponent("log-uzdoom.txt").path

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
            "+logfile", "uzdoom",
        ]
        args += ControllerPrefs.engineArgs()   // gyro / touchpad aim (Controller Settings)
        if UserDefaults.standard.bool(forKey: Self.showFrameRateKey) {
            args += ["+vid_fps", "1"]
        }
        args += Self.extraEngineArgs(from: cachesDirURL)

        // Set SDL_VULKAN_LIBRARY to embedded MoltenVK so both SDL and engine use it.
        let moltenVKPath = bundle.privateFrameworksURL!.appendingPathComponent("MoltenVK.framework/MoltenVK").path
        if !FileManager.default.fileExists(atPath: moltenVKPath) {
            print("[EngineBridge] Warning: MoltenVK not found at \(moltenVKPath)")
        }
        setenv("SDL_VULKAN_LIBRARY", moltenVKPath, 1)
        // UZDoom 5.0.3 triggers a GPU page fault (black screen) on the Apple TV A12 when MoltenVK
        // binds descriptors through Metal argument buffers, so use plain bindings. engine.env can
        // override this (MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS=1).
        setenv("MVK_CONFIG_USE_METAL_ARGUMENT_BUFFERS", "0", 1)
        Self.applyEnvOverrides(from: cachesDirURL)

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
