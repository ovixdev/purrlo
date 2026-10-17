#!/usr/bin/env bash
# Line-coverage gate for KeepAliveCore sources (PRD §8). Run after `swift test --enable-code-coverage`.
# Usage: scripts/coverage.sh <package-path> <minimum-percent>
set -euo pipefail

package="$1"
minimum="$2"
json="$(swift test --package-path "$package" --show-codecov-path)"

python3 -I - "$json" "$minimum" "$(cd "$package" && pwd)/Sources/KeepAliveCore/" <<'PY'
import json, sys

path, minimum, sources = sys.argv[1], float(sys.argv[2]), sys.argv[3]
report = json.load(open(path))["data"][0]["files"]
package_root = sources.rsplit("/Sources/", 1)[0] + "/"
if not any(f["filename"].startswith(package_root) for f in report):
    sys.exit(f"coverage report has no files under {package_root}; the path filter is broken")

files = [f for f in report if f["filename"].startswith(sources)]
covered = sum(f["summary"]["lines"]["covered"] for f in files)
total = sum(f["summary"]["lines"]["count"] for f in files)
if total == 0:
    print("KeepAliveCore has no executable source lines yet; nothing to gate")
    sys.exit(0)
percent = 100.0 * covered / total

for f in sorted(files, key=lambda f: f["summary"]["lines"]["percent"]):
    lines = f["summary"]["lines"]
    print(f'{lines["percent"]:6.1f}%  {lines["covered"]:5}/{lines["count"]:<5}  {f["filename"][len(sources):]}')
print(f"KeepAliveCore line coverage: {percent:.1f}% (minimum {minimum:.0f}%)")
sys.exit(0 if percent >= minimum else 1)
PY
