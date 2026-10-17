#!/usr/bin/env bash
# L6 hardware suite (PRD §8), run by a person with a real Echo. M1 ships E2E-H4, the FR-13 spike:
# does the "Now connected to…" announcement follow the Mac-side volume?
# Writes e2e-report-<version>-<mac>.json for `gh release upload`. Bash 3.2 compatible.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
E2E_PRODUCTS="${E2E_PRODUCTS:-$ROOT/build/DerivedData/Build/Products/E2E}"
KACTL="$E2E_PRODUCTS/kactl"
APP_PLIST="$E2E_PRODUCTS/Purrlo.app/Contents/Info.plist"
SETTLE_SECONDS=5

kactl() { "$KACTL" "$@"; }
say() { printf '\n\033[1m%s\033[0m\n' "$*"; }

[ -x "$KACTL" ] || { echo "E2E build missing; run make e2e-hardware"; exit 1; }
VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$APP_PLIST")"
MAC_MODEL="$(sysctl -n hw.model)"
REPORT="$ROOT/e2e-report-$VERSION-$MAC_MODEL.json"

# ask "question" "a) answer|b) answer|..." → prints the chosen letter.
ask() {
    local question="$1" options="$2" answer letters
    letters="$(printf '%s' "$options" | tr '|' '\n' | cut -c1 | tr -d '\n')"
    while true; do
        printf '%s\n' "$question" >&2
        printf '%s\n' "$options" | tr '|' '\n' | sed 's/^/   /' >&2
        printf '> ' >&2
        read -r answer || exit 1
        case "$answer" in
            [$letters]) printf '%s' "$answer"; return 0 ;;
        esac
        echo "Please type one of: $(printf '%s' "$letters" | sed 's/./& /g')" >&2
    done
}

say "Purrlo hardware suite: E2E-H4 (FR-13 quiet reconnect spike)"
cat <<EOF
This test disconnects and reconnects your speaker twice with kactl, once with the Mac-side volume
at 0 and once at 50%, and asks what you heard. It takes about two minutes.

Before you start:
  - Quit Purrlo if it is running.
  - Connect the Echo to this Mac and stay close enough to hear it.
  - macOS may ask to allow Bluetooth for your terminal app. Allow it, then start this script again.
  - Your original volume is restored at the end, also if you press Ctrl-C.
EOF

if pgrep -x Purrlo >/dev/null; then
    echo "Purrlo is running. Quit it from its menu, then run this again."
    exit 1
fi

# --- Pick the speaker -----------------------------------------------------

UIDS=()
NAMES=()
while IFS= read -r line; do
    UIDS+=("$(printf '%s' "$line" | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["uid"])')")
    NAMES+=("$(printf '%s' "$line" | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["name"])')")
done < <(kactl spike outputs | grep '"bluetooth":true')

if [ "${#UIDS[@]}" -eq 0 ]; then
    echo "No Bluetooth output is connected. Connect the Echo and run this again."
    exit 1
fi
say "Bluetooth outputs"
for i in "${!NAMES[@]}"; do echo "  $((i + 1))) ${NAMES[$i]}"; done
choice=1
if [ "${#UIDS[@]}" -gt 1 ]; then
    printf 'Which one is the Echo? > '
    read -r choice
fi
[ "$choice" -ge 1 ] 2>/dev/null && [ "$choice" -le "${#UIDS[@]}" ] || { echo "No such speaker"; exit 1; }
SPEAKER_UID="${UIDS[$((choice - 1))]}"
SPEAKER_NAME="${NAMES[$((choice - 1))]}"
ORIGINAL_VOLUME="$(kactl spike volume "$SPEAKER_UID")"
echo "Testing $SPEAKER_NAME (current Mac-side volume $ORIGINAL_VOLUME)."

restore() {
    if ! kactl spike wait-present "$SPEAKER_UID" true --timeout 0 >/dev/null 2>&1; then
        echo "Reconnecting $SPEAKER_NAME"
        kactl spike connect "$SPEAKER_UID" || true
        kactl spike wait-present "$SPEAKER_UID" true --timeout 20 >/dev/null || true
    fi
    kactl spike volume "$SPEAKER_UID" "$ORIGINAL_VOLUME" 2>/dev/null && echo "Volume restored to $ORIGINAL_VOLUME." || true
}
# Restore on any exit, including Ctrl-C and kill, so the speaker is never left disconnected or muted.
trap restore EXIT
trap 'exit 130' INT TERM HUP

# --- One reconnect --------------------------------------------------------

# reconnect <volume>: sets the volume, disconnects, waits, reconnects; prints the volume found after reconnecting.
reconnect() {
    local volume="$1" after
    kactl spike volume "$SPEAKER_UID" "$volume"
    sleep 1
    echo "Disconnecting…" >&2
    kactl spike disconnect "$SPEAKER_UID"
    kactl spike wait-present "$SPEAKER_UID" false --timeout 15 >/dev/null
    sleep "$SETTLE_SECONDS"
    echo "Reconnecting now. Listen to the Echo." >&2
    kactl spike connect "$SPEAKER_UID"
    kactl spike wait-present "$SPEAKER_UID" true --timeout 30 >/dev/null
    sleep 4
    after="$(kactl spike volume "$SPEAKER_UID")"
    printf '%s' "$after"
}

# A disconnect needs a typed "go", so stray input (a pipe, a pasted line) can never start one.
confirm_go() {
    local answer=""
    while [ "$answer" != "go" ]; do
        printf 'Type go and press Return when you are ready to listen: '
        read -r answer || exit 1
    done
}

HEARD='a) no announcement at all|b) announcement, quieter than usual|c) announcement at its usual loudness'

say "Run 1 of 2: Mac-side volume 0"
confirm_go
VOLUME_AFTER_ZERO="$(reconnect 0)"
HEARD_AT_ZERO="$(ask "What did you hear?" "$HEARD")"

say "Run 2 of 2: Mac-side volume 50%"
confirm_go
VOLUME_AFTER_HALF="$(reconnect 0.5)"
HEARD_AT_HALF="$(ask "What did you hear?" "$HEARD")"

trap - EXIT
restore

# --- Verdict and report ---------------------------------------------------

# a < b < c in loudness: FR-13 helps only if volume 0 sounded quieter than 50%.
if [[ "$HEARD_AT_ZERO" < "$HEARD_AT_HALF" ]]; then
    VERDICT="keep FR-13"
    PASSED=true
else
    VERDICT="drop FR-13"
    PASSED=false
fi

python3 -I - "$REPORT" <<EOF
import json, platform, subprocess, sys
heard = {"a": "none", "b": "quieter", "c": "usual"}
report = {
    "suite": "hardware",
    "version": "$VERSION",
    "mac": "$MAC_MODEL",
    "macos": platform.mac_ver()[0],
    "speaker": "$SPEAKER_NAME",
    "results": [{
        "id": "E2E-H4",
        "scenario": "FR-13 spike: reconnect with the Mac-side volume at 0, then at 50%",
        "runs": [
            {"volume": 0.0, "volume_after_reconnect": float("$VOLUME_AFTER_ZERO"), "heard": heard["$HEARD_AT_ZERO"]},
            {"volume": 0.5, "volume_after_reconnect": float("$VOLUME_AFTER_HALF"), "heard": heard["$HEARD_AT_HALF"]},
        ],
        "passed": $( [ "$PASSED" = true ] && echo True || echo False ),
        "verdict": "$VERDICT",
    }],
}
with open(sys.argv[1], "w") as handle:
    json.dump(report, handle, indent=2)
    handle.write("\n")
EOF

say "E2E-H4 result: $VERDICT"
echo "At volume 0 you heard: $(printf '%s' "$HEARD" | tr '|' '\n' | grep "^$HEARD_AT_ZERO)" | cut -c4-)"
echo "At volume 50% you heard: $(printf '%s' "$HEARD" | tr '|' '\n' | grep "^$HEARD_AT_HALF)" | cut -c4-)"
echo "Mac-side volume right after reconnecting: $VOLUME_AFTER_ZERO (set to 0) and $VOLUME_AFTER_HALF (set to 0.5)"
echo "Report: $REPORT"
