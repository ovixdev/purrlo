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

# A disconnect or a sleep needs a typed "go", so stray input (a pipe, a pasted line) can never start one.
confirm_go() {
    local answer=""
    while [ "$answer" != "go" ]; do
        printf '%s' "$1"
        read -r answer || exit 1
    done
}

# E2E-H3. Drives the Debug app (it has real Bluetooth; the E2E app does not) and reads the unified log.
run_h3() {
    local debug_app nap start_stamp log_file announced appeared passed
    debug_app="${DEBUG_APP:-$ROOT/build/DerivedData/Build/Products/Debug/Purrlo.app}"
    [ -d "$debug_app" ] || { echo "Debug build missing; run make e2e-hardware-h3"; exit 1; }
    [ -x "$KACTL" ] || { echo "kactl missing; run make e2e-hardware-h3"; exit 1; }

    nap="$(pmset -g 2>/dev/null | awk 'tolower($1) == "powernap" { print $2; exit }')"
    if [ "$nap" != "1" ]; then
        echo "Power Nap is off, so this run would not exercise a dark wake."
        echo "Turn it on yourself, then run this again:"
        echo "  sudo pmset -a powernap 1"
        exit 1
    fi

    say "Purrlo hardware suite: E2E-H3 (overnight Power Nap)"
    cat <<EOF
This sleeps the Mac with \`pmset sleepnow\` and checks the Debug app's log after you wake it.
The E2E app is not used: it has no Bluetooth.

Before you start:
  - Quit Purrlo if it is running.
  - Connect the speaker. Launch will be the Debug build at:
      $debug_app
  - In the menu, pick that speaker and wait until the status says Streaming.
  - Plug in power. Lid open. Power Nap is already on; this script will not change it.
  - macOS may ask for Bluetooth permission for Purrlo at launch. Allow it.
  - If the speaker is still disconnected at the end, kactl may ask for Bluetooth permission
    for this terminal, and only then, to reconnect it. This script never disconnects by itself.

Stdin from /dev/null stops at the next question, before sleep and before any Bluetooth command.
EOF

    if pgrep -x Purrlo >/dev/null; then
        echo "Purrlo is running. Quit it from its menu, then run this again."
        exit 1
    fi

    confirm_go "Type go and press Return when you have read this. The Mac will not sleep yet: "
    open "$debug_app"
    echo "Pick the speaker in the Purrlo menu and wait until it says Streaming."
    confirm_go "Type go and press Return to sleep the Mac now: "

    start_stamp="$(date '+%Y-%m-%d %H:%M:%S')"
    pmset sleepnow
    sleep 3

    log_file="$ROOT/build/e2e-h3.log"
    mkdir -p "$ROOT/build"
    log show --info --start "$start_stamp" --style compact \
        --predicate 'subsystem == "io.github.ovixdev.purrlo"' >"$log_file" 2>/dev/null || true

    announced="$(ask "Did the speaker announce itself before you unlocked?" "a) no|b) yes")"
    appeared="$(ask "Did the speaker show up in the menu before you unlocked?" "a) no|b) yes")"
    restore_choice="$(ask "Is the speaker still disconnected?" "a) no, it is connected|b) yes, reconnect it")"
    if [ "$restore_choice" = "b" ]; then
        echo "Reconnecting uses kactl spike. macOS may ask to allow Bluetooth for this terminal."
        restore_speaker
    fi

    VERSION="$(/usr/libexec/PlistBuddy -c 'Print CFBundleShortVersionString' "$debug_app/Contents/Info.plist")"
    REPORT="$ROOT/e2e-report-$VERSION-$MAC_MODEL.json"
    if python3 -I - "$REPORT" "$log_file" "$announced" "$appeared" "$SPEAKER_NAME_H3" "$VERSION" "$MAC_MODEL" <<'PY'
import json, os, platform, sys
report_path, log_path, announced, appeared, speaker, version, mac = sys.argv[1:8]
lines = []
if os.path.exists(log_path):
    lines = [line for line in open(log_path, errors="replace") if "-->" in line]
unlock_at = next((i for i, line in enumerate(lines) if "screenUnlocked" in line), None)
disconnects = [line for line in lines if "systemWillSleep" in line and "disconnectBluetooth" in line]
if unlock_at is None:
    connects_before, connects_after = [line for line in lines if "connectBluetooth" in line], []
else:
    connects_before = [line for line in lines[:unlock_at] if "connectBluetooth" in line]
    connects_after = [line for line in lines[unlock_at:] if "connectBluetooth" in line]
passed = len(disconnects) == 1 and len(connects_before) == 0 and len(connects_after) == 1
result = {
    "id": "E2E-H3",
    "scenario": "Power Nap: disconnect on sleep, reconnect once after unlock",
    "announced_before_unlock": announced == "b",
    "device_appeared_before_unlock": appeared == "b",
    "disconnect_on_will_sleep": len(disconnects),
    "connect_before_unlock": len(connects_before),
    "connect_after_unlock": len(connects_after),
    "passed": passed,
}
report = {}
if os.path.exists(report_path):
    with open(report_path) as handle:
        report = json.load(handle)
report.setdefault("suite", "hardware")
report["version"] = version or report.get("version")
report["mac"] = mac or report.get("mac")
report["macos"] = platform.mac_ver()[0]
if speaker:
    report["speaker"] = speaker
results = [item for item in report.get("results", []) if item.get("id") != "E2E-H3"]
results.append(result)
report["results"] = results
with open(report_path, "w") as handle:
    json.dump(report, handle, indent=2)
    handle.write("\n")
sys.exit(0 if passed else 1)
PY
    then
        passed=true
    else
        passed=false
    fi
    say "E2E-H3 result: $([ "$passed" = true ] && echo passed || echo failed)"
    echo "Log: $log_file"
    echo "Report: $REPORT"
    [ "$passed" = true ]
}

restore_speaker() {
    local choice
    H3_UIDS=()
    H3_NAMES=()
    while IFS= read -r line; do
        H3_UIDS+=("$(printf '%s' "$line" | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["uid"])')")
        H3_NAMES+=("$(printf '%s' "$line" | python3 -I -c 'import json, sys; print(json.load(sys.stdin)["name"])')")
    done < <(kactl spike outputs | grep '"bluetooth":true' || true)
    if [ "${#H3_UIDS[@]}" -eq 0 ]; then
        echo "No Bluetooth output is connected, and none is listed to reconnect."
        return 0
    fi
    say "Bluetooth outputs"
    for i in "${!H3_NAMES[@]}"; do echo "  $((i + 1))) ${H3_NAMES[$i]}"; done
    choice=1
    if [ "${#H3_UIDS[@]}" -gt 1 ]; then
        printf 'Which one should be reconnected? > '
        read -r choice || exit 1
    fi
    kactl spike connect "${H3_UIDS[$((choice - 1))]}" || true
    SPEAKER_NAME_H3="${H3_NAMES[$((choice - 1))]}"
}

SPEAKER_NAME_H3=""
case "${1:-h4}" in
    h3)
        run_h3
        exit
        ;;
    h4) ;;
    *)
        echo "usage: hardware.sh [h3|h4]" >&2
        exit 64
        ;;
esac

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

HEARD='a) no announcement at all|b) announcement, quieter than usual|c) announcement at its usual loudness'

say "Run 1 of 2: Mac-side volume 0"
confirm_go "Type go and press Return when you are ready to listen: "
VOLUME_AFTER_ZERO="$(reconnect 0)"
HEARD_AT_ZERO="$(ask "What did you hear?" "$HEARD")"

say "Run 2 of 2: Mac-side volume 50%"
confirm_go "Type go and press Return when you are ready to listen: "
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
