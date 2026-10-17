@testable import KeepAliveCore
import Testing

private let dotA = "E8-4C-4A-8A-9A-39:output"
private let dotB = "E8-4C-4A-8A-11-22:output"

@Suite("DeviceOrdering")
struct DeviceOrderingTests {
    @Test("FR-1: Bluetooth and Bluetooth LE devices are listed before all others")
    func bluetoothFirst() {
        let sections = DeviceOrdering.sections([
            makeDevice(uid: "builtin", name: "Speakers", transport: .builtIn),
            makeDevice(uid: "le", name: "Zed LE", transport: .bluetoothLE),
            makeDevice(uid: "usb", name: "Dock", transport: .usb),
            makeDevice(uid: "bt", name: "Echo Dot", transport: .bluetooth),
        ])
        #expect(sections.bluetooth.map(\.uid) == ["bt", "le"])
        let allBluetooth = sections.bluetooth.allSatisfy(\.isBluetooth)
        #expect(allBluetooth)
        #expect(sections.other.map(\.uid) == ["usb", "builtin"])
        #expect(sections.other.allSatisfy { !$0.isBluetooth })
    }

    @Test("FR-1: input-only devices are excluded")
    func outputsOnly() {
        let sections = DeviceOrdering.sections([
            makeDevice(uid: "mic", name: "Microphone", transport: .builtIn, outputChannels: 0),
            makeDevice(uid: "headset-in", name: "Headset", transport: .bluetooth, outputChannels: 0),
            makeDevice(uid: "out", name: "Speakers", transport: .builtIn),
        ])
        #expect(sections.bluetooth.isEmpty)
        #expect(sections.other.map(\.uid) == ["out"])
    }

    @Test("FR-1: an empty device list gives empty sections")
    func empty() {
        let sections = DeviceOrdering.sections([])
        #expect(sections.bluetooth.isEmpty && sections.other.isEmpty)
    }

    @Test("FR-1: order is by name (numbers naturally), then UID, whatever the input order")
    func stableOrder() {
        let devices = [
            makeDevice(uid: "d", name: "Echo Dot 10", transport: .bluetooth),
            makeDevice(uid: "c", name: "Echo Dot 2", transport: .bluetooth),
            makeDevice(uid: "b", name: "Beats", transport: .bluetooth),
            makeDevice(uid: "a", name: "beats", transport: .bluetooth),
            makeDevice(uid: "e", name: "echo dot 9", transport: .bluetooth),
        ]
        let expected = DeviceOrdering.sections(devices).bluetooth.map(\.uid)
        // "a"/"b": names differ only by case, so the UID decides.
        #expect(expected.count == 5)
        #expect(expected.firstIndex(of: "a") ?? 0 < expected.firstIndex(of: "c") ?? 0)
        #expect(expected.firstIndex(of: "b") ?? 0 < expected.firstIndex(of: "c") ?? 0)
        #expect(expected.suffix(3) == ["c", "e", "d"])
        for shuffled in [devices.reversed(), devices.shuffled(), devices.shuffled()] {
            #expect(DeviceOrdering.sections(Array(shuffled)).bluetooth.map(\.uid) == expected)
        }
    }

    @Test("FR-1: identical names are ordered by UID")
    func sameNameByUID() {
        let sections = DeviceOrdering.sections([
            makeDevice(uid: "b-uid", name: "Same", transport: .usb),
            makeDevice(uid: "a-uid", name: "Same", transport: .usb),
        ])
        #expect(sections.other.map(\.uid) == ["a-uid", "b-uid"])
    }

    @Test("EC-2: devices with the same name get unique short UID suffixes, and others get none")
    func duplicateNamesGetSuffixes() {
        let sections = DeviceOrdering.sections([
            makeDevice(uid: dotA, name: "Echo Dot", transport: .bluetooth),
            makeDevice(uid: dotB, name: "Echo Dot", transport: .bluetooth),
            makeDevice(uid: "BuiltInSpeakerDevice", name: "Speakers", transport: .builtIn),
        ])
        #expect(sections.bluetooth.map(\.title) == ["Echo Dot (1-22)", "Echo Dot (A-39)"])
        #expect(sections.other.map(\.title) == ["Speakers"])
    }

    @Test("EC-2: three devices with the same name each get a distinct suffix")
    func threeDuplicates() {
        let sections = DeviceOrdering.sections([
            makeDevice(uid: "AAAA-1234:output", name: "Echo Dot", transport: .bluetooth),
            makeDevice(uid: "BBBB-1234:output", name: "Echo Dot", transport: .bluetooth),
            makeDevice(uid: "CCCC-9999:output", name: "Echo Dot", transport: .bluetooth),
        ])
        #expect(sections.bluetooth.map(\.title) == ["Echo Dot (A-1234)", "Echo Dot (B-1234)", "Echo Dot (9999)"])
        #expect(Set(sections.bluetooth.map(\.title)).count == 3)
    }

    @Test("EC-2: duplicates are detected across sections and ignoring case")
    func duplicatesAcrossSections() {
        let sections = DeviceOrdering.sections([
            makeDevice(uid: "bt-0001:output", name: "Studio", transport: .bluetooth),
            makeDevice(uid: "usb-0002", name: "STUDIO", transport: .usb),
            makeDevice(uid: "mic-0003", name: "Studio", transport: .usb, outputChannels: 0),
        ])
        #expect(sections.bluetooth.map(\.title) == ["Studio (0001)"])
        #expect(sections.other.map(\.title) == ["STUDIO (0002)"])
    }

    @Test("EC-2: a same-named input-only device does not force a suffix")
    func inputOnlyDuplicateIgnored() {
        let sections = DeviceOrdering.sections([
            makeDevice(uid: "out-0001", name: "Headset", transport: .bluetooth),
            makeDevice(uid: "in-0002", name: "Headset", transport: .bluetooth, outputChannels: 0),
        ])
        #expect(sections.bluetooth.map(\.title) == ["Headset"])
    }

    @Test("EC-2: shortUID grows the tail until it is unique")
    func shortUIDGrows() {
        #expect(DeviceOrdering.shortUID(dotA, among: [dotA, dotB]) == "A-39")
        #expect(DeviceOrdering.shortUID(dotB, among: [dotA, dotB]) == "1-22")
        #expect(DeviceOrdering.shortUID("AAAA-1234", among: ["AAAA-1234", "BBBB-1234"]) == "A-1234")
    }

    @Test("EC-2: shortUID strips :output and :input and never goes below four characters")
    func shortUIDStripsDirection() {
        #expect(DeviceOrdering.shortUID("abcdefgh:input", among: ["abcdefgh:input", "zzzzzzzz:output"]) == "efgh")
        #expect(DeviceOrdering.shortUID("abcdefgh", among: []) == "efgh")
    }

    @Test("EC-2: shortUID falls back to the whole UID when no tail is unique")
    func shortUIDFallback() {
        #expect(DeviceOrdering.shortUID("1234:output", among: ["1234:output", "AB1234:output"]) == "1234:output")
        #expect(DeviceOrdering.shortUID("ab", among: ["ab", "xab"]) == "ab")
        #expect(DeviceOrdering.shortUID("", among: ["", "x"]) == "")
    }

    @Test("EC-3: a renamed device keeps its UID and shows the new name")
    func renamedDevice() {
        var device = makeDevice(uid: dotA, name: "Echo Dot", transport: .bluetooth)
        let before = DeviceOrdering.sections([device]).bluetooth
        device.name = "Kitchen Speaker"
        let after = DeviceOrdering.sections([device]).bluetooth
        #expect(before.map(\.uid) == [dotA])
        #expect(after.map(\.uid) == [dotA])
        #expect(before.map(\.title) == ["Echo Dot"])
        #expect(after.map(\.title) == ["Kitchen Speaker"])
    }
}
