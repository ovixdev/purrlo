import CoreAudio
import KeepAliveCore

/// Test-only CoreAudio control used by L2 tests and `kactl` (PRD §8). Never linked into the app.
public struct CoreAudioError: Error, Equatable, CustomStringConvertible {
    public let operation: String
    public let status: OSStatus

    public var description: String {
        "\(operation) failed (OSStatus \(status))"
    }
}

public enum VirtualDevice {
    public static let blackHole2chUID = "BlackHole2ch_UID"
    public static let blackHole16chUID = "BlackHole16ch_UID"

    /// Creates a public aggregate on top of `subDeviceUID`, simulating the speaker appearing (`kactl vdev create`).
    /// Public aggregates outlive the creating process, so `destroy` finds it again by UID.
    @discardableResult
    public static func create(name: String, uid: String, on subDeviceUID: String) throws -> AudioObjectID {
        let description: [String: Any] = [
            kAudioAggregateDeviceNameKey: name,
            kAudioAggregateDeviceUIDKey: uid,
            kAudioAggregateDeviceIsPrivateKey: 0,
            kAudioAggregateDeviceMainSubDeviceKey: subDeviceUID,
            kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: subDeviceUID]],
        ]
        var id = AudioObjectID(kAudioObjectUnknown)
        let status = AudioHardwareCreateAggregateDevice(description as CFDictionary, &id)
        guard status == noErr else { throw CoreAudioError(operation: "create aggregate \(uid)", status: status) }
        return id
    }

    /// Removes the aggregate with `uid`, simulating the speaker disappearing. No-op when it does not exist.
    public static func destroy(uid: String) throws {
        guard let id = CoreAudioProperty.deviceID(forUID: uid) else { return }
        let status = AudioHardwareDestroyAggregateDevice(id)
        guard status == noErr else { throw CoreAudioError(operation: "destroy aggregate \(uid)", status: status) }
    }

    public static func deviceID(uid: String) -> AudioObjectID? {
        CoreAudioProperty.deviceID(forUID: uid)
    }

    public static func nominalSampleRate(uid: String) -> Double? {
        deviceID(uid: uid)
            .flatMap { CoreAudioProperty.value($0, kAudioDevicePropertyNominalSampleRate, as: Float64.self) }
    }

    public static func setNominalSampleRate(_ rate: Double, uid: String) throws {
        guard let id = deviceID(uid: uid) else { throw CoreAudioError(
            operation: "find \(uid)",
            status: kAudioHardwareBadDeviceError
        ) }
        let status = CoreAudioProperty.setValue(id, kAudioDevicePropertyNominalSampleRate, Float64(rate))
        guard status == noErr else { throw CoreAudioError(operation: "set rate \(rate) on \(uid)", status: status) }
    }

    /// `kAudioDevicePropertyDeviceIsRunningSomewhere`: some process is doing IO on the device.
    public static func isRunningSomewhere(uid: String) -> Bool {
        deviceID(uid: uid).flatMap {
            CoreAudioProperty.value($0, kAudioDevicePropertyDeviceIsRunningSomewhere, as: UInt32.self)
        } == 1
    }

    public static func defaultOutputUID() -> String? {
        CoreAudioProperty.value(
            CoreAudioProperty.system,
            kAudioHardwarePropertyDefaultOutputDevice,
            as: AudioObjectID.self
        )
        .flatMap { CoreAudioProperty.string($0, kAudioDevicePropertyDeviceUID) }
    }

    public static func setDefaultOutput(uid: String) throws {
        guard let id = deviceID(uid: uid) else { throw CoreAudioError(
            operation: "find \(uid)",
            status: kAudioHardwareBadDeviceError
        ) }
        let status = CoreAudioProperty.setValue(CoreAudioProperty.system, kAudioHardwarePropertyDefaultOutputDevice, id)
        guard status == noErr else { throw CoreAudioError(operation: "set default output \(uid)", status: status) }
    }
}
