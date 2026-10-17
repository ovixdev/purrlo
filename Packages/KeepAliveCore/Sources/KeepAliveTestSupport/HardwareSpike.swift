import AudioToolbox
import CoreAudio
import Foundation
import IOBluetooth
import KeepAliveCore

/// E2E-H4 (FR-13 spike): raw volume and Bluetooth control for `kactl spike`, run on purpose by a tester.
/// Lives in test support so the app never contains a connect call (FR-5).
public enum HardwareSpike {
    public struct Output: Codable, Sendable {
        public let uid: String
        public let name: String
        public let transport: String
        public let bluetooth: Bool
    }

    /// Output devices, Bluetooth first (FR-1 order).
    public static func outputs() -> [Output] {
        let devices = CoreAudioHardware.outputDevices()
        return (devices.filter(\.transport.isBluetooth) + devices.filter { !$0.transport.isBluetooth }).map {
            Output(uid: $0.uid, name: $0.name, transport: $0.transport.rawValue, bluetooth: $0.transport.isBluetooth)
        }
    }

    public static func isPresent(uid: String) -> Bool {
        CoreAudioProperty.deviceID(forUID: uid) != nil
    }

    /// Mac-side output volume 0...1 (`kAudioHardwareServiceDeviceProperty_VirtualMainVolume`), the FR-13 knob.
    public static func volume(uid: String) throws -> Float {
        let id = try deviceID(uid)
        guard let value = CoreAudioProperty.value(
            id, kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioObjectPropertyScopeOutput,
            as: Float32.self
        ) else { throw CoreAudioError(operation: "read volume of \(uid)", status: kAudioHardwareUnknownPropertyError) }
        return value
    }

    public static func setVolume(_ volume: Float, uid: String) throws {
        let status = try CoreAudioProperty.setValue(
            deviceID(uid), kAudioHardwareServiceDeviceProperty_VirtualMainVolume, Float32(min(max(volume, 0), 1)),
            scope: kAudioObjectPropertyScopeOutput
        )
        guard status == noErr else { throw CoreAudioError(operation: "set volume of \(uid)", status: status) }
    }

    /// `IOBluetoothDevice.closeConnection` on the device behind a Bluetooth CoreAudio UID.
    public static func disconnect(uid: String) throws {
        let status = try bluetoothDevice(uid).closeConnection()
        guard status == kIOReturnSuccess else { throw CoreAudioError(operation: "closeConnection", status: status) }
    }

    /// `IOBluetoothDevice.openConnection`; blocks until the link is up or fails.
    public static func connect(uid: String) throws {
        let status = try bluetoothDevice(uid).openConnection()
        guard status == kIOReturnSuccess else { throw CoreAudioError(operation: "openConnection", status: status) }
    }

    private static func deviceID(_ uid: String) throws -> AudioObjectID {
        guard let id = CoreAudioProperty.deviceID(forUID: uid) else {
            throw CoreAudioError(operation: "find \(uid)", status: kAudioHardwareBadDeviceError)
        }
        return id
    }

    private static func bluetoothDevice(_ uid: String) throws -> IOBluetoothDevice {
        guard let address = BluetoothAddress(coreAudioUID: uid) else {
            throw CoreAudioError(
                operation: "\(uid) has no Bluetooth address (EC-18)",
                status: kAudioHardwareIllegalOperationError
            )
        }
        guard let device = IOBluetoothDevice(addressString: address.description) else {
            throw CoreAudioError(
                operation: "no paired Bluetooth device \(address)",
                status: kAudioHardwareBadDeviceError
            )
        }
        return device
    }
}
