import CoreAudio
import Foundation
import KeepAliveCore

/// Captures channel 0 of a device's input (BlackHole loops its output back to its input), `kactl record` (PRD §8).
public enum Recorder {
    public struct Recording: Sendable {
        public let sampleRate: Double
        public let samples: [Float]
    }

    public static func record(uid: String, seconds: Double) throws -> Recording {
        guard let id = CoreAudioProperty.deviceID(forUID: uid) else {
            throw CoreAudioError(operation: "find \(uid)", status: kAudioHardwareBadDeviceError)
        }
        let rate = CoreAudioProperty.value(id, kAudioDevicePropertyNominalSampleRate, as: Float64.self) ?? 48000
        let capacity = Int(rate * seconds)
        let sink = CaptureSink(capacity: capacity)
        defer { sink.free() }

        var proc: AudioDeviceIOProcID?
        var status = AudioDeviceCreateIOProcIDWithBlock(&proc, id, nil) { _, input, _, _, _ in
            sink.append(UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: input)))
        }
        guard status == noErr,
              let proc else { throw CoreAudioError(operation: "create IOProc on \(uid)", status: status) }
        defer { AudioDeviceDestroyIOProcID(id, proc) }

        status = AudioDeviceStart(id, proc)
        guard status == noErr else { throw CoreAudioError(operation: "start capture on \(uid)", status: status) }
        let deadline = Date().addingTimeInterval(seconds + 5)
        while !sink.isFull, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }
        AudioDeviceStop(id, proc)
        guard sink.isFull else {
            throw CoreAudioError(
                operation: "capture \(seconds) s from \(uid) (device stalled)",
                status: kAudioHardwareNotRunningError
            )
        }
        return Recording(sampleRate: rate, samples: sink.samples())
    }

    /// Mono 32-bit float WAV (format tag 3), read by `scripts/e2e/lib/assert_signal.py`.
    public static func wavData(_ recording: Recording) -> Data {
        var data = Data()
        func append(_ value: some FixedWidthInteger) {
            withUnsafeBytes(of: value.littleEndian) { data.append(contentsOf: $0) }
        }
        let byteCount = UInt32(recording.samples.count * 4)
        data.append(contentsOf: Array("RIFF".utf8))
        append(UInt32(36) + byteCount)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append(UInt32(16))
        append(UInt16(3))
        append(UInt16(1))
        append(UInt32(recording.sampleRate))
        append(UInt32(recording.sampleRate) * 4)
        append(UInt16(4))
        append(UInt16(32))
        data.append(contentsOf: Array("data".utf8))
        append(byteCount)
        for sample in recording.samples {
            append(sample.bitPattern)
        }
        return data
    }
}

/// Preallocated capture buffer written by the IO thread and read after the device stops.
private final class CaptureSink: @unchecked Sendable {
    private let storage: UnsafeMutablePointer<Float>
    private let capacity: Int
    private var count = 0

    init(capacity: Int) {
        self.capacity = capacity
        storage = .allocate(capacity: capacity)
    }

    var isFull: Bool {
        count >= capacity
    }

    func append(_ buffers: UnsafeMutableAudioBufferListPointer) {
        guard let buffer = buffers.first, let data = buffer.mData, buffer.mNumberChannels > 0 else { return }
        let stride = Int(buffer.mNumberChannels)
        let frames = Int(buffer.mDataByteSize) / (MemoryLayout<Float>.size * stride)
        let samples = data.assumingMemoryBound(to: Float.self)
        var frame = 0
        while frame < frames, count < capacity {
            storage[count] = samples[frame * stride]
            count += 1
            frame += 1
        }
    }

    func samples() -> [Float] {
        Array(UnsafeBufferPointer(start: storage, count: min(count, capacity)))
    }

    func free() {
        storage.deallocate()
    }
}
