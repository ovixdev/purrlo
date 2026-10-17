import AudioToolbox
import CoreAudio

/// Streams the keep-alive signal to one device only, independent of the default output (FR-3, EC-5).
@MainActor
public protocol KeepAliveEngine: AnyObject {
    var isRunning: Bool { get }
    /// Starts a stream bound to `device` at its nominal rate and channel count.
    /// A signal change on that same device leaves the unit running.
    func start(device: AudioDevice, signal: SignalKind) throws(EngineError)
    /// Idempotent.
    func stop()
}

public struct EngineError: Error, Equatable, CustomStringConvertible {
    public let operation: String
    public let status: OSStatus

    public init(operation: String, status: OSStatus) {
        self.operation = operation
        self.status = status
    }

    public var description: String {
        "\(operation) failed (OSStatus \(status))"
    }
}

/// One AUHAL output unit bound to the target by AudioObjectID (PRD §6, Audio).
@MainActor
public final class AUHALEngine: KeepAliveEngine {
    private var unit: AudioUnit?
    /// Render state read only by the render thread while the unit runs; freed after the unit is disposed.
    private var generator: UnsafeMutablePointer<SignalGenerator>?
    private var boundObjectID: UInt32?
    private var boundSampleRate: Double = 0
    private var boundChannels: Int = 0

    public init() {}

    public var isRunning: Bool {
        unit != nil
    }

    public func start(device: AudioDevice, signal: SignalKind) throws(EngineError) {
        // Stopping the unit to change tone/silence lets the loopback clock run ahead of the output.
        // BlackHole then fills the input with exact zeros (a 32 ms run, 2.2 s into E2E-2's second tone).
        if unit != nil, boundObjectID == device.objectID, boundSampleRate == device.nominalSampleRate,
           boundChannels == device.outputChannels, let generator {
            SignalGenerator.storeKind(signal, in: generator)
            return
        }
        stop()
        let generator = UnsafeMutablePointer<SignalGenerator>.allocate(capacity: 1)
        generator.initialize(to: SignalGenerator(kind: signal, sampleRate: device.nominalSampleRate))
        do {
            unit = try Self.makeUnit(device: device, generator: generator)
            self.generator = generator
            boundObjectID = device.objectID
            boundSampleRate = device.nominalSampleRate
            boundChannels = device.outputChannels
        } catch {
            generator.deinitialize(count: 1)
            generator.deallocate()
            throw error
        }
    }

    public func stop() {
        if let unit {
            AudioOutputUnitStop(unit)
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            self.unit = nil
        }
        if let generator {
            generator.deinitialize(count: 1)
            generator.deallocate()
            self.generator = nil
        }
        boundObjectID = nil
    }

    private static func makeUnit(
        device: AudioDevice,
        generator: UnsafeMutablePointer<SignalGenerator>
    ) throws(EngineError) -> AudioUnit {
        var description = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_HALOutput,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )
        guard let component = AudioComponentFindNext(nil, &description) else {
            throw EngineError(operation: "AudioComponentFindNext", status: kAudioUnitErr_InvalidElement)
        }
        var instance: AudioUnit?
        try check("AudioComponentInstanceNew", AudioComponentInstanceNew(component, &instance))
        guard let unit = instance else {
            throw EngineError(operation: "AudioComponentInstanceNew", status: kAudioUnitErr_FailedInitialization)
        }

        do {
            try configure(unit, device: device, generator: generator)
            try check("AudioUnitInitialize", AudioUnitInitialize(unit))
            try check("AudioOutputUnitStart", AudioOutputUnitStart(unit))
        } catch {
            AudioUnitUninitialize(unit)
            AudioComponentInstanceDispose(unit)
            throw error
        }
        return unit
    }

    private static func configure(
        _ unit: AudioUnit,
        device: AudioDevice,
        generator: UnsafeMutablePointer<SignalGenerator>
    ) throws(EngineError) {
        try set(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, element: 0, UInt32(1))
        try set(unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, element: 1, UInt32(0))
        try set(unit, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, element: 0, device.objectID)

        let channels = UInt32(max(device.outputChannels, 1))
        let bytesPerSample = UInt32(MemoryLayout<Float32>.size)
        let format = AudioStreamBasicDescription(
            mSampleRate: device.nominalSampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: bytesPerSample,
            mFramesPerPacket: 1,
            mBytesPerFrame: bytesPerSample,
            mChannelsPerFrame: channels,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        try set(unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, element: 0, format)

        let callback = AURenderCallbackStruct(
            inputProc: renderSignal,
            inputProcRefCon: UnsafeMutableRawPointer(generator)
        )
        try set(unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, element: 0, callback)
    }

    private static func set<T: BitwiseCopyable>(
        _ unit: AudioUnit,
        _ property: AudioUnitPropertyID,
        _ scope: AudioUnitScope,
        element: AudioUnitElement,
        _ value: T
    ) throws(EngineError) {
        var value = value
        let status = AudioUnitSetProperty(unit, property, scope, element, &value, UInt32(MemoryLayout<T>.size))
        try check("AudioUnitSetProperty(\(property))", status)
    }

    private static func check(_ operation: @autoclosure () -> String, _ status: OSStatus) throws(EngineError) {
        guard status == noErr else { throw EngineError(operation: operation(), status: status) }
    }
}

/// Render thread (NFR-3): touches only the preallocated generator; no allocation, locks, ARC or Objective-C.
private let renderSignal: AURenderCallback = { refCon, _, _, _, frameCount, bufferList in
    guard let bufferList else { return noErr }
    refCon.assumingMemoryBound(to: SignalGenerator.self).pointee.render(frameCount: frameCount, into: bufferList)
    return noErr
}
