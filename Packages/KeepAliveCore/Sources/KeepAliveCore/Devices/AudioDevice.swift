import CoreAudio

public enum Transport: String, Sendable, Codable, CaseIterable {
    case bluetooth, bluetoothLE, builtIn, usb, hdmi, displayPort, thunderbolt, airPlay, aggregate, virtual, other

    private static let byCoreAudioType: [UInt32: Transport] = [
        kAudioDeviceTransportTypeBluetooth: .bluetooth,
        kAudioDeviceTransportTypeBluetoothLE: .bluetoothLE,
        kAudioDeviceTransportTypeBuiltIn: .builtIn,
        kAudioDeviceTransportTypeUSB: .usb,
        kAudioDeviceTransportTypeHDMI: .hdmi,
        kAudioDeviceTransportTypeDisplayPort: .displayPort,
        kAudioDeviceTransportTypeThunderbolt: .thunderbolt,
        kAudioDeviceTransportTypeAirPlay: .airPlay,
        kAudioDeviceTransportTypeAggregate: .aggregate,
        kAudioDeviceTransportTypeVirtual: .virtual,
    ]

    /// Maps a `kAudioDevicePropertyTransportType` value; anything unknown is `.other`.
    public init(coreAudioTransportType: UInt32) {
        self = Self.byCoreAudioType[coreAudioTransportType] ?? .other
    }

    public var isBluetooth: Bool {
        self == .bluetooth || self == .bluetoothLE
    }
}

public struct AudioDevice: Sendable, Equatable, Codable, Identifiable {
    public var id: String {
        uid
    }

    /// CoreAudio `kAudioDevicePropertyDeviceUID`; the only identity we persist (FR-2).
    public let uid: String
    /// `AudioObjectID`; changes across reconnects, never persisted.
    public var objectID: UInt32
    public var name: String
    public var transport: Transport
    public var outputChannels: Int
    public var nominalSampleRate: Double
    public var isAlive: Bool
    /// Set by the Bluetooth port before the state machine sees the device. `.unavailable` until then.
    public var bluetoothControl: BluetoothControl

    public init(
        uid: String,
        objectID: UInt32,
        name: String,
        transport: Transport,
        outputChannels: Int,
        nominalSampleRate: Double,
        isAlive: Bool,
        bluetoothControl: BluetoothControl = .unavailable
    ) {
        self.uid = uid
        self.objectID = objectID
        self.name = name
        self.transport = transport
        self.outputChannels = outputChannels
        self.nominalSampleRate = nominalSampleRate
        self.isAlive = isAlive
        self.bluetoothControl = bluetoothControl
    }

    public var bluetoothAddress: BluetoothAddress? {
        BluetoothAddress(coreAudioUID: uid)
    }
}
