# UZDoomTV app

The SwiftUI launcher for the Apple TV port. For how to build, install and use it, see the
[main README](../README.md). For technical background, see [NOTES.md](../NOTES.md).

| File | What it does |
|---|---|
| `Sources/App/UZDoomTVApp.swift` | App entry point; uploads saves to iCloud when the app goes to the background |
| `Sources/App/LauncherView.swift` | Launcher screen, QR code, iCloud switch, controller requirement |
| `Sources/App/WadLibrary.swift` | Finds games (bundle → local → iCloud) and starts them |
| `Sources/App/DoomCloudStore.swift` | CloudKit sync of WADs and saves (only with `UZ_ICLOUD` and the switch on) |
| `Sources/App/FreedoomInstaller.swift` | Downloads Freedoom |
| `Sources/App/BeamServer.swift` | Small web server for the iPhone: uploads, save backup/restore, touch controller |
| `Sources/App/PadPage.swift` | The iPhone touch-controller page |
| `Sources/App/ControlsView.swift` | Controller layout and live tester |
| `Sources/App/ControllerSettingsView.swift` | Controller Settings menu: gyro/touchpad aim, tester, reset; passes the aim settings to the engine |
| `Sources/App/Assets.xcassets` | App icon, Top Shelf images and launcher logo, adapted from the UZDoom logo (CC BY-SA 4.0, © 2025 The UZDoom Team) |
| `Sources/App/EngineBridge.swift` | Starts the engine; first-launch settings |
| `Config/Base.xcconfig` | Shared build settings: default app ID, no team, iCloud off |
| `Config/Local.xcconfig` | Your team, app ID and optional iCloud (not in git; written by `tvos/install.sh`, template in `Local.xcconfig.example`) |
| `Frameworks/` | Built by `tvos/build-tvos.sh` (not in git) |
| `Resources/` | Optional personal files for your own test builds. Everything in it is git-ignored |

## Security notes

- The iPhone web server only runs while **Connect iPhone…** is on. Every request needs the random
  key from that session's QR code, and it stops by itself after 15 minutes unless the phone is
  being used as a controller. Traffic is plain HTTP (unencrypted), so it's meant for a home network.
- Commercial IWADs (DOOM.WAD, DOOM2.WAD, …) must never be committed. `.gitignore` blocks `*.wad`
  in any letter case and everything in `Resources/`. Files placed in `Resources/` are built into
  the app, so only do that for builds you keep to yourself.
