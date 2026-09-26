#!/bin/bash

set -euo pipefail

# === FUNCTIONS ===

die() {
  echo "ERROR: ${1:-Installation failed.}" >&2
  exit 1
}

log_header() {
  echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] === $1 ==="
}

log() {
  echo "$1"
}

usage() {
  cat <<EOF
Usage: ./tvos/install.sh [--team TEAMID] [--bundle-id ID] [--icloud] [--device NAME|ID] [--skip-engine] [--no-launch]

  --team TEAMID     Your Apple developer team ID (Xcode → Settings → Accounts). Needed the first time.
  --bundle-id ID    App ID to sign with (default: com.uzdoomtv.<team id in lower case>).
  --icloud          Turn on iCloud sync (paid developer accounts only).
  --device NAME|ID  Which Apple TV, if more than one is paired.
  --skip-engine     Don't rebuild the engine (use the one already in app/Frameworks).
  --no-launch       Install only; don't open the app afterwards.

Your settings are saved in app/Config/Local.xcconfig, so later runs need no options.
EOF
}

# === SETUP ===

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
cd "$REPO_ROOT"

if [[ -z "${WORK:-}" ]]; then
  if [[ "$REPO_ROOT" == *" "* ]]; then
    WORK="$HOME/uzdoomtvos-work"
    echo "Note: REPO_ROOT contains spaces. Using WORK=$WORK"
  else
    WORK="$REPO_ROOT/tvos/work"
  fi
fi

# === CHECK MACOS AND TOOLS ===

[[ "$(uname -s)" == "Darwin" ]] || die "Xcode is needed. Install it from the Mac App Store, open it once, then run this again."

command -v xcodebuild >/dev/null || die "Xcode is needed. Install it from the Mac App Store, open it once, then run this again."
command -v xcrun >/dev/null || die "Xcode is needed. Install it from the Mac App Store, open it once, then run this again."

# === PARSE OPTIONS ===

TEAM_ID=""
BUNDLE_ID=""
USE_ICLOUD=false
DEVICE=""
SKIP_ENGINE=false
NO_LAUNCH=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --team)
      TEAM_ID="${2:-}"
      [[ -z "$TEAM_ID" ]] && { usage; exit 1; }
      shift 2
      ;;
    --bundle-id)
      BUNDLE_ID="${2:-}"
      [[ -z "$BUNDLE_ID" ]] && { usage; exit 1; }
      shift 2
      ;;
    --team=*)
      TEAM_ID="${1#--team=}"
      shift
      ;;
    --bundle-id=*)
      BUNDLE_ID="${1#--bundle-id=}"
      shift
      ;;
    --device)
      DEVICE="${2:-}"
      [[ -z "$DEVICE" ]] && { usage; exit 1; }
      shift 2
      ;;
    --device=*)
      DEVICE="${1#--device=}"
      shift
      ;;
    --icloud)
      USE_ICLOUD=true
      shift
      ;;
    --skip-engine)
      SKIP_ENGINE=true
      shift
      ;;
    --no-launch)
      NO_LAUNCH=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: Unknown option: $1" >&2
      usage
      exit 1
      ;;
  esac
done

# === SIGNING CONFIG ===

CONF="app/Config/Local.xcconfig"

if [[ -n "$TEAM_ID" ]]; then
  if [[ -z "$BUNDLE_ID" ]]; then
    TEAM_ID_LOWER=$(printf '%s' "$TEAM_ID" | tr '[:upper:]' '[:lower:]')
    BUNDLE_ID="com.uzdoomtv.$TEAM_ID_LOWER"
  fi
  mkdir -p "$(dirname "$CONF")"
  printf '// Written by tvos/install.sh. Git-ignored; edit or delete freely.\n' > "$CONF"
  printf 'DEVELOPMENT_TEAM = %s\n' "$TEAM_ID" >> "$CONF"
  printf 'UZ_BUNDLE_ID = %s\n' "$BUNDLE_ID" >> "$CONF"
  if [[ "$USE_ICLOUD" == true ]]; then
    printf 'UZ_ENTITLEMENTS = UZDoomTV.entitlements\n' >> "$CONF"
    printf 'UZ_EXTRA_CONDITIONS = UZ_ICLOUD\n' >> "$CONF"
  fi
elif [[ -n "$BUNDLE_ID" ]] || [[ "$USE_ICLOUD" == true ]]; then
  die "Give --team as well so the settings file can be written."
elif [[ ! -f "$CONF" ]]; then
  die "First run: tell me your team ID, for example: ./tvos/install.sh --team ABCDE12345  (find it in Xcode → Settings → Accounts → your Apple ID)"
fi

BUNDLE_ID=$(sed -n -E 's/^[[:space:]]*UZ_BUNDLE_ID[[:space:]]*=[[:space:]]*(.*[^[:space:]])[[:space:]]*$/\1/p' "$CONF" | sed -n '1p')
BUNDLE_ID="${BUNDLE_ID:-com.mscproductions.uzdoomtv}"

# === ENGINE ===

if [[ "$SKIP_ENGINE" != true ]]; then
  ./tvos/build-tvos.sh
else
  if [[ ! -d "app/Frameworks/UZDoomEngine.framework" ]]; then
    die "No engine built yet; run without --skip-engine."
  fi
fi

# === BUILD THE APP ===

if [[ "$WORK" == *" "* ]]; then
  die "WORK path contains spaces: $WORK. Please set WORK to a path without spaces."
fi

mkdir -p "$WORK/logs"
LOG_FILE="$WORK/logs/app_build.log"

log_header "Building app (log: $LOG_FILE)"
if ! xcodebuild -project app/UZDoomTV.xcodeproj -scheme UZDoomTV -configuration Release \
  -destination 'generic/platform=tvOS' -derivedDataPath "$WORK/app-build" \
  -allowProvisioningUpdates build >"$LOG_FILE" 2>&1; then
  log "Build failed. Last 40 lines of log:"
  tail -n 40 "$LOG_FILE"
  log "If it's a signing error: in Xcode → Settings → Accounts, make sure your Apple ID is added. Free Apple IDs can't use --icloud."
  die "App build failed (log: $LOG_FILE)"
fi

APP="$WORK/app-build/Build/Products/Release-appletvos/UZDoomTV.app"
[[ -d "$APP" ]] || die "App build failed."

# === FIND THE APPLE TV ===

tmpjson=$(mktemp)
trap 'rm -f "$tmpjson"' EXIT
xcrun devicectl list devices --json-output "$tmpjson" >/dev/null 2>&1 \
  || die "Couldn't list devices with Xcode. Open Xcode once (it may need to finish installing components), then try again."

DEVICES=$(
  xcrun python3 -c '
import json
import sys

with open(sys.argv[1]) as f:
    data = json.load(f)

for device in data.get("result", {}).get("devices", []):
    platform = device.get("hardwareProperties", {}).get("platform", "")
    reality = device.get("hardwareProperties", {}).get("reality", "")
    if platform == "tvOS" and reality == "physical":
        ident = device.get("identifier", "")
        name = device.get("deviceProperties", {}).get("name", "")
        print(ident + "\t" + name)
' "$tmpjson"
)

if [[ -n "$DEVICE" ]]; then
  LINE=$(printf '%s\n' "$DEVICES" | awk -F'\t' -v want="$DEVICE" '$1 == want || $2 == want { print; exit }')
  if [[ -z "$LINE" ]]; then
    printf '%s\n' "Available Apple TVs:" "$DEVICES"
    die "No paired Apple TV called '$DEVICE'."
  fi
else
  COUNT=$(printf '%s\n' "$DEVICES" | sed '/^$/d' | wc -l | tr -d ' ')
  if [[ "$COUNT" -eq 0 ]]; then
    die "No Apple TV found. Pair it first: on the Apple TV open Settings → Remotes and Devices → Remote App and Devices, then in Xcode open Window → Devices and Simulators and click Pair."
  elif [[ "$COUNT" -gt 1 ]]; then
    printf '%s\n' "Available Apple TVs:" "$DEVICES"
    die "Several Apple TVs are paired; choose one with --device."
  fi
  LINE="$DEVICES"
fi

DEVICE_ID=$(printf '%s' "$LINE" | cut -f1)
DEVICE_NAME=$(printf '%s' "$LINE" | cut -f2-)

# === INSTALL ===

log_header "Installing app"
xcrun devicectl device install app --device "$DEVICE_ID" "$APP" || die "Failed to install. The Apple TV must be awake and on the same network."

# === LAUNCH ===

if [[ "$NO_LAUNCH" != true ]]; then
  log_header "Launching app"
  xcrun devicectl device process launch --device "$DEVICE_ID" "$BUNDLE_ID" || log "Installed. Open UZDoom from the Apple TV Home screen."
fi

# === SUCCESS MESSAGE ===

log "UZDoom installed on $DEVICE_NAME."
log "Free Apple ID? The app stops opening after 7 days; run this script again to renew it."
