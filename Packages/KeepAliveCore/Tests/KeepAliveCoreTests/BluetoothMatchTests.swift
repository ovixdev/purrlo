@testable import KeepAliveCore
import Testing

@Suite("Bluetooth match (§6)")
struct BluetoothMatchTests {
    @Test("§6: an address in the UID is .byAddress and the name list is ignored")
    func addressWins() {
        let control = BluetoothMatch.resolve(
            uid: "E8-4C-4A-8A-9A-39:output", name: "Not Paired", pairedNames: ["Not Paired", "Not Paired"]
        )
        #expect(control == .byAddress)
    }

    @Test("§6: one paired device with the exact name is .byUniqueName")
    func uniqueName() {
        let control = BluetoothMatch.resolve(uid: "e2e-speaker", name: "Kitchen", pairedNames: ["Kitchen", "Other"])
        #expect(control == .byUniqueName)
    }

    @Test("§6, EC-18: zero matches and two matches are .unavailable")
    func noneOrMany() {
        #expect(BluetoothMatch.resolve(uid: "e2e-speaker", name: "Kitchen", pairedNames: []) == .unavailable)
        #expect(
            BluetoothMatch.resolve(uid: "e2e-speaker", name: "Kitchen", pairedNames: ["Kitchen", "Kitchen"])
                == .unavailable
        )
        #expect(BluetoothMatch.matchName("Kitchen", pairedNames: ["kitchen"]) == .unavailable)
    }
}
