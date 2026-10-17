import CoreAudio
import Foundation
@testable import KeepAliveCore
import Testing

private let sampleRates: [Double] = [8000, 16000, 44100, 48000, 96000]
private let amplitude = Double(SignalGenerator.toneAmplitude)

/// Goertzel magnitude of `samples` at `frequency`.
private func magnitude(_ samples: [Float], frequency: Double, sampleRate: Double) -> Double {
    let omega = 2 * Double.pi * frequency / sampleRate
    let coefficient = 2 * cos(omega)
    var previous = 0.0
    var beforePrevious = 0.0
    for sample in samples {
        let current = Double(sample) + coefficient * previous - beforePrevious
        beforePrevious = previous
        previous = current
    }
    return (previous * previous + beforePrevious * beforePrevious - coefficient * previous * beforePrevious)
        .squareRoot()
}

private func render(
    _ kind: SignalKind, rate: Double, frames: Int, chunk: Int? = nil, channels: Int = 1
) -> AudioTestBuffers {
    let buffers = AudioTestBuffers(channels: channels, frames: frames)
    var generator = SignalGenerator(kind: kind, sampleRate: rate)
    guard let chunk else {
        generator.render(frameCount: UInt32(frames), into: buffers.pointer)
        return buffers
    }
    // Render chunk by chunk through a scratch list, then copy into the full-size buffers.
    let scratch = AudioTestBuffers(channels: channels, frames: chunk)
    var done = 0
    while done < frames {
        let count = min(chunk, frames - done)
        generator.render(frameCount: UInt32(count), into: scratch.pointer)
        for channel in 0 ..< channels {
            let part = scratch.samples(channel)[0 ..< count]
            let target = buffers.list[channel].mData?.assumingMemoryBound(to: Float.self)
            for (offset, value) in part.enumerated() {
                target?[done + offset] = value
            }
        }
        done += count
    }
    return buffers
}

@Suite("SignalGenerator")
struct SignalGeneratorTests {
    @Test("FR-4: tone has dominant frequency 30 Hz, 1% RMS and peak at most 0.001", arguments: sampleRates)
    func toneSpectrumAndLevel(rate: Double) {
        let samples = render(.tone, rate: rate, frames: Int(rate)).samples(0)

        let spectrum = (1 ... 200).map { magnitude(samples, frequency: Double($0), sampleRate: rate) }
        let dominant = (spectrum.indices.max { spectrum[$0] < spectrum[$1] } ?? -1) + 1
        #expect(abs(dominant - 30) <= 1)
        let at30 = magnitude(samples, frequency: 30, sampleRate: rate)
        for other in [20.0, 25, 35, 40, 60] {
            #expect(at30 > 100 * magnitude(samples, frequency: other, sampleRate: rate))
        }

        let rms = (samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(samples.count)).squareRoot()
        #expect(abs(rms - amplitude / 2.0.squareRoot()) < 0.01 * amplitude / 2.0.squareRoot())
        #expect((samples.map { abs($0) }.max() ?? 1) <= SignalGenerator.toneAmplitude)
    }

    @Test("FR-4: tone constants are 30 Hz at amplitude 0.001")
    func toneConstants() {
        #expect(SignalGenerator.toneFrequency == 30)
        #expect(SignalGenerator.toneAmplitude == 0.001)
        let generator = SignalGenerator(kind: .tone, sampleRate: 48000)
        #expect(generator.kind == .tone)
        #expect(generator.sampleRate == 48000)
        #expect(SignalKind.allCases == [.tone, .silence])
    }

    @Test("FR-4: phase is continuous across render calls of any size", arguments: [512, 37, 1])
    func phaseContinuity(chunk: Int) {
        let frames = 48000
        let whole = render(.tone, rate: 48000, frames: frames).samples(0)
        let pieces = render(.tone, rate: 48000, frames: frames, chunk: chunk).samples(0)
        let worst = zip(whole, pieces).map { abs($0 - $1) }.max() ?? 1
        #expect(worst < 1e-7)
    }

    @Test("FR-4: no run of exactly-zero samples longer than 20 ms in tone mode", arguments: sampleRates)
    func noLongZeroRuns(rate: Double) {
        let samples = render(.tone, rate: rate, frames: Int(rate) * 2).samples(0)
        var longest = 0
        var current = 0
        for sample in samples {
            current = sample == 0 ? current + 1 : 0
            longest = max(longest, current)
        }
        #expect(Double(longest) / rate <= 0.020)
    }

    @Test("FR-4: silence is exactly zero, even over garbage", arguments: sampleRates)
    func silenceIsZero(rate: Double) {
        let buffers = AudioTestBuffers(channels: 2, frames: 1024, fill: 0.75)
        var generator = SignalGenerator(kind: .silence, sampleRate: rate)
        generator.render(frameCount: 1024, into: buffers.pointer)
        for channel in 0 ..< 2 {
            #expect(buffers.samples(channel).allSatisfy { $0 == 0 })
            #expect(buffers.guardFramesAreUntouched(channel))
        }
    }

    @Test("FR-4: every channel gets identical samples", arguments: [2, 6])
    func identicalChannels(channels: Int) {
        let buffers = render(.tone, rate: 48000, frames: 1000, channels: channels)
        let first = buffers.samples(0)
        #expect(first.contains { $0 != 0 })
        for channel in 1 ..< channels {
            #expect(buffers.samples(channel) == first)
        }
    }

    @Test("FR-4: never writes past a buffer's mDataByteSize", arguments: SignalKind.allCases)
    func respectsByteSize(kind: SignalKind) {
        let buffers = AudioTestBuffers(capacities: [256, 100, 0, 300])
        var generator = SignalGenerator(kind: kind, sampleRate: 48000)
        generator.render(frameCount: 256, into: buffers.pointer)
        for channel in 0 ..< 4 {
            #expect(buffers.guardFramesAreUntouched(channel))
        }
        // Frames beyond the shorter buffer are still written to the longer ones, and the short one is filled.
        let reference = render(kind, rate: 48000, frames: 256).samples(0)
        #expect(buffers.samples(0) == reference)
        #expect(buffers.samples(1) == Array(reference[0 ..< 100]))
        #expect(buffers.samples(3)[0 ..< 256] == reference[0 ..< 256])
        #expect(buffers.samples(3)[256...].allSatisfy { $0 == AudioTestBuffers.sentinel })
    }

    @Test("FR-4: a buffer without data and an empty list are skipped", arguments: SignalKind.allCases)
    func toleratesMissingData(kind: SignalKind) {
        let list = AudioBufferList.allocate(maximumBuffers: 1)
        defer { free(list.unsafeMutablePointer) }
        list[0] = AudioBuffer(mNumberChannels: 1, mDataByteSize: 400, mData: nil)
        var generator = SignalGenerator(kind: kind, sampleRate: 48000)
        generator.render(frameCount: 100, into: list.unsafeMutablePointer)
        let empty = AudioBufferList.allocate(maximumBuffers: 1)
        defer { free(empty.unsafeMutablePointer) }
        empty.unsafeMutablePointer.pointee.mNumberBuffers = 0
        generator.render(frameCount: 100, into: empty.unsafeMutablePointer)
    }

    @Test("FR-4: accumulator stays in [0, 2π) and amplitude stays correct over a long run")
    func longRun() {
        // 24 h at 48 kHz is 4.1e9 frames, too slow for L1; 2e6 frames (about 42 s) is checked against the closed form.
        let rate = 48000.0
        let chunk = 4096
        let buffers = AudioTestBuffers(channels: 1, frames: chunk)
        var generator = SignalGenerator(kind: .tone, sampleRate: rate)
        var rendered = 0
        while rendered < 2_000_000 {
            generator.render(frameCount: UInt32(chunk), into: buffers.pointer)
            rendered += chunk
            #expect(generator.phase >= 0 && generator.phase < 2 * Double.pi)
        }
        let samples = buffers.samples(0)
        let start = rendered - chunk
        for (offset, sample) in samples.enumerated() {
            let expected = amplitude * sin(2 * Double.pi * 30 * Double(start + offset) / rate)
            #expect(abs(Double(sample) - expected) < 1e-8)
        }
    }

    @Test("FR-4: low sample rates still wrap the accumulator")
    func lowSampleRateWraps() {
        // 30 Hz at 10 Hz sample rate advances 6π per frame.
        var generator = SignalGenerator(kind: .tone, sampleRate: 10)
        let buffers = AudioTestBuffers(channels: 1, frames: 64)
        generator.render(frameCount: 64, into: buffers.pointer)
        #expect(generator.phase >= 0 && generator.phase < 2 * Double.pi)
    }

    @Test(
        "NFR-3: render performs no heap allocation",
        .enabled(if: AllocationCounter.isAvailable, Comment(rawValue: AllocationCounter.unavailableReason ?? "")),
        arguments: SignalKind.allCases
    )
    func renderDoesNotAllocate(kind: SignalKind) {
        let buffers = AudioTestBuffers(channels: 2, frames: 512)
        var generator = SignalGenerator(kind: kind, sampleRate: 48000)
        generator.render(frameCount: 512, into: buffers.pointer)
        let pointer = buffers.pointer
        // `while`, not `for ... in`: range iteration allocates in unoptimised builds and would hide the result.
        let allocations = AllocationCounter.count {
            var remaining = 10000
            while remaining > 0 {
                generator.render(frameCount: 512, into: pointer)
                remaining -= 1
            }
        }
        #expect(allocations == 0)
    }
}

@Suite(
    "AllocationCounter",
    .enabled(if: AllocationCounter.isAvailable, Comment(rawValue: AllocationCounter.unavailableReason ?? ""))
)
struct AllocationCounterTests {
    private nonisolated(unsafe) static var sink: UnsafeMutableRawPointer?
    private nonisolated(unsafe) static var arraySink: [Int] = []

    @Test("NFR-3: the counter detects malloc on the watched thread")
    func detectsMalloc() {
        let allocations = AllocationCounter.count {
            Self.sink = malloc(64)
            free(Self.sink)
            Self.sink = nil
        }
        #expect(allocations >= 1)
    }

    @Test("NFR-3: the counter detects a Swift array allocation")
    func detectsArray() {
        let allocations = AllocationCounter.count {
            Self.arraySink = [Int](repeating: 7, count: 100)
        }
        Self.arraySink = []
        #expect(allocations >= 1)
    }

    @Test("NFR-3: the counter reports zero for pure math")
    func zeroForMath() {
        nonisolated(unsafe) var total = 0.0
        let allocations = AllocationCounter.count {
            var index = 0
            while index < 1000 {
                total += sin(Double(index))
                index += 1
            }
        }
        #expect(allocations == 0)
        #expect(total != 12345)
    }
}
