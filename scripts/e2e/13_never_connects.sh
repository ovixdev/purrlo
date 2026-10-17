#!/usr/bin/env bash
# E2E-13 (FR-5): only the unlock scenarios may call openConnection.
# Does not launch the app. Counts the calls files this run already wrote.
# 09 and 10 are required and must hold exactly the opens their scenarios expect (1 and 2), so an
# app that never connects cannot pass vacuously. Every other *.calls.json must contain zero
# openConnection, including 11 when M3 adds it (it sorts before this script).
source "$(dirname "$0")/lib/common.sh"
plan 3

required() {
    [ -f "$ARTIFACTS/$1" ] || { echo "missing $ARTIFACTS/$1 (run the full suite, do not run 13 alone)"; return 1; }
}
only_unlock_connects() {
    python3 -I - "$ARTIFACTS" <<'PY'
import glob, json, os, sys
artifacts = sys.argv[1]
allow = {"09_unlock_reconnect.calls.json": 1, "10_reconnect_fails.calls.json": 2}
for name in sorted(allow):
    if not os.path.isfile(os.path.join(artifacts, name)):
        print("missing", name)
        sys.exit(1)
for path in sorted(glob.glob(os.path.join(artifacts, "*.calls.json"))):
    base = os.path.basename(path)
    result = json.load(open(path))["result"]
    opens = [c for c in result if "bluetooth.openConnection" in c.get("call", "")]
    if len(opens) != allow.get(base, 0):
        print(base, "has", len(opens), "bluetooth.openConnection, expected", allow.get(base, 0))
        sys.exit(1)
PY
}

check "E2E-13: 09_unlock_reconnect wrote a calls file" required "09_unlock_reconnect.calls.json"
check "E2E-13: 10_reconnect_fails wrote a calls file" required "10_reconnect_fails.calls.json"
check "E2E-13, FR-5: openConnection only in E2E-9 (once) and E2E-10 (twice)" only_unlock_connects
[ "$FAILED" -eq 0 ]
