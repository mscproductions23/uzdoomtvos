# UZDoom tvOS Port — Session Notes

Status as of July 19, 2026: engine compiles and links cleanly; app launches
and calls into the engine; blocked at SDL_Init failing due to a UIKit
window-ownership mismatch. This is a narrow, well-understood remaining
problem, not an unknown.

## What's working

- Engine: UZDoom 4.14.3 cross-compiled clean for tvOS arm64
  (engine/, built via engine/build-tvos). Zero compile errors.
- Dependencies built for tvOS: SDL2, ZMusic (as zmusiclite, FluidSynth
  disabled), MoltenVK (pulled from Vulkan SDK). All in tvos-libs/
  (not committed - see Rebuilding below).
- App scaffold (app/): SwiftUI launcher, CloudKit sync for WADs/saves,
  Freedoom auto-install, iPhone-to-AppleTV beaming via local HTTP server,
  GameController detection. All fully functional and tested on a real
  Apple TV.
- Linking: every one of ~30 missing-symbol dyld errors was tracked down
  and resolved by re-adding the correct object file from libuzdoom.a to
  the merged libuzdoom_full.a.
- Entry point: uzdoom_launch(argc, argv) in
  engine/src/common/platform/posix/sdl/uzdoom_entry.cpp is a clean C
  entry point Swift calls via @_silgen_name. It calls SDL_SetMainReady()
  then SDL_main().

## Where it's stuck

SDL_Init(0) returns -1 (clean failure, not a crash) once called from
uzdoom_launch. Diagnosis: SDL's UIKit video driver
(SDL_uikitappdelegate.m / SDL_uikitwindow.m, part of libSDL2) expects to
own UIApplicationMain and construct its own UIWindow /
SDL_uikitviewcontroller hierarchy from app launch. Our app's SceneDelegate
creates a plain UIWindow for SwiftUI instead, and SDL's video init can't
find what it's looking for in the window/scene hierarchy, so it fails
gracefully rather than crashing.

This is the same root issue on any SDL-based engine embedded inside a
SwiftUI shell: SDL wants to be the app, not a subsystem of one.

### Two ways forward

1. Give SDL what it wants. Read SDL_uikitappdelegate.m and
   SDL_uikitwindow.m from the SDL source to find exactly what object(s)
   UIKit_VideoInit looks for, and construct them manually in
   SceneDelegate.swift before calling uzdoom_launch. Bounded work,
   likely a few hours.
2. Split into two targets. Keep the SwiftUI launcher as a picker that
   writes the chosen IWAD path to a shared config, then hand off to a
   separate, pure-SDL app target in the same Xcode project (same
   pattern as GenZD/baumhoto's iOS ports) that owns UIApplicationMain
   from the start. Loses the "seamless single window" feel but sidesteps
   the ownership fight entirely. This is the proven pattern other UZDoom/
   GZDoom Apple ports use.

If you try a different Doom source port next (Chocolate Doom, PrBoom+,
etc.) and it's SDL2-based, you will hit this exact same wall unless you
use approach #2 from the start.

## Rebuilding the merged engine library

libuzdoom_full.a (~400MB) is not committed. To rebuild it:

    cd engine
    mkdir -p build-tvos && cd build-tvos
    cmake .. \
      -DCMAKE_TOOLCHAIN_FILE=<path-to-ios-cmake>/ios.toolchain.cmake \
      -DPLATFORM=TVOS -DDEPLOYMENT_TARGET=17.0 \
      -DZMUSIC_INCLUDE_DIR=<path-to-ZMusic>/include \
      -DZMUSIC_LIBRARIES=<path-to-tvos-libs>/libzmusiclite.a \
      -DIMPORT_EXECUTABLES=<path-to-native-macOS-build>/ImportExecutables.cmake \
      -DDISCORD_RPC=OFF -DOSX_COCOA_BACKEND=OFF \
      -DSDL2_INCLUDE_DIR=<tvos-libs>/SDL2.framework/Headers \
      -DSDL2_LIBRARY=<tvos-libs>/SDL2.framework/SDL2
    make -j$(sysctl -n hw.logicalcpu)

You'll need an ImportExecutables.cmake from a native macOS build first
(cmake needs host-native tool binaries like lemon/zipdir for
cross-compiling).

Then merge every object file from libuzdoom.a plus the vendored libs
(discord-rpc, lzma, miniz, webp, zvulkan, zmusiclite) into one archive with
plain ar rcs (not libtool -static, which silently drops duplicate
symbols you may actually need):

    mkdir /tmp/merge && cd /tmp/merge
    ar x <path>/libuzdoom.a
    for lib in libdiscord-rpc libzvulkan liblzma libminiz libwebp libzmusiclite; do
      ar x <tvos-libs>/$lib.a
    done
    # Remove launcher/ZWidget-dependent objects
    rm -f launcherwindow.cpp.o launcherbanner.cpp.o launcherbuttonbar.cpp.o \
          playgamepage.cpp.o settingspage.cpp.o
    ar rcs libuzdoom_full.a *.o

Known gotcha: a few engine .o files (font.cpp.o, rawpagetexture.cpp.o,
codegen.cpp.o, file_zip.cpp.o at minimum) get silently dropped during
naive extraction because of duplicate filenames across sub-libraries. If
dyld reports "symbol not found in flat namespace" at runtime, extract
that specific .o from libuzdoom.a directly and ar r it into the merged
archive.

## Xcode project gotchas hit this session

- -force_load in Other Linker Flags gets silently mis-quoted by Xcode's
  UI when typed into the text field. Edit project.pbxproj directly with
  a script to get the array syntax right:
  OTHER_LDFLAGS = ("-Wl,-undefined,dynamic_lookup", "-force_load", "/path/to/libuzdoom_full.a");
- MACH_O_TYPE wasn't set and Xcode 27 beta defaulted the app to build as
  a preview dylib with no real executable. Explicitly set
  MACH_O_TYPE = mh_execute;
- Info.plist needs CFBundleExecutable = $(EXECUTABLE_NAME) or the
  install fails with "missing or invalid CFBundleExecutable."
- UIApplicationSceneManifest needs a real UISceneDelegateClassName
  pointing at an actual class (empty UISceneConfigurations triggers a
  scene-lifecycle crash on modern SDKs).
- Use @_silgen_name("uzdoom_launch") in Swift instead of a bridging
  header - more reliable for calling a C symbol from a merged static lib
  in this Xcode version.

## Apple-side dependencies already solved (reusable regardless of engine choice)

- tvos-libs/SDL2.framework - SDL2 built via SDL's own Xcode project,
  Static Library-tvOS / Framework-tvOS scheme.
- tvos-libs/MoltenVK.xcframework - copied from Vulkan SDK for macOS.
- tvos-libs/libzmusiclite.a - ZMusic built via ios-cmake toolchain,
  FluidSynth disabled.
- glib stub library (libglib_stubs.a) - hand-written pthread-backed
  stubs for the small glib subset FluidSynth's C code calls.

## Legal note

Freedoom is freely redistributable and is fine to auto-download/commit.
Commercial IWADs (DOOM.WAD, DOOM2.WAD, TNT.WAD, PLUTONIA.WAD) must never
be committed to this repo - .gitignore covers *.wad already.
