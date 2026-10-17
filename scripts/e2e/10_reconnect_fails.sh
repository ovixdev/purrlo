#!/usr/bin/env bash
# E2E-10 (EC-11): a failed reconnect is tried once more about 10 s later, then never again.
source "$(dirname "$0")/lib/common.sh"
TARGET_UID="E2-E0-00-00-00-01:output"
TARGET_NAME="E2E Speaker"
e2e_setup
plan 4

start_streaming
kactl simulate will-sleep >/dev/null
vdev_destroy
wait_target_gone
kactl set fake-connect fail >/dev/null
kactl simulate did-wake >/dev/null
kactl simulate unlock >/dev/null

two_opens_ten_seconds_apart() {
    kactl calls | python3 -I -c '
import json, sys
opens = [c["time"] for c in json.load(sys.stdin)["result"] if "bluetooth.openConnection" in c["call"]]
if len(opens) != 2:
    print("openConnection count", len(opens))
    sys.exit(1)
delta = opens[1] - opens[0]
# The product retry stays 10 s. Task.sleep wakes late on a busy runner: CI recorded 11.03 s
# (run 39062332805) with no machine change. A retry under 9 s is still a failure.
if not 9 <= delta <= 12:
    print("delta", delta)
    sys.exit(1)
'
}
check "E2E-10, EC-11: two openConnection calls about 10 s apart; a loaded runner may wake the timer late" \
    within 15 two_opens_ten_seconds_apart
check "E2E-10: stays Waiting after the retry fails" kactl wait waiting --timeout 2
sleep 60
check "E2E-10, EC-11: no third attempt after another 60 s" expect_call_count "bluetooth.openConnection" 2
check "E2E-10: still Waiting" expect_status state waiting
