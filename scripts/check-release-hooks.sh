#!/usr/bin/env bash
# NFR-10: a Release build must contain no E2E test hooks (PRD §6). Full release checks are E2E-15 (M4).
# Usage: scripts/check-release-hooks.sh <path to Purrlo.app>
set -euo pipefail

binary="$1/Contents/MacOS/Purrlo"
pattern='kactl|control\.sock|fake-helper|fake-bluetooth|E2EHooks|ControlServer|CallRecorder|E2E_HOOKS'
[ -f "$binary" ] || { echo "no binary at $binary" >&2; exit 2; }

if matches="$( (strings -a "$binary"; nm -a "$binary" 2>/dev/null) | grep -E "$pattern" | sort -u)"; then
    echo "NFR-10 failed: test hooks found in the Release binary:" >&2
    echo "$matches" >&2
    exit 1
fi
echo "NFR-10: no test hooks in $binary"
