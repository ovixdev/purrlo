#!/usr/bin/env bash
# E2E-3 (FR-3, EC-5): switching the default output elsewhere does not move the stream.
source "$(dirname "$0")/lib/common.sh"
e2e_setup
plan 5

start_streaming
kactl default-output "$OTHER_DEVICE"
check "E2E-3: the default output is now another device" test "$(kactl default-output)" = "$OTHER_DEVICE"
sleep 1
check "E2E-3, EC-5: the target is still Streaming" expect_status state streaming
check "E2E-3, EC-5: the target is still driven" test "$(kactl device-running "$TARGET_UID")" = 1
check "E2E-3, EC-5: the other device is not driven by the app" test "$(kactl device-running "$OTHER_DEVICE")" = 0
check "E2E-3, FR-4: the tone still reaches the target" expect_signal tone
