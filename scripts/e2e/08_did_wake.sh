#!/usr/bin/env bash
# E2E-8 (FR-12, EC-10): a wake without an unlock stays Suspended and never connects.
source "$(dirname "$0")/lib/common.sh"
TARGET_UID="E2-E0-00-00-00-01:output"
TARGET_NAME="E2E Speaker"
e2e_setup
plan 3

start_streaming
kactl simulate will-sleep >/dev/null
kactl simulate did-wake >/dev/null
sleep 30

check "E2E-8: still Suspended 30 s after did-wake" expect_status state suspended
check "E2E-8, FR-12: did-wake does not connect" expect_call_count "bluetooth.openConnection" 0
check "E2E-8, FR-11: the sleep still closed the link" expect_call_count "bluetooth.closeConnection" 1
