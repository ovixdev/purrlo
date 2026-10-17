#!/usr/bin/env bash
# E2E-6 (FR-3, EC-6): BlackHole 48 kHz → 44.1 kHz → exactly one engine restart, signal still correct.
source "$(dirname "$0")/lib/common.sh"
e2e_setup
plan 5

restarts() { kactl transitions | json 'sum(1 for e in r for f in e["effects"] if f.startswith("restartEngine"))'; }

start_streaming
check "E2E-6: precondition, the target runs at 48 kHz" test "$(kactl vdev rate --uid "$TARGET_UID")" = 48000
before="$(restarts)"

kactl vdev set-rate --uid "$BLACKHOLE" 44100
check "E2E-6, EC-6: the target follows BlackHole to 44.1 kHz" within 2 test "$(kactl vdev rate --uid "$TARGET_UID")" = 44100
sleep 1
one_restart() {
    local count=$(($(restarts) - before))
    [ "$count" -eq 1 ] || { echo "$count restarts"; kactl transitions; return 1; }
}
check "E2E-6, EC-6: exactly one engine restart in the log" one_restart
check "E2E-6, FR-3: still Streaming" expect_status state streaming
check "E2E-6, FR-4: the tone is correct at 44.1 kHz" expect_signal tone
