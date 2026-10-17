import Foundation
import KeepAliveTestSupport
import Testing

/// Every L2 suite that touches the BlackHole devices nests here so they never run concurrently.
@Suite(.serialized)
enum L2Hardware {}

/// Polls `condition` on the main actor every 10 ms until it holds or `timeout` passes.
@MainActor
func waitUntil(timeout: Duration, _ condition: () -> Bool) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if condition() {
            return true
        }
        try? await Task.sleep(for: .milliseconds(10))
    }
    return condition()
}

/// Runs `body` with BlackHole 2ch at `rate`, restoring the previous rate afterwards.
@MainActor
func withBlackHoleRate<T>(_ rate: Double, _ body: () async throws -> T) async throws -> T {
    let uid = VirtualDevice.blackHole2chUID
    let original = try #require(VirtualDevice.nominalSampleRate(uid: uid))
    try VirtualDevice.setNominalSampleRate(rate, uid: uid)
    defer { try? VirtualDevice.setNominalSampleRate(original, uid: uid) }
    _ = await waitUntil(timeout: .seconds(2)) { VirtualDevice.nominalSampleRate(uid: uid) == rate }
    return try await body()
}

/// Single-bin DFT magnitude (Goertzel) of `samples` at `frequency`.
func magnitude(of samples: ArraySlice<Float>, at frequency: Double, sampleRate: Double) -> Double {
    let coefficient = 2 * cos(2 * Double.pi * frequency / sampleRate)
    var previous = 0.0
    var beforePrevious = 0.0
    for sample in samples {
        let current = Double(sample) + coefficient * previous - beforePrevious
        beforePrevious = previous
        previous = current
    }
    return sqrt(previous * previous + beforePrevious * beforePrevious - coefficient * previous * beforePrevious)
}

func rms(_ samples: ArraySlice<Float>) -> Double {
    sqrt(samples.reduce(0) { $0 + Double($1) * Double($1) } / Double(max(samples.count, 1)))
}

/// PRD §8 tone assertion: dominant 30 Hz and RMS within ±20% of 0.000707.
func expectTone(_ samples: ArraySlice<Float>, sampleRate: Double, sourceLocation: SourceLocation = #_sourceLocation) {
    let atTone = magnitude(of: samples, at: 30, sampleRate: sampleRate)
    for other in [10.0, 20, 25, 35, 40, 60, 120, 440] {
        #expect(
            atTone > 10 * magnitude(of: samples, at: other, sampleRate: sampleRate),
            "30 Hz is not dominant over \(other) Hz",
            sourceLocation: sourceLocation
        )
    }
    #expect(abs(rms(samples) - 0.000707) < 0.000707 * 0.2, "RMS \(rms(samples))", sourceLocation: sourceLocation)
}
