#!/usr/bin/env bash
# E2E-5 (FR-2, FR-6): quit and relaunch → same target by UID, Streaming within 2 s; Keep alive off persists too.
source "$(dirname "$0")/lib/common.sh"
e2e_setup
plan 6

start_streaming
kactl set signal silence >/dev/null
app_quit
check "E2E-5, FR-3: quitting releases the stream" within 1 test "$(kactl device-running "$TARGET_UID")" = 0

app_launch
check "E2E-5, FR-2: Streaming within 2 s of relaunch" kactl wait streaming --timeout 2
check "E2E-5, FR-2: the same target by UID" expect_status targetUID "$TARGET_UID"
check "E2E-5, FR-4: the signal setting persisted" expect_status signal silence

kactl set keepAlive false >/dev/null
check "E2E-5, FR-6: turning Keep alive off stops streaming" kactl wait off --timeout 1
app_quit
app_launch
check "E2E-5, FR-6: Keep alive off persists across launches" expect_status state off
