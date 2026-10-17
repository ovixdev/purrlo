#!/usr/bin/env bash
# Runs every scripts/e2e/NN_*.sh scenario against the E2E build (PRD §8, L3).
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
shopt -s nullglob
scenarios=("$here"/[0-9][0-9]_*.sh)

if ((${#scenarios[@]} == 0)); then
    echo "1..0 # SKIP no E2E scenarios yet"
    exit 0
fi

failed=0
for scenario in "${scenarios[@]}"; do
    echo "# $(basename "$scenario")"
    "$scenario" || failed=1
done
exit "$failed"
