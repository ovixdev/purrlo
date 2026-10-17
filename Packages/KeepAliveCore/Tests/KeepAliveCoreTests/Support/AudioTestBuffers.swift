import CoreAudio

/// Non-interleaved Float32 test buffers with sentinel-filled guard frames after each buffer's declared size.
final class AudioTestBuffers {
    static let guardFrames = 16
    static let sentinel: Float = 0.5

    let fill: Float

    let list: UnsafeMutableAudioBufferListPointer
    let capacities: [Int]
    private let storage: [UnsafeMutablePointer<Float>]

    /// `capacities[i]` is the number of frames buffer `i` declares in `mDataByteSize`.
    init(capacities: [Int], fill: Float = AudioTestBuffers.sentinel) {
        self.capacities = capacities
        self.fill = fill
        list = AudioBufferList.allocate(maximumBuffers: capacities.count)
        storage = capacities.map { capacity in
            let pointer = UnsafeMutablePointer<Float>.allocate(capacity: capacity + Self.guardFrames)
            pointer.initialize(repeating: fill, count: capacity + Self.guardFrames)
            return pointer
        }
        for (index, capacity) in capacities.enumerated() {
            list[index] = AudioBuffer(
                mNumberChannels: 1,
                mDataByteSize: UInt32(capacity * MemoryLayout<Float>.stride),
                mData: storage[index]
            )
        }
    }

    convenience init(channels: Int, frames: Int, fill: Float = AudioTestBuffers.sentinel) {
        self.init(capacities: Array(repeating: frames, count: channels), fill: fill)
    }

    deinit {
        storage.forEach { $0.deallocate() }
        free(list.unsafeMutablePointer)
    }

    var pointer: UnsafeMutablePointer<AudioBufferList> {
        list.unsafeMutablePointer
    }

    func samples(_ channel: Int) -> [Float] {
        Array(UnsafeBufferPointer(start: storage[channel], count: capacities[channel]))
    }

    func guardFramesAreUntouched(_ channel: Int) -> Bool {
        let tail = storage[channel] + capacities[channel]
        return UnsafeBufferPointer(start: tail, count: Self.guardFrames).allSatisfy { $0 == fill }
    }
}
