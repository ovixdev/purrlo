#!/usr/bin/env bash
# E2E-4 (FR-3, FR-9, EC-7): the target disappears → Waiting within 1 s, assertion released, lid flag cleared.
source "$(dirname "$0")/lib/common.sh"
e2e_setup
plan 6

start_streaming
check "E2E-4: precondition, the assertion is held while Streaming" expect_assertion_held

vdev_destroy
check "E2E-4, FR-3: Waiting within 1 s of the target disappearing" kactl wait waiting --timeout 1
check "E2E-4, FR-9: assertion released" expect_no_assertion
helper_cleared() {
    kactl calls | json "[c['call'] for c in r]" | grep -q 'helper.setSleepDisabled(false)' || { kactl calls; return 1; }
}
check "E2E-4, A4: the fake helper got setSleepDisabled(false)" helper_cleared
check "E2E-4, FR-3: BlackHole is no longer driven" within 1 test "$(kactl device-running "$BLACKHOLE")" = 0
check "E2E-4, FR-8: status says Waiting for the target" \
    expect_status text "Waiting for $TARGET_NAME · Sleep allowed: no speaker connected"
