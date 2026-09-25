# tvOS Build Script

## What It Does

The `build-tvos.sh` script automates building the UZDoom engine and all its dependencies from source for Apple TV (tvOS). It fetches the source repositories, applies patches, builds each dependency (SDL2, ZMusic, libvpx, OpenAL), creates native build tools, compiles the tvOS engine, and packages everything into the app's Frameworks directory.

**Caching strategy:** Only the four expensive dependency builds (sdl2, zmusic, libvpx, openal) are cached with `.done` stamps. Fetch, host-tools, engine, and package always run to ensure patches are applied, code changes picked up, and assets are current. Use `FORCE=1` to rebuild the dependency libraries even if they're cached.

## Prerequisites

- **macOS** (Apple Silicon recommended) with Xcode 27 or later installed
- **tvOS Platform** in Xcode (check Xcode → Preferences → Components)
- **CMake** (install via `brew install cmake` if missing)
- **Homebrew** (optional, for easy CMake install)
- **Ninja** (optional but faster; install via `brew install ninja`)
- **Paths with spaces are fine:** if the repo lives under a folder with a space (e.g. `~/App Projects/`), the script automatically puts its work files in `~/uzdoomtvos-work` instead of `tvos/work` (some of the libraries can't build in paths with spaces). You can pick another spot with `WORK=/some/path`.

## Quick Start

```bash
./tvos/build-tvos.sh
```

That's it. The script runs all build steps in order. Expect 20–40 minutes on first run.

## What Happens

1. **Preflight**: Checks macOS, Xcode, cmake, git, curl
2. **Fetch**: Clones UZDoom, SDL2, ZMusic, libvpx, OpenAL, and MoltenVK
3. **Dependencies**: Builds SDL2, ZMusic, libvpx (autotools), and OpenAL (tvOS static libraries)
4. **Host Tools**: Builds UZDoom tools on native macOS (for code generation during tvOS build)
5. **Engine**: Compiles UZDoom for tvOS with all dependencies linked
6. **Package**: Copies frameworks, assets, soundfonts, and runs sanity checks
7. **Summary**: Shows what was built

## Individual Steps

Run only specific steps if needed (preflight always runs first to set up directories):

```bash
./tvos/build-tvos.sh all                  # Build everything (same as no args)
./tvos/build-tvos.sh sdl2 zmusic          # Build only SDL2 and zmusic
./tvos/build-tvos.sh libvpx               # Rebuild libvpx only
./tvos/build-tvos.sh engine package       # Rebuild engine and package
```

Available steps: `fetch`, `sdl2`, `zmusic`, `libvpx`, `openal`, `moltenvk`, `host-tools`, `engine`, `package`, `summary`, `all`

Note: `preflight` runs automatically at the start and is not selectable as a separate step.

## Options

### Rebuild Everything

```bash
FORCE=1 ./tvos/build-tvos.sh
```

Ignores the "already built" markers and rebuilds the four dependency libraries too.

### Build Without Audio

```bash
NO_AUDIO=1 ./tvos/build-tvos.sh
```

Skips OpenAL; configures the engine with `-DNO_OPENAL=ON`.

### Parallel Jobs

```bash
JOBS=8 ./tvos/build-tvos.sh
```

Default is the number of logical CPUs on your machine.

### Custom tvOS Minimum

```bash
TVOS_MIN=18.0 ./tvos/build-tvos.sh
```

Default is 17.0.

## Logs

All build output goes to `tvos/work/logs/` (or `~/uzdoomtvos-work/logs/` when the repo path has a space), one file per sub-step, e.g.:

- `sdl2_build.log`
- `libvpx_configure.log`
- `engine_build.log`

If a step fails, the script prints the last 40 lines of its log. Check the full log for details.

## After Building

1. Open `app/UZDoomTV.xcodeproj` in Xcode
2. Select your Apple TV as the run destination
3. Press Run (⌘R)

Engine output appears in Xcode's console. The app also writes logs to `Caches/uzdoom.log` on the device.

## If It Fails

Note the step name (e.g., "engine") and attach the corresponding log file from `tvos/work/logs/`:

```bash
cat tvos/work/logs/engine_build.log
```

## Directories

- **`tvos/work/src`**: Source repositories (UZDoom, SDL2, etc.)
- **`tvos/work/build`**: Build directories for each component
- **`tvos/work/prefix`**: Installed libraries and headers (tvOS static)
- **`tvos/work/logs`**: Build output logs
- **`app/Frameworks`**: Final tvOS engine and Vulkan frameworks
- **`app/`**: Assets, pk3 files, soundfonts (copied here)

All of `tvos/work/` is gitignored and safe to delete for a clean rebuild.
