#!/usr/bin/env bash
# E2E-2 (FR-1, FR-3, FR-4, FR-8, FR-9): the target appears → Streaming within 2 s, signal and assertion verified.
source "$(dirname "$0")/lib/common.sh"
e2e_setup
plan 12

reset_app_state
app_launch
kactl set-target "$TARGET_UID" >/dev/null
lists_target() {
    kactl devices | json "[d['uid'] for d in r]" | grep -q "\"$TARGET_UID\"" || { kactl devices; return 1; }
}

vdev_create
check "E2E-2, FR-3: Streaming within 2 s of the target appearing" kactl wait streaming --timeout 2
check "E2E-2, FR-1: the app lists the virtual target" lists_target
check "E2E-2, FR-4: the inaudible tone reaches the target (30 Hz, -60 dBFS)" expect_signal tone
check "E2E-2, FR-9: PreventUserIdleSystemSleep held by the app" expect_assertion_held
check "E2E-2, FR-8: status says streaming and why sleep is blocked" \
    expect_status text "Streaming to $TARGET_NAME · Sleep blocked while $TARGET_NAME is connected"

set_signal silence
check "E2E-2, FR-4: Silence sends only zeros" expect_signal silence 1.5
check "E2E-2, FR-4: the target keeps running in Silence mode" within 1 test "$(kactl device-running "$TARGET_UID")" = 1
check "E2E-2, FR-3: still Streaming in Silence mode" expect_status state streaming

kactl set preventIdleSleep false >/dev/null
check "E2E-2, FR-9: turning Prevent idle sleep off releases the assertion" expect_no_assertion
check "E2E-2, FR-8: status says why sleep is allowed" \
    expect_status text "Streaming to $TARGET_NAME · Sleep allowed: Prevent idle sleep is off"
kactl set preventIdleSleep true >/dev/null
check "E2E-2, FR-9: turning it back on holds the assertion again" expect_assertion_held

set_signal tone
check "E2E-2, FR-4: switching back to the tone restores it" expect_signal tone
