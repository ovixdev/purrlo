#!/usr/bin/env bash
# E2E-9 (FR-12): unlock connects once, then the speaker returning reaches Streaming within 2 s.
source "$(dirname "$0")/lib/common.sh"
TARGET_UID="E2-E0-00-00-00-01:output"
TARGET_NAME="E2E Speaker"
e2e_setup
plan 4

start_streaming
kactl simulate will-sleep >/dev/null
vdev_destroy
kactl simulate did-wake >/dev/null
kactl simulate unlock >/dev/null

one_open() { [ "$(call_count "bluetooth.openConnection")" = "1" ]; }
check "E2E-9, FR-12: one openConnection after unlock" within 2 one_open
vdev_create
check "E2E-9, FR-12: Streaming within 2 s of the speaker returning" kactl wait streaming --timeout 2
check "E2E-9, FR-5: still exactly one openConnection" one_open
check "E2E-9: status is Streaming" expect_status state streaming
