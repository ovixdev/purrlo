#!/usr/bin/env bash
# E2E-7 (FR-11): Streaming + will-sleep → Suspended in under 5 s, link closed, assertion released.
source "$(dirname "$0")/lib/common.sh"
TARGET_UID="E2-E0-00-00-00-01:output"
TARGET_NAME="E2E Speaker"
e2e_setup
plan 7

start_streaming

under_five() {
    local start
    start="$(python3 -I -c 'import time; print(time.time())')"
    kactl simulate will-sleep >/dev/null
    python3 -I -c 'import sys, time; sys.exit(0 if time.time() - float(sys.argv[1]) < 5 else 1)' "$start"
}
sleep_order() {
    kactl transitions | python3 -I -c '
import json, sys
entries = json.load(sys.stdin)["result"]
effects = next((e["effects"] for e in entries if e["event"] == "systemWillSleep"), None)
if effects is None:
    print("no systemWillSleep transition")
    sys.exit(1)
want = ["disconnectBluetooth", "setLidBlock(false)", "releaseAssertion", "allowSleep"]
positions = []
for name in want:
    indexes = [i for i, effect in enumerate(effects) if name in effect]
    if not indexes:
        print("missing", name, effects)
        sys.exit(1)
    positions.append(indexes[0])
if positions != sorted(positions):
    print(effects)
    sys.exit(1)
if any("Volume" in effect for effect in effects):
    print(effects)
    sys.exit(1)
'
}

check "E2E-7, FR-11: will-sleep returns in under 5 s" under_five
check "E2E-7: status is Suspended" expect_status state suspended
check "E2E-7, FR-9: assertion released" expect_no_assertion
check "E2E-7, FR-11: one bluetooth.closeConnection" expect_call_count "bluetooth.closeConnection" 1
check "E2E-7, A4: one helper.setSleepDisabled(false)" expect_call_count "helper.setSleepDisabled(false)" 1
check "E2E-7: disconnect, clear lid block, release, allow sleep, no volume" sleep_order
check "E2E-7, FR-5: will-sleep does not connect" expect_call_count "bluetooth.openConnection" 0
