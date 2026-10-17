#!/usr/bin/env bash
# Prepares the CI test environment (PRD §8): BlackHole 2ch (the virtual target's base) and 16ch (the
# "other device" of E2E-3), visible to CoreAudio. Idempotent; needs sudo only when it must install or restart.
set -euo pipefail

visible() {
    system_profiler SPAudioDataType 2>/dev/null | grep -q "BlackHole 2ch:" &&
        system_profiler SPAudioDataType 2>/dev/null | grep -q "BlackHole 16ch:"
}

for cask in blackhole-2ch blackhole-16ch; do
    if ! brew list --cask "$cask" >/dev/null 2>&1; then
        echo "installing $cask"
        HOMEBREW_NO_AUTO_UPDATE=1 brew install --cask "$cask"
    fi
done

if ! visible; then
    echo "restarting coreaudiod so it loads the BlackHole drivers"
    sudo killall coreaudiod || true
    for _ in $(seq 1 60); do
        visible && break
        sleep 1
    done
fi

if visible; then
    echo "BlackHole 2ch and 16ch are visible to CoreAudio"
else
    echo "BlackHole devices did not appear; installed drivers:" >&2
    ls /Library/Audio/Plug-Ins/HAL/ >&2 || true
    exit 1
fi
