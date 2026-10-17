#!/usr/bin/env python3
"""PRD §8 signal assertion on a WAV captured with `kactl record` (standard library only).

Tone mode:    dominant frequency 30 Hz ± 1 Hz; RMS within ±20% of 0.000707;
              no run of zero samples longer than 20 ms.
Silence mode: all samples zero.

Usage: assert_signal.py tone|silence FILE.wav [--skip SECONDS]
Prints one line of measurements; exits 0 on pass, 1 on fail, 2 on bad input.
"""

import argparse
import math
import struct
import sys

TONE_HZ = 30.0
TONE_TOLERANCE_HZ = 1.0
TONE_RMS = 0.001 / math.sqrt(2)
RMS_TOLERANCE = 0.20
MAX_ZERO_RUN_S = 0.020


def read_wav(path):
    """Returns (sample_rate, samples) for mono or multi-channel 32-bit float or 16/32-bit PCM (channel 0)."""
    with open(path, "rb") as handle:
        data = handle.read()
    if data[:4] != b"RIFF" or data[8:12] != b"WAVE":
        raise ValueError("not a RIFF/WAVE file")
    offset, fmt, payload = 12, None, None
    while offset + 8 <= len(data):
        chunk_id, size = data[offset : offset + 4], struct.unpack_from("<I", data, offset + 4)[0]
        body = data[offset + 8 : offset + 8 + size]
        if chunk_id == b"fmt ":
            fmt = struct.unpack_from("<HHIIHH", body)
        elif chunk_id == b"data":
            payload = body
        offset += 8 + size + (size & 1)
    if fmt is None or payload is None:
        raise ValueError("missing fmt or data chunk")
    tag, channels, rate, _, block, bits = fmt
    frames = len(payload) // block
    if tag == 3 and bits == 32:
        values = struct.unpack_from(f"<{frames * channels}f", payload)
    elif tag == 1 and bits in (16, 32):
        code, scale = ("h", 32768.0) if bits == 16 else ("i", 2147483648.0)
        values = [v / scale for v in struct.unpack_from(f"<{frames * channels}{code}", payload)]
    else:
        raise ValueError(f"unsupported WAV format tag {tag}, {bits} bits")
    return float(rate), list(values[::channels])


def goertzel(samples, frequency, rate):
    coefficient = 2 * math.cos(2 * math.pi * frequency / rate)
    previous = before = 0.0
    for sample in samples:
        previous, before = sample + coefficient * previous - before, previous
    return math.sqrt(max(previous * previous + before * before - coefficient * previous * before, 0.0))


def dominant_frequency(samples, rate):
    """Scans 1-200 Hz on a ~1 kHz decimated copy (block averaging is a low-pass), then refines around the peak."""
    factor = max(1, int(rate // 1000))
    decimated = [sum(samples[i : i + factor]) / factor for i in range(0, len(samples) - factor + 1, factor)]
    low_rate = rate / factor
    best = max((goertzel(decimated, f / 2, low_rate), f / 2) for f in range(2, 401))[1]
    return max((goertzel(decimated, best + d / 20, low_rate), best + d / 20) for d in range(-10, 11))[1]


def longest_zero_run(samples):
    longest = current = 0
    for sample in samples:
        current = current + 1 if sample == 0.0 else 0
        longest = max(longest, current)
    return longest


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("mode", choices=["tone", "silence"])
    parser.add_argument("wav")
    parser.add_argument("--skip", type=float, default=0.3, help="seconds to drop at the start (loopback latency)")
    args = parser.parse_args()

    try:
        rate, samples = read_wav(args.wav)
    except (OSError, ValueError, struct.error) as error:
        print(f"bad input: {error}")
        return 2
    samples = samples[int(rate * args.skip) :]
    if len(samples) < rate:
        print(f"bad input: need at least 1 s after skipping, got {len(samples) / rate:.2f} s")
        return 2

    rms = math.sqrt(sum(s * s for s in samples) / len(samples))
    zero_run_ms = 1000 * longest_zero_run(samples) / rate
    if args.mode == "silence":
        nonzero = sum(1 for s in samples if s != 0.0)
        print(f"silence: {nonzero} non-zero of {len(samples)} samples, rms={rms:.3g}, rate={rate:.0f}")
        return 0 if nonzero == 0 else 1

    frequency = dominant_frequency(samples, rate)
    failures = []
    if abs(frequency - TONE_HZ) > TONE_TOLERANCE_HZ:
        failures.append(f"dominant {frequency:.2f} Hz")
    if abs(rms - TONE_RMS) > TONE_RMS * RMS_TOLERANCE:
        failures.append(f"rms {rms:.6f}")
    if zero_run_ms > MAX_ZERO_RUN_S * 1000:
        failures.append(f"zero run {zero_run_ms:.1f} ms")
    print(
        f"tone: dominant={frequency:.2f} Hz rms={rms:.6f} (expect {TONE_RMS:.6f} ±20%) "
        f"longest zero run={zero_run_ms:.2f} ms rate={rate:.0f}" + (f" FAIL: {', '.join(failures)}" if failures else "")
    )
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
