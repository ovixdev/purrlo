import CoreAudio
import Darwin

public enum SignalKind: String, Sendable, Codable, CaseIterable { case tone, silence }

/// Fills non-interleaved Float32 buffers. Real-time safe: no allocation, locks, Objective-C or ARC traffic in `render`.
public struct SignalGenerator: Sendable {
    public static let toneFrequency: Double = 30
    public static let toneAmplitude: Float = 0.001

    /// 0 is silence, anything else is the tone. One aligned word so a signal change does not restart the HAL.
    private var kindBits: Int32
    public var kind: SignalKind {
        kindBits == 0 ? .silence : .tone
    }

    public let sampleRate: Double
    /// Phase accumulator, always in [0, 2π).
    private(set) var phase: Double = 0
    private let phaseIncrement: Double

    public init(kind: SignalKind, sampleRate: Double) {
        precondition(sampleRate > 0, "sampleRate must be positive")
        kindBits = kind == .silence ? 0 : 1
        self.sampleRate = sampleRate
        phaseIncrement = 2 * Double.pi * Self.toneFrequency / sampleRate
    }

    /// Next callback uses `kind`. Does not touch the phase.
    public mutating func setKind(_ kind: SignalKind) {
        kindBits = kind == .silence ? 0 : 1
    }

    /// Writes `frameCount` frames into every buffer of `bufferList` (one buffer per channel, Float32).
    /// Each frame's sample is computed once and written to all channels. Never writes past a buffer's mDataByteSize.
    public mutating func render(frameCount: UInt32, into bufferList: UnsafeMutablePointer<AudioBufferList>) {
        // Plain `while` loops: `for ... in` over a range is not specialised in debug builds and allocates there.
        let buffers = BufferListView(bufferList)
        let stride = MemoryLayout<Float>.stride
        let frames = Int(frameCount)
        // Load once per callback. `storeKind` writes this word from the main thread without exclusive access.
        if kindBits == 0 {
            var index = 0
            while index < buffers.count {
                let buffer = buffers[index]
                if let data = buffer.mData {
                    memset(data, 0, min(frames, Int(buffer.mDataByteSize) / stride) * stride)
                }
                index += 1
            }
        } else {
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

    /// Writes the kind word of a live generator. Raw store, so it does not take exclusive access while `render` runs.
    static func storeKind(_ kind: SignalKind, in generator: UnsafeMutablePointer<SignalGenerator>) {
        let desired: Int32 = kind == .silence ? 0 : 1
        guard let offset = MemoryLayout<SignalGenerator>.offset(of: \.kindBits) else {
            preconditionFailure("kindBits is a stored property")
        }
        UnsafeMutableRawPointer(generator).advanced(by: offset).storeBytes(of: desired, as: Int32.self)
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
