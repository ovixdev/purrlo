import CoreAudio
import Darwin

public enum SignalKind: String, Sendable, Codable, CaseIterable { case tone, silence }

/// Fills non-interleaved Float32 buffers. Real-time safe: no allocation, locks, Objective-C or ARC traffic in `render`.
public struct SignalGenerator: Sendable {
    public static let toneFrequency: Double = 30
    public static let toneAmplitude: Float = 0.001

    public let kind: SignalKind
    public let sampleRate: Double
    /// Phase accumulator, always in [0, 2π).
    private(set) var phase: Double = 0
    private let phaseIncrement: Double

    public init(kind: SignalKind, sampleRate: Double) {
        precondition(sampleRate > 0, "sampleRate must be positive")
        self.kind = kind
        self.sampleRate = sampleRate
        phaseIncrement = 2 * Double.pi * Self.toneFrequency / sampleRate
    }

    /// Writes `frameCount` frames into every buffer of `bufferList` (one buffer per channel, Float32).
    /// Each frame's sample is computed once and written to all channels. Never writes past a buffer's mDataByteSize.
    public mutating func render(frameCount: UInt32, into bufferList: UnsafeMutablePointer<AudioBufferList>) {
        // Plain `while` loops: `for ... in` over a range is not specialised in debug builds and allocates there.
        let buffers = BufferListView(bufferList)
        let stride = MemoryLayout<Float>.stride
        let frames = Int(frameCount)
        switch kind {
        case .silence:
            var index = 0
            while index < buffers.count {
                let buffer = buffers[index]
                if let data = buffer.mData {
                    memset(data, 0, min(frames, Int(buffer.mDataByteSize) / stride) * stride)
                }
                index += 1
            }
        case .tone:
            let twoPi = 2 * Double.pi
            var phase = phase
            var frame = 0
            while frame < frames {
                let sample = Self.toneAmplitude * Float(sin(phase))
                var index = 0
                while index < buffers.count {
                    let buffer = buffers[index]
                    if let data = buffer.mData, frame < Int(buffer.mDataByteSize) / stride {
                        data.assumingMemoryBound(to: Float.self)[frame] = sample
                    }
                    index += 1
                }
                phase += phaseIncrement
                while phase >= twoPi {
                    phase -= twoPi
                }
                frame += 1
            }
            self.phase = phase
        }
    }
}

/// Allocation-free view of an `AudioBufferList`'s trailing buffer array.
private struct BufferListView {
    private let first: UnsafeMutablePointer<AudioBuffer>
    let count: Int

    init(_ list: UnsafeMutablePointer<AudioBufferList>) {
        // `mBuffers` is the last field, so it starts where the fixed header ends.
        let header = MemoryLayout<AudioBufferList>.size - MemoryLayout<AudioBuffer>.size
        first = (UnsafeMutableRawPointer(list) + header).assumingMemoryBound(to: AudioBuffer.self)
        count = Int(list.pointee.mNumberBuffers)
    }

    subscript(index: Int) -> AudioBuffer {
        first[index]
    }
}
