# UZDoom tvOS Port — Notes

## Status (September 25, 2026)

The port was rebuilt from scratch on the `tvos-rebuild` branch. The July
engine work was lost: the `engine` submodule pointed at a commit that was
never pushed, and the Mac's `~/Desktop/uzdoom-tvos` and
`~/Developer/doomtv/tvos-libs` folders no longer exist. Everything needed to
rebuild now lives in this repo as patches plus one build script.

Not yet built or run on a Mac/Apple TV. Next step: run `tvos/build-tvos.sh`
on the Mac, then Run from Xcode (see `tvos/README.md`).

## Why the July build failed

`SDL_Init(0)` returning -1 was **not** a UIKit window-ownership problem.
`SDL_Init(0)` starts no subsystems and never touches video. On iOS/tvOS it
fails for one reason only: SDL thinks `SDL_SetMainReady()` was never called
("Application didn't initialize properly, did you include SDL_main.h…").
`uzdoom_launch` did call it, so the call landed in a *different copy* of SDL
than the one `SDL_Init` ran in. The app linked SDL2.framework and a merged
static engine archive, glued together with `-Wl,-undefined,dynamic_lookup`
and weak "mega_stubs" symbols. That combination hides missing and duplicate
symbols at link time, which is also where the ~30 "symbol not found in flat
namespace" errors came from.

Problems that were queued up behind it:
- MoltenVK was neither linked nor embedded, so Vulkan (`vid_preferbackend 1`)
  could not have started.
- SDL2 creates its UIWindow without a scene, and scene-based (SwiftUI) apps
  never show such windows.
- The launcher passed `uzdoom.pk3` with `-file`; the engine expects its base
  pk3 in its program directory (derived from argv[0]).
- `autosegs.cpp` reads registration sections from `_mh_execute_header`, which
  only works when the engine is the main executable.
- libvpx and OpenAL were missing; FluidSynth (inside ZMusic) needs glib.
- Several macOS-only calls (AppKit via discord-rpc, CFUserNotification,
  popen/system/fork, OpenGL.framework headers) don't compile for tvOS.

## Current design

- **Engine = `UZDoomEngine.framework`** (dynamic). SDL2, ZMusic, libvpx and
  OpenAL are linked statically *inside* it, so there is exactly one SDL and
  any missing symbol is a build error instead of a runtime surprise. It
  exports `uzdoom_launch(argc, argv)` (`src/common/platform/posix/sdl/uzdoom_entry.cpp`),
  which calls `SDL_SetMainReady()` then the engine's `main` (renamed
  `SDL_main` by SDL.h).
- **MoltenVK** comes from Khronos's prebuilt `MoltenVK.xcframework` (dynamic)
  and is embedded next to the engine. The app sets `SDL_VULKAN_LIBRARY` to
  its binary; SDL and the engine's volk loader both use it.
- **SDL2 patch** attaches SDL's window to the app's active `UIWindowScene`,
  so the SwiftUI app keeps owning `UIApplicationMain`.
- **Engine patches** (all behind `UZ_TVOS`, set when `CMAKE_SYSTEM_NAME` is
  tvOS): framework target, SDL backend instead of Cocoa, all user folders
  mapped to Caches (the only writable place on tvOS), no process spawning,
  no Discord, SDL message box for fatal errors. `UZ_TOOLS_ONLY` lets the Mac
  build the host tools (lemon, re2c, zipdir) and pk3s without any deps.
- **ZMusic patch** adds pthread-based glib stubs for FluidSynth
  (`-DZMUSIC_POSIX_GLIB_STUBS=ON`).
- The app passes `argv[0] = <bundle>/uzdoom`, so the pk3s, `soundfonts/`
  and `fm_banks/` sit at the bundle root. Engine output also goes to
  `Caches/uzdoom.log` on the device.

## Apple TV rendering findings (September 25, 2026, Apple TV 4K 2nd gen, A12)

- **Pink or green title screen and menus** (UZDoom#1116, MoltenVK#2220): MoltenVK 1.2.7 and later only set
  `MTLTextureUsagePixelFormatView` on images created with `MUTABLE_FORMAT`. The fix is in
  ZVulkan's `ImageBuilder`: on `UZ_TVOS` it adds `MUTABLE_FORMAT` to every colour image and
  `SAMPLED` to transfer-source images. Confirmed on the device.
- **Texture smear** (hardware renderer): with any texture filter except None, walls smear along
  one texture axis and floors turn one flat colour. Close-up surfaces look right. Building
  the mipmaps on the CPU (`CreateTextureWithCpuMipmaps`) did NOT fix it, so the mip contents
  aren't the cause. The status-bar border fill (a wrapped 2D draw using the same REPEAT sampler)
  shows the same striping with `ui_screenborder_classic_scaling=true`, even with the filter set
  to None. Suspects: REPEAT addressing or texture-coordinate derivatives under MoltenVK on A12.
  Unresolved; worked around by the defaults below.
- **Vsync**: `vid_vsync=true` (Vulkan FIFO) makes the frame rate collapse. The likely cause is that
  frames missing the 16.7 ms deadline wait a whole refresh, halving the rate. On tvOS, Core
  Animation syncs to the display anyway (`displaySyncEnabled` is macOS-only), so vsync off
  should not tear. Keep it off.
- **Settings that hold 60 fps**, found by the user on the device and written by the launcher as a starter
  `uzdoom.ini` on first launch (`EngineBridge.starterConfig`): software renderer
  (`vid_rendermode=0`), custom 1920x1080 scaling with linear upscale and `r_magfilter`, vsync off,
  texture filter None / anisotropy 1, `screenblocks=11`, non-classic HUD and border scaling,
  `r_skymode=0`.
- The config and the Vulkan pipeline cache are saved when the app goes to the background
  (`I_TvosSuspend`), because tvOS usually kills backgrounded apps without a clean exit.

## Layout

    app/                  SwiftUI launcher + Xcode project
    app/Frameworks/       (generated) UZDoomEngine.framework, MoltenVK.xcframework
    tvos/build-tvos.sh    fetches, patches and builds everything
    tvos/patches/<repo>/  patches applied to pinned upstream tags
    tvos/work/            (generated) sources, builds, logs

## Legal note

Freedoom is freely redistributable. Commercial IWADs (DOOM.WAD, DOOM2.WAD,
TNT.WAD, PLUTONIA.WAD) must never be committed; `.gitignore` covers `*.wad`.

## Signing / iCloud

The project's `DEVELOPMENT_TEAM` is a paid Apple Developer Program team. iCloud is ON:
the target signs with `UZDoomTV.entitlements` (container `iCloud.com.mscproductions.uzdoomtv`)
and sets `UZ_ICLOUD`. The launcher's **iCloud Sync** switch (`DoomCloudStore.syncEnabled`,
UserDefaults `iCloudSyncEnabled`, default on) makes every cloud call report "disabled" when
off. To build with a free team, clear Code Signing Entitlements and remove `UZ_ICLOUD`.
Without `UZ_ICLOUD`, `DoomCloudStore` never creates a `CKContainer` (doing so without the
entitlement crashes).

## iPhone controller

`PadPage.swift` is a touch gamepad page served at `/pad` (it needs the Beam key). It opens a
WebSocket to port 8081 (`BeamServer`), sends the key as its first message, then sends JSON
`{"a":[lx,ly,rx,ry,lt,rt],"b":bits}`. `BeamServer` passes this to the engine's exported
`uzdoom_set_touch_pad()` (`i_gcjoystick.mm`), which merges it with any real controller using
the same XInput-style layout, so the default pad bindings and menus just work. One phone at a
time. A connected phone counts as a controller for the launcher's "controller required" check,
and receiving doesn't auto-stop while it's connected.

## Saves

The engine gets `-savedir <Caches>/saves` and writes `.zds` files straight into it, with no
per-game subfolder. tvOS has no permanent local storage: Caches survive reinstalling over
the app, but not deleting it, and the system may purge them when storage is low. Backups:
- the Beam page (`BeamServer`, port 8080; every request needs the random per-session `?key=` from the QR code; auto-stops after 15 min) lists saves and serves `/saves/<name>` and
  `/saves.zip` for download, and still accepts `.zds` uploads to restore them;
- iCloud sync in `DoomCloudStore` (down on launch, up on background) once iCloud is on.
