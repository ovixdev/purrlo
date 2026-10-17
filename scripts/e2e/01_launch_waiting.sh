#!/usr/bin/env bash
# E2E-1 (EC-1, FR-8, FR-9): launch with no target present → Waiting, no assertion, no retries.
source "$(dirname "$0")/lib/common.sh"
e2e_setup
plan 8

reset_app_state
app_launch
check "E2E-1: fresh launch is Waiting" expect_status state waiting
check "E2E-1, FR-8: status asks to choose a speaker and says sleep is allowed" \
    expect_status text "Choose a speaker · Sleep allowed: no speaker connected"
check "E2E-1, FR-9: no assertion from the app in pmset -g assertions" expect_no_assertion

kactl set-target "$TARGET_UID" >/dev/null
check "E2E-1, EC-1: an absent target leaves the app Waiting" expect_status state waiting
check "E2E-1, FR-9: still no assertion with an absent target" expect_no_assertion
app_quit

app_launch
check "E2E-1, EC-1: relaunch with the persisted target absent is Waiting" expect_status state waiting
check "E2E-1, FR-9: no assertion after relaunch" expect_no_assertion
sleep 2
no_engine_attempts() {
    local starts
    starts="$(kactl transitions | json 'sum(1 for e in r for f in e["effects"] if "Engine" in f)')"
    [ "$starts" = "0" ] || { echo "$starts engine effects while the target was absent"; return 1; }
}
check "E2E-1, EC-1: no engine start or retry while the target is absent" no_engine_attempts
