#!/usr/bin/env bash
# Captures raw store screenshots from the Connect IQ simulator using demo data.
# Needs Accessibility permission for the terminal/IDE (System Settings >
# Privacy & Security > Accessibility). Output: bin/shots/raw/*.png
#
#   scripts/shots.sh                      all widget and watch face screens
#   scripts/shots.sh face-venu3 ...       only the named shots (see SHOT_LIST)
#   scripts/shots.sh glance-venu3         the glance: set Settings > Glance Launch
#                                         Mode > Launch in Glance Mode first (that
#                                         menu can't be automated), Normal after
#
# Then run scripts/gen_store_images.py to frame them for the store.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SDK="$(cat "$HOME/Library/Application Support/Garmin/ConnectIQ/current-sdk.cfg")"
SDK="${SDK%/}"
KEY="${CIQ_KEY:-$HOME/.garmin/keys/developer_key.der}"
SHOTS="$ROOT/bin/shots"
RAW="$SHOTS/raw"
mkdir -p "$RAW"

# Build an app whose username defaults to demo<kind>.
build_demo() { # app device kind
    local app=$1 dev=$2 kind=$3
    local res="$SHOTS/res-$kind"
    mkdir -p "$res/settings"
    printf '<properties>\n    <property id="username" type="string">demo%s</property>\n</properties>\n' "$kind" \
        > "$res/settings/properties.xml"
    # The simulator keeps storage and settings per app ID, so give every demo
    # build its own ID; otherwise each run inherits the previous one's data.
    local id
    id=$(uuidgen | tr -d '-' | tr '[:upper:]' '[:lower:]')
    sed -E "s/(<iq:application id=\")[0-9a-f]+\"/\1$id\"/" "$ROOT/$app/manifest.xml" > "$ROOT/$app/.shot-manifest.xml"
    sed -e "s|^base.resourcePath = \(.*\)$|base.resourcePath = \1;\"$res\"|" \
        -e "s|^project.manifest = .*|project.manifest = .shot-manifest.xml|" \
        "$ROOT/$app/monkey.jungle" > "$ROOT/$app/.shot.jungle"
    "$SDK/bin/monkeyc" -f "$ROOT/$app/.shot.jungle" -d "$dev" -o "$SHOTS/$app-$dev-$kind.prg" \
        -y "$KEY" -w 2>&1 | grep -E "ERROR|BUILD" || true
    rm -f "$ROOT/$app/.shot.jungle" "$ROOT/$app/.shot-manifest.xml"
    rm -rf "$res"
}

sim() { # AppleScript statements run against the simulator process (retried while it's busy)
    for _ in 1 2 3 4 5; do
        if osascript -e "tell application \"System Events\" to tell process \"simulator\"
set frontmost to true
$1
end tell" >/dev/null 2>&1; then
            return 0
        fi
        sleep 2
    done
    echo "simulator automation failed" >&2
    return 1
}

LAST_DEVICE=""
launch() { # prg device
    "$SDK/bin/monkeydo" "$1" "$2" >/dev/null 2>&1 &
    # Switching the simulator to a different device takes longer.
    if [[ "$2" != "$LAST_DEVICE" ]]; then
        sleep 25
    else
        sleep 12
    fi
    LAST_DEVICE="$2"
}

background_event() {
    sim "click menu item \"Background Events\" of menu 1 of menu bar item \"Simulation\" of menu bar 1
delay 1.5
click button \"OK\" of window \"Background Events\""
    sleep 5
}

FOLDER_SET=""
capture() { # name
    rm -f "$RAW/$1.png"
    # The save panel remembers its folder, so only navigate there the first time.
    local goto=""
    if [[ -z "$FOLDER_SET" ]]; then
        goto="keystroke \"g\" using {command down, shift down}
delay 1
keystroke \"a\" using {command down}
keystroke \"$RAW/\"
delay 1
key code 36
delay 1.5"
        FOLDER_SET=1
    fi
    sim "click menu item \"Save Screen Capture\" of menu 1 of menu bar item \"File\" of menu bar 1
delay 2
perform action \"AXRaise\" of window \"Save\"
delay 0.5
$goto
keystroke \"a\" using {command down}
keystroke \"$1\"
delay 0.5
key code 36
delay 2"
    [[ -f "$RAW/$1.png" ]] && echo "captured $1" || echo "FAILED $1"
}

open_sim() {
    pgrep -x simulator >/dev/null || { open "$SDK/bin/ConnectIQ.app"; sleep 8; }
}

# name                app        device       demo kind   background fetch
SHOT_LIST="
widget-venu3-normal   widget     venu3        -           no
widget-venu3-high     widget     venu3        high        no
widget-venu3-low      widget     venu3        low         no
widget-venu3-gap      widget     venu3        gap         no
face-venu3            watchface  venu3        -           yes
widget-vivoactive3    widget     vivoactive3  -           no
face-vivoactive3      watchface  vivoactive3  -           yes
glance-venu3          widget     venu3        -           yes
"

# Default: everything except the glance (that needs glance mode set by hand).
WANTED=("$@")
if [[ ${#WANTED[@]} -eq 0 ]]; then
    WANTED=($(echo "$SHOT_LIST" | awk 'NF && $1 != "glance-venu3" {print $1}'))
fi

echo "Building demo apps..."
while read -r name app dev kind _; do
    [[ -z "$name" || ! " ${WANTED[*]} " == *" $name "* ]] && continue
    [[ "$kind" == "-" ]] && kind=""
    [[ -f "$SHOTS/$app-$dev-$kind.prg" ]] || build_demo "$app" "$dev" "$kind"
done <<< "$SHOT_LIST"

open_sim
while read -r name app dev kind bg; do
    [[ -z "$name" || ! " ${WANTED[*]} " == *" $name "* ]] && continue
    [[ "$kind" == "-" ]] && kind=""
    launch "$SHOTS/$app-$dev-$kind.prg" "$dev"
    [[ "$bg" == "yes" ]] && background_event
    capture "$name"
done <<< "$SHOT_LIST"

rm -f "$SHOTS"/*.prg "$SHOTS"/*.json "$SHOTS"/*.debug.xml
