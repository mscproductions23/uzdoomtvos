#!/bin/bash
set -euo pipefail

# === EARLY HELPER ===

die() {
    echo "ERROR: $1" >&2
    exit 1
}

# === CONFIGURATION ===

# Resolve repo root
REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)

# Detect if REPO_ROOT has spaces and set default WORK
if [[ -z "${WORK:-}" ]]; then
    if [[ "$REPO_ROOT" == *" "* ]]; then
        WORK="$HOME/uzdoomtvos-work"
        echo "Note: REPO_ROOT contains spaces. Using WORK=$WORK"
    else
        WORK="$REPO_ROOT/tvos/work"
    fi
fi

# Check if WORK contains spaces
if [[ "$WORK" == *" "* ]]; then
    die "WORK path contains spaces: $WORK. Please set WORK to a path without spaces."
fi

# Directories
SRC="$WORK/src"
BUILD="$WORK/build"
PREFIX="$WORK/prefix"
LOG_DIR="$WORK/logs"
APP_DIR="$REPO_ROOT/app"
OUT_FW="$APP_DIR/Frameworks"

# Versions
UZDOOM_TAG="4.14.3"
SDL_TAG="release-2.32.10"
ZMUSIC_TAG="1.1.14"
VPX_TAG="v1.15.2"
OPENAL_TAG="1.24.3"
MOLTENVK_VERSION="v1.4.2"

# Build settings
TVOS_MIN="${TVOS_MIN:-17.0}"
NO_AUDIO="${NO_AUDIO:-0}"
JOBS="${JOBS:-$(sysctl -n hw.logicalcpu 2>/dev/null || echo 4)}"
FORCE="${FORCE:-0}"

# Detect generator (as array for proper quoting with spaces)
if command -v ninja >/dev/null 2>&1; then
    GENERATOR=(-G Ninja)
else
    GENERATOR=(-G "Unix Makefiles")
fi

# Shared tvOS CMake args (as array to avoid word splitting)
TVOS_CMAKE_ARGS=(
    -DCMAKE_SYSTEM_NAME=tvOS
    -DCMAKE_OSX_SYSROOT=appletvos
    -DCMAKE_OSX_ARCHITECTURES=arm64
    -DCMAKE_OSX_DEPLOYMENT_TARGET="$TVOS_MIN"
    -DCMAKE_BUILD_TYPE=Release
    -DCMAKE_INSTALL_PREFIX="$PREFIX"
    -DCMAKE_PREFIX_PATH="$PREFIX"
    -DCMAKE_FIND_ROOT_PATH="$PREFIX"
)

# === HELPER FUNCTIONS ===

log_header() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] === $1 ==="
}

plist_set() {
    local plist="$1"
    local key="$2"
    local type="$3"
    local value="$4"

    /usr/libexec/PlistBuddy -c "Set :$key $value" "$plist" 2>/dev/null || \
        /usr/libexec/PlistBuddy -c "Add :$key $type $value" "$plist"
}

check_done() {
    # Only used for dependency builds: sdl2, zmusic, libvpx, openal
    [[ ! -f "$BUILD/$1.done" || "$FORCE" == "1" ]] && return 1
    return 0
}

mark_done() {
    # Only used for dependency builds: sdl2, zmusic, libvpx, openal
    mkdir -p "$BUILD"
    touch "$BUILD/$1.done"
}

run_step() {
    local step="$1"
    shift
    local log="$LOG_DIR/$step.log"
    mkdir -p "$(dirname "$log")"
    if ! "$@" 2>&1 | tee "$log"; then
        echo "Step $step failed — see $log"
        tail -n 40 "$log"
        exit 1
    fi
}

# === STEP FUNCTIONS ===

step_preflight() {
    # Preflight always runs (no stamp) and must set up directories first
    log_header "Step 0: preflight"

    mkdir -p "$LOG_DIR" "$BUILD" "$SRC"

    [[ "$(uname -s)" == "Darwin" ]] || die "This script requires macOS"

    xcrun --sdk appletvos --show-sdk-path >/dev/null || die "Xcode tvOS SDK not found. Run: sudo xcode-select -s /Applications/Xcode.app"

    command -v cmake >/dev/null || die "cmake not found. Run: brew install cmake"
    command -v git >/dev/null || die "git not found"
    command -v curl >/dev/null || die "curl not found"

    echo "Tools:"
    cmake --version | head -1
    git --version
    echo "SDK path: $(xcrun --sdk appletvos --show-sdk-path)"
    echo "Generator: ${GENERATOR[*]}"
    echo "Logical CPUs: $JOBS"
}

step_fetch() {
    # fetch always runs (no stamp) to pick up code/patch changes
    log_header "Step 1: fetch"

    # Clone repos
    local repos=(
        "uzdoom:$UZDOOM_TAG:https://github.com/UZDoom/UZDoom.git"
        "sdl2:$SDL_TAG:https://github.com/libsdl-org/SDL.git"
        "zmusic:$ZMUSIC_TAG:https://github.com/UZDoom/ZMusic.git"
        "libvpx:$VPX_TAG:https://github.com/webmproject/libvpx.git"
        "openal:$OPENAL_TAG:https://github.com/kcat/openal-soft.git"
    )

    for repo_spec in "${repos[@]}"; do
        IFS=':' read -r name tag url <<< "$repo_spec"
        if [[ ! -d "$SRC/$name" ]]; then
            echo "Cloning $name..."
            run_step "fetch_$name" git clone --depth 1 --branch "$tag" "$url" "$SRC/$name"
        else
            echo "Repo $name already cloned"
        fi
    done

    # Apply patches
    for name in uzdoom sdl2 zmusic libvpx openal; do
        local patch_dir="$REPO_ROOT/tvos/patches/$name"
        if [[ -d "$patch_dir" ]]; then
            while IFS= read -r -d '' pfile; do
                echo "Checking patch: $(basename "$pfile")"
                if git -C "$SRC/$name" apply --reverse --check "$pfile" >/dev/null 2>&1; then
                    echo "  Already applied, skipping"
                elif git -C "$SRC/$name" apply --check "$pfile" >/dev/null 2>&1; then
                    echo "  Applying..."
                    git -C "$SRC/$name" apply "$pfile"
                else
                    die "Patch $(basename "$pfile") no longer matches $SRC/$name. Delete that folder and re-run: rm -rf '$SRC/$name'"
                fi
            done < <(find "$patch_dir" -name "*.patch" -print0 | sort -z)
        fi
    done

    # Download and extract MoltenVK
    mkdir -p "$WORK/downloads"
    local moltenvk_tar="$WORK/downloads/MoltenVK-all-${MOLTENVK_VERSION}.tar"
    if [[ ! -f "$moltenvk_tar" ]]; then
        echo "Downloading MoltenVK..."
        run_step "fetch_moltenvk" curl -fL --retry 3 -o "$moltenvk_tar" "https://github.com/KhronosGroup/MoltenVK/releases/download/${MOLTENVK_VERSION}/MoltenVK-all.tar"
    else
        echo "MoltenVK tar already downloaded"
    fi
    # MoltenVK tar extracts to MoltenVK/ at the top level; extract into a subdir
    local moltenvk_xcfw="$SRC/moltenvk/MoltenVK/MoltenVK/dynamic/MoltenVK.xcframework"
    if [[ ! -d "$moltenvk_xcfw" ]]; then
        echo "Extracting MoltenVK..."
        mkdir -p "$SRC/moltenvk"
        run_step "extract_moltenvk" tar -C "$SRC/moltenvk" -xf "$moltenvk_tar"
    else
        echo "MoltenVK already extracted"
    fi
}

step_sdl2() {
    check_done "sdl2" && return
    log_header "Step 3: sdl2"

    mkdir -p "$BUILD/sdl2"
    run_step "sdl2_configure" cmake -S "$SRC/sdl2" -B "$BUILD/sdl2" \
        "${GENERATOR[@]}" \
        "${TVOS_CMAKE_ARGS[@]}" \
        -DSDL_SHARED=OFF -DSDL_STATIC=ON -DSDL_TEST=OFF -DSDL_OPENGL=OFF -DSDL_OPENGLES=OFF -DSDL_HIDAPI=OFF
    run_step "sdl2_build" cmake --build "$BUILD/sdl2" --parallel "$JOBS"
    run_step "sdl2_install" cmake --install "$BUILD/sdl2"

    [[ -f "$PREFIX/lib/libSDL2.a" ]] || die "SDL2 static library not found"
    [[ -f "$PREFIX/include/SDL2/SDL.h" ]] || die "SDL2 header not found"

    mark_done "sdl2"
}

step_zmusic() {
    check_done "zmusic" && return
    log_header "Step 4: zmusic"

    mkdir -p "$BUILD/zmusic"
    run_step "zmusic_configure" cmake -S "$SRC/zmusic" -B "$BUILD/zmusic" \
        "${GENERATOR[@]}" \
        "${TVOS_CMAKE_ARGS[@]}" \
        -DBUILD_SHARED_LIBS=OFF -DZMUSIC_POSIX_GLIB_STUBS=ON
    run_step "zmusic_build" cmake --build "$BUILD/zmusic" --parallel "$JOBS"
    run_step "zmusic_install" cmake --install "$BUILD/zmusic"

    [[ -f "$PREFIX/lib/libzmusic.a" ]] || die "zmusic static library not found"
    [[ -f "$PREFIX/include/zmusic.h" ]] || die "zmusic header not found"

    mark_done "zmusic"
}

step_libvpx() {
    check_done "libvpx" && return
    log_header "Step 5: libvpx"

    mkdir -p "$BUILD/libvpx"
    (
        cd "$BUILD/libvpx"
        SDK=$(xcrun --sdk appletvos --show-sdk-path)
        CC=$(xcrun --sdk appletvos -f clang)
        CXX=$(xcrun --sdk appletvos -f clang++)
        AR=$(xcrun --sdk appletvos -f ar)
        LD="$CC"
        STRIP=$(xcrun --sdk appletvos -f strip)
        NM=$(xcrun --sdk appletvos -f nm)
        RANLIB=$(xcrun --sdk appletvos -f ranlib)
        export CC CXX AR LD STRIP NM RANLIB

        flags="-arch arm64 -isysroot $SDK -mtvos-version-min=$TVOS_MIN"
        # --extra-cflags doesn't reach configure's link test, so without these
        # the linker defaults to macOS and rejects the tvOS objects.
        CFLAGS="$flags"
        CXXFLAGS="$flags"
        LDFLAGS="$flags"
        export CFLAGS CXXFLAGS LDFLAGS
        run_step "libvpx_configure" "$SRC/libvpx/configure" \
            --target=generic-gnu --prefix="$PREFIX" \
            --enable-static --disable-shared --enable-pic \
            --disable-examples --disable-tools --disable-docs \
            --disable-unit-tests --disable-install-bins --disable-install-srcs \
            --disable-vp8-encoder --disable-vp9-encoder --enable-vp8-decoder --enable-vp9-decoder \
            --extra-cflags="$flags" --extra-cxxflags="$flags"
        run_step "libvpx_build" make -j"$JOBS"
        run_step "libvpx_install" make install
    ) || die "Step libvpx failed — see $LOG_DIR/libvpx_*.log"

    [[ -f "$PREFIX/lib/libvpx.a" ]] || die "libvpx static library not found"
    [[ -f "$PREFIX/include/vpx/vp8dx.h" ]] || die "libvpx header not found"

    mark_done "libvpx"
}

step_openal() {
    if [[ "$NO_AUDIO" == "1" ]]; then
        log_header "Step 6: openal (SKIPPED due to NO_AUDIO=1)"
        return
    fi

    check_done "openal" && return
    log_header "Step 6: openal"

    mkdir -p "$BUILD/openal"
    run_step "openal_configure" cmake -S "$SRC/openal" -B "$BUILD/openal" \
        "${GENERATOR[@]}" \
        "${TVOS_CMAKE_ARGS[@]}" \
        -DLIBTYPE=STATIC -DALSOFT_UTILS=OFF -DALSOFT_EXAMPLES=OFF -DALSOFT_TESTS=OFF \
        -DALSOFT_INSTALL_CONFIG=OFF -DALSOFT_INSTALL_HRTF_DATA=OFF -DALSOFT_INSTALL_AMBDEC_PRESETS=OFF \
        -DALSOFT_INSTALL_EXAMPLES=OFF -DALSOFT_INSTALL_UTILS=OFF -DALSOFT_REQUIRE_COREAUDIO=ON -DALSOFT_EMBED_HRTF_DATA=ON
    run_step "openal_build" cmake --build "$BUILD/openal" --parallel "$JOBS"
    run_step "openal_install" cmake --install "$BUILD/openal"

    [[ -f "$PREFIX/lib/libopenal.a" ]] || die "OpenAL static library not found"
    [[ -f "$PREFIX/include/AL/al.h" ]] || die "OpenAL header not found"

    mark_done "openal"
}

step_moltenvk() {
    # Cheap copy; always runs so a deleted app/Frameworks is restored
    log_header "Step 7: moltenvk"

    mkdir -p "$OUT_FW"
    run_step "moltenvk_copy" rsync -a --delete "$SRC/moltenvk/MoltenVK/MoltenVK/dynamic/MoltenVK.xcframework" "$OUT_FW/"

    local found
    found=$(find "$OUT_FW/MoltenVK.xcframework" -path "*tvos-arm64*/MoltenVK.framework/MoltenVK" ! -path "*simulator*" 2>/dev/null | head -1)
    [[ -n "$found" ]] || die "MoltenVK tvOS arm64 framework not found"
}

step_host_tools() {
    # host-tools always runs (no stamp) to pick up engine code changes
    log_header "Step 8: host-tools"

    mkdir -p "$BUILD/uzdoom-host"
    run_step "host-tools_configure" env -u SDKROOT -u CC -u CXX cmake -S "$SRC/uzdoom" -B "$BUILD/uzdoom-host" \
        "${GENERATOR[@]}" -DCMAKE_BUILD_TYPE=Release -DUZ_TOOLS_ONLY=ON
    run_step "host-tools_build" cmake --build "$BUILD/uzdoom-host" --parallel "$JOBS"

    [[ -f "$BUILD/uzdoom-host/ImportExecutables.cmake" ]] || die "ImportExecutables.cmake not found"
    local pk3
    pk3=$(find "$BUILD/uzdoom-host" -maxdepth 2 -name "uzdoom.pk3" -type f | head -1)
    [[ -n "$pk3" ]] || die "uzdoom.pk3 not found from host build"
}

step_engine() {
    # engine always runs (no stamp) to pick up source changes
    log_header "Step 9: engine"

    mkdir -p "$BUILD/uzdoom-tvos"

    local openal_args=()
    if [[ "$NO_AUDIO" == "1" ]]; then
        openal_args=(-DNO_OPENAL=ON)
    else
        openal_args=(-DDYN_OPENAL=OFF "-DOPENAL_INCLUDE_DIR=$PREFIX/include/AL" "-DOPENAL_LIBRARY=$PREFIX/lib/libopenal.a")
    fi

    run_step "engine_configure" cmake -S "$SRC/uzdoom" -B "$BUILD/uzdoom-tvos" \
        "${GENERATOR[@]}" \
        "${TVOS_CMAKE_ARGS[@]}" \
        "-DIMPORT_EXECUTABLES=$BUILD/uzdoom-host/ImportExecutables.cmake" \
        "-DSDL2_INCLUDE_DIR=$PREFIX/include/SDL2" "-DSDL2_LIBRARY=$PREFIX/lib/libSDL2.a" \
        "-DZMUSIC_INCLUDE_DIR=$PREFIX/include" "-DZMUSIC_LIBRARIES=$PREFIX/lib/libzmusic.a" \
        "-DVPX_INCLUDE_DIR=$PREFIX/include" "-DVPX_LIBRARIES=$PREFIX/lib/libvpx.a" \
        "-DCMAKE_C_FLAGS=-I$PREFIX/include" "-DCMAKE_CXX_FLAGS=-I$PREFIX/include" \
        "${openal_args[@]}"
    run_step "engine_build" cmake --build "$BUILD/uzdoom-tvos" --target zdoom --parallel "$JOBS"

    local fw
    fw=$(find "$BUILD/uzdoom-tvos" -maxdepth 3 -type d -name "UZDoomEngine.framework" | head -1)
    [[ -n "$fw" ]] || die "UZDoomEngine.framework not found"
}

step_package() {
    # package always runs (no stamp) to pick up asset/framework changes
    log_header "Step 10: package"

    local fw
    fw=$(find "$BUILD/uzdoom-tvos" -maxdepth 3 -type d -name "UZDoomEngine.framework" | head -1)

    run_step "package_framework" rsync -a --delete "$fw" "$OUT_FW/"

    # Copy pk3s
    for pk3 in uzdoom.pk3 game_support.pk3 game_widescreen_gfx.pk3 brightmaps.pk3 lights.pk3; do
        local pfile
        pfile=$(find "$BUILD/uzdoom-host" -maxdepth 2 -name "$pk3" -type f | head -1)
        if [[ -n "$pfile" ]]; then
            cp "$pfile" "$APP_DIR/"
        else
            if [[ "$pk3" == "brightmaps.pk3" ]] || [[ "$pk3" == "lights.pk3" ]]; then
                echo "WARNING: $pk3 not found (optional)"
            else
                die "$pk3 not found (required)"
            fi
        fi
    done

    # Copy soundfonts and fm_banks
    mkdir -p "$APP_DIR/soundfonts" "$APP_DIR/fm_banks"
    if [[ -f "$SRC/uzdoom/soundfont/uzdoom.sf2" ]]; then
        cp "$SRC/uzdoom/soundfont/uzdoom.sf2" "$APP_DIR/soundfonts/"
    else
        die "uzdoom.sf2 not found at $SRC/uzdoom/soundfont/uzdoom.sf2"
    fi
    if [[ -d "$SRC/uzdoom/fm_banks" ]]; then
        cp -R "$SRC/uzdoom/fm_banks/." "$APP_DIR/fm_banks/"
    else
        echo "WARNING: fm_banks directory not found"
    fi

    # Update framework Info.plist for tvOS
    local plist="$OUT_FW/UZDoomEngine.framework/Info.plist"
    plist_set "$plist" "MinimumOSVersion" "string" "$TVOS_MIN"
    /usr/libexec/PlistBuddy -c "Delete :CFBundleSupportedPlatforms" "$plist" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :CFBundleSupportedPlatforms array" \
        -c "Add :CFBundleSupportedPlatforms:0 string AppleTVOS" "$plist"
    plist_set "$plist" "CFBundlePackageType" "string" "FMWK"

    # Sanity checks
    local engine_bin="$OUT_FW/UZDoomEngine.framework/UZDoomEngine"
    [[ -f "$engine_bin" ]] || die "Engine binary not found"

    echo "Binary sanity checks:"
    lipo -archs "$engine_bin" | grep -q arm64 || die "arm64 slice not found"
    echo "  ✓ arm64 slice present"

    nm -gU "$engine_bin" | grep -q "_uzdoom_launch" || die "_uzdoom_launch symbol not found"
    echo "  ✓ _uzdoom_launch symbol present"

    echo "  Binary dependencies:"
    otool -L "$engine_bin" | head -10
    if otool -L "$engine_bin" | grep -iE "sdl2|moltenvk" >/dev/null; then
        die "Engine incorrectly linked against SDL2 or MoltenVK"
    fi
    echo "  ✓ No SDL2 or MoltenVK dylib references"

    echo "  Build version info:"
    otool -l "$engine_bin" | grep -A5 "LC_BUILD_VERSION" | grep -q "platform 3" || die "tvOS platform not set"
    otool -l "$engine_bin" | grep -A5 "LC_BUILD_VERSION"
}

step_summary() {
    log_header "Step 11: summary"

    echo "Built frameworks and assets:"
    du -sh "$OUT_FW/UZDoomEngine.framework" 2>/dev/null || echo "UZDoomEngine.framework: not found"
    du -sh "$OUT_FW/MoltenVK.xcframework" 2>/dev/null || echo "MoltenVK.xcframework: not found"
    du -sh "$APP_DIR" 2>/dev/null || echo "App dir: not found"

    echo ""
    echo "Total build time: $(( $(date +%s) - START_TIME )) seconds"
    echo ""
    echo "Next steps:"
    echo "1. Open app/UZDoomTV.xcodeproj in Xcode"
    echo "2. Pick your Apple TV as the run destination"
    echo "3. Press Run (⌘R)"
    echo ""
    echo "Engine output appears in Xcode's console; the app also writes Caches/uzdoom.log on the device."
}

# === MAIN ===

START_TIME=$(date +%s)

if [[ "$#" -gt 0 ]] && { [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; }; then
    echo "Usage: $0 [<step>...]"
    echo ""
    echo "Steps: fetch sdl2 zmusic libvpx openal moltenvk host-tools engine package summary all"
    echo "Note: preflight always runs first to set up directories."
    echo ""
    echo "Environment variables:"
    echo "  FORCE=1         Rebuild cached dependencies (default: skip)"
    echo "  NO_AUDIO=1      Skip OpenAL build"
    echo "  TVOS_MIN=17.0   Minimum tvOS version (default: 17.0)"
    echo "  JOBS=N          Number of parallel build jobs (default: hw.logicalcpu)"
    echo "  WORK=/path      Work directory for sources/builds (default: tvos/work or ~/uzdoomtvos-work if repo has spaces)"
    echo ""
    echo "Examples:"
    echo "  $0                      # Build everything"
    echo "  $0 all                  # Build everything (same as no args)"
    echo "  $0 sdl2 zmusic          # Build only SDL2 and zmusic (dependencies)"
    echo "  $0 engine package       # Rebuild engine and package"
    echo "  FORCE=1 $0              # Rebuild cached dependencies (sdl2, zmusic, libvpx, openal)"
    echo "  NO_AUDIO=1 $0           # Build without audio support"
    exit 0
fi

# Preflight always runs first to set up directories
step_preflight

if [[ "$#" -eq 0 ]]; then
    # Build all
    step_fetch
    step_sdl2
    step_zmusic
    step_libvpx
    step_openal
    step_moltenvk
    step_host_tools
    step_engine
    step_package
    step_summary
else
    # Run selected steps; check for "all" or specific steps
    for step in "$@"; do
        case "$step" in
            all)
                step_fetch
                step_sdl2
                step_zmusic
                step_libvpx
                step_openal
                step_moltenvk
                step_host_tools
                step_engine
                step_package
                step_summary
                ;;
            fetch) step_fetch ;;
            sdl2) step_sdl2 ;;
            zmusic) step_zmusic ;;
            libvpx) step_libvpx ;;
            openal) step_openal ;;
            moltenvk) step_moltenvk ;;
            host-tools) step_host_tools ;;
            engine) step_engine ;;
            package) step_package ;;
            summary) step_summary ;;
            -h|--help) ;; # Already handled above
            *) echo "Unknown step: $step"; exit 1 ;;
        esac
    done
fi
