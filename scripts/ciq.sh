#!/usr/bin/env bash
# Build, run and package the Connect IQ apps from the command line / IntelliJ.
#
#   scripts/ciq.sh build   <widget|watchface> [device]   debug build (default device: vivoactive3)
#   scripts/ciq.sh run     <widget|watchface> [device]   build and launch in the simulator
#   scripts/ciq.sh release <widget|watchface> [device]   release .prg for sideloading to a watch
#   scripts/ciq.sh sideload <widget|watchface> [device]  release .prg with your Dexcom login from local.env
#   scripts/ciq.sh package <widget|watchface>            store-ready .iq for every device in the manifest
#   scripts/ciq.sh beta    <widget|watchface>            same, with the beta app ID (upload as "Beta App")
#   scripts/ciq.sh check   <widget|watchface>            compile for every device in the manifest
#
# Environment overrides: CIQ_SDK (SDK folder), CIQ_KEY (developer_key.der).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CIQ_HOME="$HOME/Library/Application Support/Garmin/ConnectIQ"
SDK="${CIQ_SDK:-$(cat "$CIQ_HOME/current-sdk.cfg" 2>/dev/null || true)}"
SDK="${SDK%/}"
KEY="${CIQ_KEY:-$HOME/.garmin/keys/developer_key.der}"

cmd="${1:-}"
app="${2:-}"
device="${3:-vivoactive3}"

if [[ -z "$cmd" || -z "$app" ]]; then
    sed -n '2,12p' "$0"
    exit 1
fi
if [[ ! -x "$SDK/bin/monkeyc" ]]; then
    echo "Connect IQ SDK not found. Install it with the SDK Manager or set CIQ_SDK." >&2
    exit 1
fi
if [[ ! -f "$KEY" ]]; then
    echo "Developer key not found at $KEY (set CIQ_KEY)." >&2
    exit 1
fi

JUNGLE="$ROOT/$app/monkey.jungle"
OUT="$ROOT/bin"
mkdir -p "$OUT"

compile() { # device output [extra args...]
    local dev="$1" out="$2"
    shift 2
    "$SDK/bin/monkeyc" -f "$JUNGLE" -d "$dev" -o "$out" -y "$KEY" -w "$@"
}

case "$cmd" in
    build)
        compile "$device" "$OUT/$app-$device.prg"
        ;;
    run)
        compile "$device" "$OUT/$app-$device.prg"
        if ! pgrep -f "ConnectIQ.app" >/dev/null; then
            open "$SDK/bin/ConnectIQ.app"
            sleep 4
        fi
        "$SDK/bin/monkeydo" "$OUT/$app-$device.prg" "$device"
        ;;
    release)
        compile "$device" "$OUT/$app-$device-release.prg" -r
        echo "Copy $OUT/$app-$device-release.prg to GARMIN/APPS on the watch."
        ;;
    sideload)
        # Sideloaded apps can't receive settings from the phone, so bake the
        # Dexcom login from local.env (git-ignored) into this build only.
        ENV_FILE="$ROOT/local.env"
        if [[ ! -f "$ENV_FILE" ]]; then
            echo "Create $ENV_FILE first (see local.env.example)." >&2
            exit 1
        fi
        LOCAL_RES="$OUT/sideload-resources"
        mkdir -p "$LOCAL_RES/settings"
        ENV_FILE="$ENV_FILE" python3 - "$LOCAL_RES/settings/properties.xml" <<'PY'
import os, sys
from xml.sax.saxutils import escape
vals = {}
for line in open(os.environ["ENV_FILE"]):
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        k, v = line.split("=", 1)
        vals[k.strip()] = v.strip().strip('"').strip("'")
user, pw = vals.get("DEXCOM_USERNAME", ""), vals.get("DEXCOM_PASSWORD", "")
if not user or not pw:
    sys.exit("DEXCOM_USERNAME and DEXCOM_PASSWORD must be set in local.env")
region = vals.get("DEXCOM_REGION", "0")
with open(sys.argv[1], "w") as f:
    f.write("<properties>\n"
            f'    <property id="username" type="string">{escape(user)}</property>\n'
            f'    <property id="password" type="string">{escape(pw)}</property>\n'
            f'    <property id="region" type="number">{int(region)}</property>\n'
            "</properties>\n")
PY
        SIDE_JUNGLE="$ROOT/$app/.sideload.jungle"
        # Quoted: jungle paths containing spaces must be in quotes.
        sed "s|^base.resourcePath = \(.*\)$|base.resourcePath = \1;\"$LOCAL_RES\"|" "$JUNGLE" > "$SIDE_JUNGLE"
        trap 'rm -f "$SIDE_JUNGLE"; rm -rf "$LOCAL_RES"' EXIT
        "$SDK/bin/monkeyc" -f "$SIDE_JUNGLE" -d "$device" -o "$OUT/$app-$device-sideload.prg" -y "$KEY" -w -r
        echo "Copy $OUT/$app-$device-sideload.prg to GARMIN/APPS on the watch. It contains your password: don't share it."
        ;;
    package)
        "$SDK/bin/monkeyc" -f "$JUNGLE" -e -r -o "$OUT/$app.iq" -y "$KEY" -w
        echo "Upload $OUT/$app.iq at https://apps.garmin.com/developer/upload"
        ;;
    beta)
        # Garmin requires beta uploads to use a different app ID than the
        # production app; swap it in a temporary manifest.
        case "$app" in
            widget) BETA_ID="2c75ea2e04034637bc5acc815739c053" ;;
            watchface) BETA_ID="bf97e654d94f43a3bc4dbf964ae25a2b" ;;
        esac
        BETA_MANIFEST="$ROOT/$app/.beta-manifest.xml"
        BETA_JUNGLE="$ROOT/$app/.beta.jungle"
        sed -E "s/(<iq:application id=\")[0-9a-f]+\"/\1$BETA_ID\"/" "$ROOT/$app/manifest.xml" > "$BETA_MANIFEST"
        sed "s|^project.manifest = .*|project.manifest = .beta-manifest.xml|" "$JUNGLE" > "$BETA_JUNGLE"
        trap 'rm -f "$BETA_MANIFEST" "$BETA_JUNGLE"' EXIT
        "$SDK/bin/monkeyc" -f "$BETA_JUNGLE" -e -r -o "$OUT/$app-beta.iq" -y "$KEY" -w
        echo "Upload $OUT/$app-beta.iq at https://apps.garmin.com/developer/upload with \"Beta App\" checked."
        ;;
    check)
        failed=()
        for dev in $(grep -o 'product id="[^"]*"' "$ROOT/$app/manifest.xml" | cut -d'"' -f2); do
            if compile "$dev" "$OUT/check-$app-$dev.prg" >"$OUT/check-$dev.log" 2>&1; then
                echo "ok      $dev"
            else
                echo "FAILED  $dev  (see bin/check-$dev.log)"
                failed+=("$dev")
            fi
        done
        rm -f "$OUT"/check-"$app"-*.prg*
        [[ ${#failed[@]} -eq 0 ]] || exit 1
        ;;
    *)
        echo "Unknown command: $cmd" >&2
        exit 1
        ;;
esac
