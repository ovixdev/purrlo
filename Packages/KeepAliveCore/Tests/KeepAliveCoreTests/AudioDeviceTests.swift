import CoreAudio
import Foundation
@testable import KeepAliveCore
import Testing

func makeDevice(
    uid: String,
    name: String,
    transport: Transport = .other,
    outputChannels: Int = 2,
    objectID: UInt32 = 1
) -> AudioDevice {
    AudioDevice(
        uid: uid,
        objectID: objectID,
        name: name,
        transport: transport,
        outputChannels: outputChannels,
        nominalSampleRate: 48000,
        isAlive: true
    )
}

private let transportCases: [(UInt32, Transport)] = [
    (kAudioDeviceTransportTypeBluetooth, .bluetooth),
    (kAudioDeviceTransportTypeBluetoothLE, .bluetoothLE),
    (kAudioDeviceTransportTypeBuiltIn, .builtIn),
    (kAudioDeviceTransportTypeUSB, .usb),
    (kAudioDeviceTransportTypeHDMI, .hdmi),
    (kAudioDeviceTransportTypeDisplayPort, .displayPort),
    (kAudioDeviceTransportTypeThunderbolt, .thunderbolt),
    (kAudioDeviceTransportTypeAirPlay, .airPlay),
    (kAudioDeviceTransportTypeAggregate, .aggregate),
    (kAudioDeviceTransportTypeVirtual, .virtual),
    (kAudioDeviceTransportTypeUnknown, .other),
    (kAudioDeviceTransportTypePCI, .other),
    (0xDEAD_BEEF, .other),
]

@Suite("AudioDevice")
struct AudioDeviceTests {
    @Test("FR-1: CoreAudio transport types map to Transport", arguments: transportCases)
    func transportMapping(raw: UInt32, expected: Transport) {
        #expect(Transport(coreAudioTransportType: raw) == expected)
    }

    @Test("FR-1: only Bluetooth and Bluetooth LE count as Bluetooth", arguments: Transport.allCases)
    func isBluetooth(transport: Transport) {
        #expect(transport.isBluetooth == (transport == .bluetooth || transport == .bluetoothLE))
    }

    @Test("FR-2: identity is the UID, not the name or AudioObjectID")
    func identityIsUID() {
        let device = makeDevice(uid: "E8-4C-4A-8A-9A-39:output", name: "Echo Dot", objectID: 77)
        #expect(device.id == "E8-4C-4A-8A-9A-39:output")
        var renamed = device
        renamed.name = "Kitchen"
        renamed.objectID = 91
        #expect(renamed.id == device.id)
        #expect(renamed != device)
    }

    @Test("FR-2/EC-18: bluetoothAddress comes from the UID")
    func bluetoothAddress() {
        #expect(makeDevice(uid: "E8-4C-4A-8A-9A-39:output", name: "Echo").bluetoothAddress?.description
            == "e8-4c-4a-8a-9a-39")
        #expect(makeDevice(uid: "BuiltInSpeakerDevice", name: "Speakers").bluetoothAddress == nil)
    }

    @Test("FR-2: round-trips through Codable")
    func codable() throws {
        let device = makeDevice(uid: "E8-4C-4A-8A-9A-39:output", name: "Echo Dot", transport: .bluetooth)
        let data = try JSONEncoder().encode(device)
        let decoded = try JSONDecoder().decode(AudioDevice.self, from: data)
        #expect(decoded == device)
    }
}
