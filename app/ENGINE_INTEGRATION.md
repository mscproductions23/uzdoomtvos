# Phase 2: Building UZDoom for tvOS — verified findings (July 2026)

Everything below was confirmed by actually cloning and compiling the code
(Linux container: full engine build + boot test; Apple-specific parts by
source inspection).

## Verified facts

1. **No iOS/tvOS build of UZDoom exists anywhere.** Official releases are
   Windows/Linux/macOS only. You're first.

2. **Base your port on the `4.14.3` tag** (`git clone --branch 4.14.3
   https://github.com/UZDoom/UZDoom.git`). Trunk is 5.0.0-pre with heavy churn
   (new launcher framework, TTF fonts) — a moving target. 4.14.3 is stable and
   closest to the GZDoom base the iOS ports patched.

3. **UZDoom 4.14.3 compiles clean from source.** ~1,500 files, zero compile
   errors on GCC 13. The engine boots, loads Freedoom + its pk3s, and inits
   audio; it only stops at video init on a machine with no GPU. The tree is
   healthy.

4. **Apple support is native to the codebase.** `src/common/platform/posix/`
   contains `cocoa/` and `osx/` layers, and the build loads
   `libMoltenVK.dylib` dynamically (src/CMakeLists.txt ~line 1466). You are
   extending an existing Apple path, not creating one.

5. **GenZD's source is NOT public** — its GitHub repo is README-only. Use
   **baumhoto/gzdoom** as the reference instead. It contains:
   - `gzDoom-iOS/` — a complete Xcode project
   - `gzDoom-iOS/libs/` — the full prebuilt iOS dependency set: libzmusic.a,
     libSDL2.a, libMoltenVK.dylib, libopenal, libfluidsynth, libglib, libsndfile,
     FLAC/ogg/vorbis/opus, glslang/SPIRV, etc. **This is your dependency
     shopping list.** (iOS .a files won't link for tvOS — each needs a tvOS
     slice — but the list and the Xcode wiring are the recipe.)
   - `gzDoom-iOS/gzDoom/gzDoom-Bridging-Header.h` + a lightly modified SDL
     UIKit view controller — the whole app/engine handoff.

6. **The iOS approach is SDL2-based**, not a custom backend — and **SDL2
   officially supports tvOS** (its Xcode project ships an appletvos target).
   So the path of least resistance: build SDL2 for tvOS, and the engine's
   existing SDL platform layer (`posix/sdl/`) does most of the work. SDL also
   gives you GameController input on tvOS for free.

7. **JIT: no work needed.** The ZScript JIT is x86-only (`jitintern.h` is all
   asmjit::X86*). On arm64 the engine automatically uses the VM interpreter —
   same as Apple Silicon macOS. Performance is fine for classic Doom content.

8. **Dependency list for tvOS cross-compiles**, in build order:
   - **SDL2** (official tvOS target in its Xcode project — easiest)
   - **ZMusic** as static lib. Verified: `cmake -DBUILD_SHARED_LIBS=OFF`
     builds clean. For tvOS add `-G Xcode
     -DCMAKE_TOOLCHAIN_FILE=<ios-cmake>/ios.toolchain.cmake -DPLATFORM=TVOS`.
   - **libvpx** — hard-required by UZDoom 4.14 (new vs older GZDoom). Has its
     own configure system; community prebuilt Apple frameworks exist.
   - **MoltenVK** — tvOS framework ships in the Vulkan SDK.
   - **OpenAL** — use Apple's or openal-soft built for tvOS (baumhoto vendors
     libopenal.1.dylib on iOS).

9. **Configure gotchas (hit and solved):**
   - FindZMusic needs explicit paths:
     `-DZMUSIC_INCLUDE_DIR=<ZMusic>/include -DZMUSIC_LIBRARIES=<path>/libzmusic.a`
   - CMake also honors `ZMUSIC_ROOT_PATH` / `VPX_ROOT_PATH` with per-arch
     lib dirs (see src/CMakeLists.txt ~350, ~369) — likely cleaner for Xcode
     builds.
   - Static ZMusic + engine both compile `i_module.cpp` → duplicate-symbol
     link error. Fix properly by trimming one copy, or pragmatically with
     `-Wl,--allow-multiple-definition` (ld64 equivalent: deduplicates
     automatically in many cases; if not, remove i_module from one side).
   - Static ZMusic drags in FluidSynth's deps (glib!) — link them too, as
     baumhoto's lib list confirms (libglib.a, libintl.a).

## Suggested order on your Mac

1. Open baumhoto's `gzDoom-iOS/gzdoom.xcodeproj`, get HIS port running on
   your iPhone first (his INSTALL.md documents it). This teaches you the
   working end-state with zero unknowns.
2. Duplicate that Xcode target as tvOS; swap in tvOS-built SDL2 and deps;
   fix the handful of UIKit-isms (no touch, no Files app).
3. Once his GZDoom runs on the Apple TV, swap the engine source tree for
   UZDoom 4.14.3 and re-fight the (small) diff.
4. Wire the result into EngineBridge.swift in this scaffold, replacing the
   stub — the launcher/CloudKit/beam layer is already done and tested.

## Boot-test command (works on any platform once built)

    ./uzdoom -iwad freedoom1.wad +quit -stdout

Freedoom 0.13.0 release URL and zip layout verified working (the scaffold's
FreedoomInstaller uses the same URL).
