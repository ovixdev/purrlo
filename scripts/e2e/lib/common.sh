# Shared helpers for the L3 E2E scenarios (PRD §8). Source from scripts/e2e/NN_*.sh.
# Bash 3.2 compatible (macOS /bin/bash). Prints TAP on stdout; diagnostics are "# " lines.
set -euo pipefail

E2E_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$E2E_LIB/../../.." && pwd)"
E2E_PRODUCTS="${E2E_PRODUCTS:-$ROOT/build/DerivedData/Build/Products/E2E}"
APP_BIN="$E2E_PRODUCTS/Purrlo.app/Contents/MacOS/Purrlo"
KACTL="$E2E_PRODUCTS/kactl"
BUNDLE_ID="io.github.ovixdev.purrlo.e2e"
TARGET_UID="e2e-speaker"
TARGET_NAME="E2E Speaker"
BLACKHOLE="BlackHole2ch_UID"
OTHER_DEVICE="BlackHole16ch_UID"
ARTIFACTS="${E2E_ARTIFACTS:-$ROOT/build/e2e-artifacts}"
SCENARIO="$(basename "$0" .sh)"
APP_PID=""
TESTS=0
FAILED=0
mkdir -p "$ARTIFACTS"

kactl() { "$KACTL" "$@"; }

# --- TAP -------------------------------------------------------------------

plan() { echo "1..$1"; }
diag() { sed 's/^/# /'; }
ok() {
    TESTS=$((TESTS + 1))
    echo "ok $TESTS - $*"
}
not_ok() {
    TESTS=$((TESTS + 1))
    FAILED=$((FAILED + 1))
    echo "not ok $TESTS - $*"
}

# check "ID: description" command [args...]: one TAP line; the command's output becomes diagnostics on failure.
check() {
    local description="$1"
    shift
    local output
    if output="$("$@" 2>&1)"; then
        ok "$description"
    else
        not_ok "$description"
        printf '%s\n' "$output" | diag
    fi
}

# --- JSON ------------------------------------------------------------------

# json <python expression over `r`, the response's result>, reading kactl JSON on stdin.
json() {
    python3 -I -c 'import json, sys
r = json.load(sys.stdin)["result"]
v = eval(sys.argv[1])
print(json.dumps(v) if isinstance(v, (dict, list)) else ("" if v is None else str(v).lower() if isinstance(v, bool) else v))' "$1"
}

status() { kactl status | json "r[\"$1\"]"; }

expect_status() {
    local field="$1" expected="$2" actual
    actual="$(status "$field")"
    [ "$actual" = "$expected" ] || { echo "status.$field is '$actual', expected '$expected'"; return 1; }
}

# --- App lifecycle ---------------------------------------------------------

app_launch() {
    "$APP_BIN" --fake-bluetooth --fake-helper >>"$ARTIFACTS/$SCENARIO.app-output.txt" 2>&1 &
    APP_PID=$!
    local tries=0
    until kactl status >/dev/null 2>&1; do
        tries=$((tries + 1))
        if [ "$tries" -gt 200 ]; then
            echo "Bail out! app did not open its control socket within 10 s"
            exit 1
        fi
        sleep 0.05
    done
}

app_quit() {
    [ -n "$APP_PID" ] || return 0
    kactl transitions >"$ARTIFACTS/$SCENARIO.transitions.json" 2>/dev/null || true
    kactl calls >"$ARTIFACTS/$SCENARIO.calls.json" 2>/dev/null || true
    kactl quit >/dev/null 2>&1 || true
    local tries=0
    while kill -0 "$APP_PID" 2>/dev/null; do
        tries=$((tries + 1))
        if [ "$tries" -gt 100 ]; then
            kill -9 "$APP_PID" 2>/dev/null || true
            break
        fi
        sleep 0.05
    done
    wait "$APP_PID" 2>/dev/null || true
    APP_PID=""
}

reset_app_state() { defaults delete "$BUNDLE_ID" >/dev/null 2>&1 || true; }

vdev_create() { kactl vdev create --name "$TARGET_NAME" --uid "$TARGET_UID" >/dev/null; }
vdev_destroy() { kactl vdev destroy --uid "$TARGET_UID"; }

# Streaming to the virtual target, with fresh settings.
start_streaming() {
    reset_app_state
    vdev_create
    app_launch
    kactl set-target "$TARGET_UID" >/dev/null
    kactl wait streaming --timeout 2 >/dev/null
}

# --- Assertions ------------------------------------------------------------

# Lines of `pmset -g assertions` for the app's PreventUserIdleSystemSleep assertion.
app_idle_assertions() {
    pmset -g assertions | grep -E "pid $APP_PID\(Purrlo\).*PreventUserIdleSystemSleep" || true
}

expect_assertion_held() {
    [ -n "$(app_idle_assertions)" ] || { pmset -g assertions | grep -i purrlo || echo "no Purrlo assertions"; return 1; }
}

expect_no_assertion() {
    local lines
    lines="$(pmset -g assertions | grep -E "pid $APP_PID\(" || true)"
    [ -z "$lines" ] || { echo "$lines"; return 1; }
}

# expect_signal tone|silence [seconds]: records the BlackHole loopback and runs the PRD §8 assertion.
expect_signal() {
    local mode="$1" seconds="${2:-2.3}" wav
    wav="$ARTIFACTS/$SCENARIO.$mode.$TESTS.wav"
    kactl record --device "$BLACKHOLE" --seconds "$seconds" --out "$wav"
    python3 -I "$E2E_LIB/assert_signal.py" "$mode" "$wav"
}

# within <seconds> <command...>: retries every 20 ms, about <seconds> worth of attempts, then shows the last output.
# Timing-critical state checks use `kactl wait` instead, which measures in-process.
within() {
    local attempts
    attempts="$(awk "BEGIN { print int($1 * 50) }")"
    shift
    while [ "$attempts" -gt 0 ]; do
        if "$@" >/dev/null 2>&1; then return 0; fi
        attempts=$((attempts - 1))
        sleep 0.02
    done
    "$@"
}

# --- Setup and teardown ----------------------------------------------------

ORIGINAL_DEFAULT_OUTPUT=""
ORIGINAL_BLACKHOLE_RATE=""

e2e_setup() {
    [ -x "$APP_BIN" ] && [ -x "$KACTL" ] || { echo "Bail out! E2E build missing; run make build-e2e"; exit 1; }
    pkill -f "$APP_BIN" 2>/dev/null || true
    vdev_destroy 2>/dev/null || true
    ORIGINAL_DEFAULT_OUTPUT="$(kactl default-output)"
    ORIGINAL_BLACKHOLE_RATE="$(kactl vdev rate --uid "$BLACKHOLE")"
    [ "$ORIGINAL_BLACKHOLE_RATE" = "48000" ] || kactl vdev set-rate --uid "$BLACKHOLE" 48000
    trap e2e_teardown EXIT
}

e2e_teardown() {
    local code=$?
    app_quit
    vdev_destroy 2>/dev/null || true
    if [ -n "$ORIGINAL_BLACKHOLE_RATE" ] && [ "$(kactl vdev rate --uid "$BLACKHOLE")" != "$ORIGINAL_BLACKHOLE_RATE" ]; then
        kactl vdev set-rate --uid "$BLACKHOLE" "$ORIGINAL_BLACKHOLE_RATE" || true
    fi
    if [ -n "$ORIGINAL_DEFAULT_OUTPUT" ] && [ "$ORIGINAL_DEFAULT_OUTPUT" != "none" ] \
        && [ "$(kactl default-output)" != "$ORIGINAL_DEFAULT_OUTPUT" ]; then
        kactl default-output "$ORIGINAL_DEFAULT_OUTPUT" || true
    fi
    reset_app_state
    if [ "$code" -ne 0 ] && [ "$FAILED" -eq 0 ]; then exit "$code"; fi
    [ "$FAILED" -eq 0 ] || echo "# $SCENARIO: $FAILED of $TESTS failed"
    exit $((FAILED > 0 ? 1 : 0))
}
