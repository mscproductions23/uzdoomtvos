# UZDoomTV — scaffold

A tvOS app shell for a UZDoom port with controller support, iCloud-synced WADs and
saves, iPhone beaming, and Freedoom as the automatic fallback.

**Phase 1 (this scaffold, runs today):** launcher UI, WAD discovery (bundle → local →
iCloud), Freedoom auto-install, beam-from-iPhone receiver, CloudKit sync. The engine
call is a stub.

**Phase 2 (on your Mac):** compile UZDoom for tvOS and wire it into
`EngineBridge.swift`. See `ENGINE_INTEGRATION.md`.

## Getting the scaffold running

1. `brew install xcodegen`
2. Edit `project.yml`: set your bundle ID prefix, bundle ID, `DEVELOPMENT_TEAM`
   (your Apple Developer team ID), and the iCloud container ID.
3. Edit `DoomCloudStore.swift`: set the same container ID in `CKContainer(identifier:)`.
4. Run `xcodegen` in this directory → open `UZDoomTV.xcodeproj`.
5. Select your Apple TV as the destination and run.

First run notes:
- With no WADs anywhere, the app downloads **Freedoom** automatically and lists
  Phase 1 & Phase 2 as playable.
- For your personal testing path: drag `DOOM.WAD`, `DOOM2.WAD`, `TNT.WAD`,
  `PLUTONIA.WAD` into `Resources/` before running — they'll show as "Built-in".
- **Beam from iPhone**: select it in the launcher, then open the shown
  `http://<appletv-ip>:8080` address in Safari on your iPhone (same Wi-Fi) and pick
  files. `.wad`/`.pk3` land in the WAD library, `.zds` saves land in the save folder.
- **CloudKit**: after the first run creates the schema, open the CloudKit Console
  and mark `fileName` (WadFile) and `iwadName` (SaveGame) as *queryable* — queries
  fail without those indexes.

## Legal note

Freedoom is freely redistributable; the commercial IWADs are not. Keep them to
personal sideloaded builds using your own copies.

## Layout

```
project.yml                  XcodeGen project definition
Sources/App/
  UZDoomTVApp.swift          entry point, save sync on background
  LauncherView.swift         focus-engine launcher UI
  WadLibrary.swift           discovery + orchestration model
  DoomCloudStore.swift       CloudKit WAD/save store
  FreedoomInstaller.swift    Freedoom download + unzip (ZIPFoundation)
  BeamServer.swift           HTTP receiver for iPhone Safari uploads
  EngineBridge.swift         stub — Phase 2 seam for the real engine
Resources/                   drop personal WADs here for embedded testing
ENGINE_INTEGRATION.md        Phase 2 guide
```
