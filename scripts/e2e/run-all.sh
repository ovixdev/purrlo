#!/usr/bin/env bash
# Runs every scripts/e2e/NN_*.sh scenario against the E2E build (PRD §8, L3).
# Writes TAP per scenario, JUnit XML, the app log and the transition logs to $E2E_ARTIFACTS.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$here/../.." && pwd)"
export E2E_ARTIFACTS="${E2E_ARTIFACTS:-$root/build/e2e-artifacts}"
rm -rf "$E2E_ARTIFACTS"
mkdir -p "$E2E_ARTIFACTS"

shopt -s nullglob
scenarios=("$here"/[0-9][0-9]_*.sh)
if ((${#scenarios[@]} == 0)); then
    echo "1..0 # SKIP no E2E scenarios yet"
    exit 0
fi

started="$(date '+%Y-%m-%d %H:%M:%S')"
failed=()
for scenario in "${scenarios[@]}"; do
    name="$(basename "$scenario" .sh)"
    echo "# $name"
    if ! "$scenario" | tee "$E2E_ARTIFACTS/$name.tap"; then
        failed+=("$name")
    fi
done

python3 -I "$here/lib/tap2junit.py" "$E2E_ARTIFACTS/junit.xml" "$E2E_ARTIFACTS"/*.tap
log show --info --start "$started" --predicate 'subsystem == "io.github.ovixdev.purrlo.e2e"' --style compact \
    >"$E2E_ARTIFACTS/app.log" 2>/dev/null || true

if ((${#failed[@]} > 0)); then
    echo "# FAILED: ${failed[*]}"
    exit 1
fi
echo "# all ${#scenarios[@]} scenarios passed; artifacts in $E2E_ARTIFACTS"
