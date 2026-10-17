import CoreAudio
import Foundation
@testable import KeepAliveCore
import KeepAliveTestSupport
import Testing

extension L2Hardware {
    @MainActor
    @Suite("AUHALEngine against BlackHole")
    struct EngineIntegrationTests {
        private let uid = VirtualDevice.blackHole2chUID

        private func blackHole() throws -> AudioDevice {
            let id = try #require(VirtualDevice.deviceID(uid: uid))
            return try #require(CoreAudioHardware.device(for: id))
        }

        /// Drops the first `seconds` of a recording, which may hold loopback latency or older buffer contents.
        private func settled(_ recording: Recorder.Recording, skipping seconds: Double = 0.3) -> ArraySlice<Float> {
            recording.samples.dropFirst(Int(recording.sampleRate * seconds))
        }

        @Test("FR-3: streams to the target within 2 s and stops within 1 s")
        func startsAndStops() async throws {
            let engine = AUHALEngine()
            try engine.start(device: blackHole(), signal: .tone)
            #expect(engine.isRunning)
            #expect(await waitUntil(timeout: .seconds(2)) { VirtualDevice.isRunningSomewhere(uid: uid) })

            engine.stop()
            #expect(!engine.isRunning)
            #expect(await waitUntil(timeout: .seconds(1)) { !VirtualDevice.isRunningSomewhere(uid: uid) })
            engine.stop() // idempotent
        }

        @Test("FR-4: the recorded tone is 30 Hz at about -60 dBFS")
        func recordsTone() throws {
            let engine = AUHALEngine()
            try engine.start(device: blackHole(), signal: .tone)
            defer { engine.stop() }
            let recording = try Recorder.record(uid: uid, seconds: 2.3)
            expectTone(settled(recording), sampleRate: recording.sampleRate)
        }

        @Test("FR-4: silence sends only zeros while the device keeps running")
        func recordsSilence() throws {
            let engine = AUHALEngine()
            try engine.start(device: blackHole(), signal: .silence)
            defer { engine.stop() }
            let recording = try Recorder.record(uid: uid, seconds: 1.3)
            #expect(settled(recording).allSatisfy { $0 == 0 })
            #expect(VirtualDevice.isRunningSomewhere(uid: uid))
        }

        @Test("FR-4: silence then tone keeps the device running and does not drop the tone")
        func signalChangeDoesNotDropOut() throws {
            let engine = AUHALEngine()
            let device = try blackHole()
            try engine.start(device: device, signal: .silence)
            defer { engine.stop() }
            try engine.start(device: device, signal: .tone)
            #expect(engine.isRunning)
            #expect(VirtualDevice.isRunningSomewhere(uid: uid))
            let recording = try Recorder.record(uid: uid, seconds: 2.3)
            let samples = settled(recording)
            expectTone(samples, sampleRate: recording.sampleRate)
            let limit = Int(recording.sampleRate * 0.020)
            #expect(longestZeroRun(samples) <= limit, "zero run exceeds 20 ms")
        }

        @Test("EC-5: switching the default output does not move the stream")
        func ignoresDefaultOutput() async throws {
            let original = try #require(VirtualDevice.defaultOutputUID())
            defer { try? VirtualDevice.setDefaultOutput(uid: original) }
            let engine = AUHALEngine()
            try engine.start(device: blackHole(), signal: .tone)
            defer { engine.stop() }

            try VirtualDevice.setDefaultOutput(uid: VirtualDevice.blackHole16chUID)
            try await Task.sleep(for: .milliseconds(300))
            #expect(VirtualDevice.isRunningSomewhere(uid: uid))
            #expect(!VirtualDevice.isRunningSomewhere(uid: VirtualDevice.blackHole16chUID))
            let recording = try Recorder.record(uid: uid, seconds: 1.3)
            expectTone(settled(recording), sampleRate: recording.sampleRate)
        }

        @Test("EC-6: after a sample-rate change the restarted engine streams at the new rate")
        func restartsAtNewRate() async throws {
            let original = try #require(VirtualDevice.nominalSampleRate(uid: uid))
            let other: Double = original == 44100 ? 48000 : 44100
            let engine = AUHALEngine()
            try engine.start(device: blackHole(), signal: .tone)
            defer { engine.stop() }

            try await withBlackHoleRate(other) {
                let device = try blackHole()
                #expect(device.nominalSampleRate == other)
                try engine.start(device: device, signal: .tone)
                let recording = try Recorder.record(uid: uid, seconds: 2.3)
                #expect(recording.sampleRate == other)
                expectTone(settled(recording), sampleRate: other)
            }
        }

        @Test("EC-4: another stream to the same device mixes with ours")
        func mixesWithOtherClients() throws {
            let ours = AUHALEngine()
            let theirs = AUHALEngine()
            try ours.start(device: blackHole(), signal: .tone)
            defer { ours.stop() }
            try theirs.start(device: blackHole(), signal: .silence)
            defer { theirs.stop() }
            #expect(ours.isRunning && theirs.isRunning)
            let recording = try Recorder.record(uid: uid, seconds: 2.3)
            expectTone(settled(recording), sampleRate: recording.sampleRate)
        }

        @Test("FR-3: starting on a device that does not exist fails cleanly")
        func missingDeviceFails() {
            let engine = AUHALEngine()
            let ghost = AudioDevice(
                uid: "ghost", objectID: 0xDEAD, name: "Ghost", transport: .virtual,
                outputChannels: 2, nominalSampleRate: 48000, isAlive: true
            )
            #expect(throws: EngineError.self) { try engine.start(device: ghost, signal: .tone) }
            #expect(!engine.isRunning)
        }
    }
}
