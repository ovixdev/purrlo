import Foundation
@testable import KeepAliveCore
import Testing

@Suite("BluetoothAddress")
struct BluetoothAddressTests {
    @Test("FR-2/EC-18: parses the address from a real Bluetooth UID")
    func parsesRealUID() {
        #expect(BluetoothAddress(coreAudioUID: "E8-4C-4A-8A-9A-39:output")?.description == "e8-4c-4a-8a-9a-39")
    }

    @Test(
        "FR-2/EC-18: parses dash or colon separators, any hex case, and an end of string or ':' suffix",
        arguments: [
            "E8-4C-4A-8A-9A-39",
            "e8-4c-4a-8a-9a-39",
            "E8-4c-4A-8a-9A-39:input",
            "E8:4C:4A:8A:9A:39",
            "e8:4c:4a:8a:9a:39:output",
            "E8-4C-4A-8A-9A-39:output:extra",
            "E8-4C-4A-8A-9A-39:",
        ]
    )
    func parsesValid(uid: String) {
        #expect(BluetoothAddress(coreAudioUID: uid)?.description == "e8-4c-4a-8a-9a-39")
    }

    @Test("FR-2/EC-18: leading zeros and all-zero addresses are kept")
    func keepsLeadingZeros() {
        #expect(BluetoothAddress(coreAudioUID: "00-01-0A-0F-A0-FF:output")?.description == "00-01-0a-0f-a0-ff")
        #expect(BluetoothAddress(coreAudioUID: "00-00-00-00-00-00")?.description == "00-00-00-00-00-00")
    }

    @Test("FR-2/EC-18: the same address from different UIDs is equal and hashable")
    func equality() {
        let dash = BluetoothAddress(coreAudioUID: "E8-4C-4A-8A-9A-39:output")
        let colon = BluetoothAddress(coreAudioUID: "e8:4c:4a:8a:9a:39")
        #expect(dash != nil)
        #expect(dash == colon)
        #expect(Set([dash, colon]).count == 1)
        #expect(dash != BluetoothAddress(coreAudioUID: "E8-4C-4A-8A-9A-3A"))
    }

    @Test("FR-2/EC-18: round-trips through Codable")
    func codable() throws {
        let address = try #require(BluetoothAddress(coreAudioUID: "E8-4C-4A-8A-9A-39:output"))
        let data = try JSONEncoder().encode(address)
        let decoded = try JSONDecoder().decode(BluetoothAddress.self, from: data)
        #expect(decoded == address)
    }

    @Test(
        "EC-18: UIDs without a Bluetooth address give nil",
        arguments: [
            "",
            "BuiltInSpeakerDevice",
            "e2e-speaker",
            "BlackHole2ch_UID",
            "4A8B3460-0000-0000-0823-0104B5000078",
            "E8-4C-4A-8A-9A",
            "E8-4C-4A-8A-9A-39-01",
            "E8-4C-4A-8A-9A-3G",
            "E8-4C-4A-8A-9A-3",
            "E8-4C:4A-8A-9A-39",
            "E8:4C-4A-8A-9A-39",
            "E8-4C-4A-8A-9A-39X",
            "E8-4C-4A-8A-9A-39 output",
            "E8_4C_4A_8A_9A_39",
            "E84C4A8A9A39",
            ":E8-4C-4A-8A-9A-39",
            "é8-4C-4A-8A-9A-39",
        ]
    )
    func rejectsInvalid(uid: String) {
        #expect(BluetoothAddress(coreAudioUID: uid) == nil)
    }
}
