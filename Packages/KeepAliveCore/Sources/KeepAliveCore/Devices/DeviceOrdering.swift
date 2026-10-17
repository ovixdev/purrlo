import Foundation

public struct DeviceMenuEntry: Sendable, Equatable {
    public let uid: String
    /// The device name, plus ` (<suffix>)` when another listed device has the same name (EC-2).
    public let title: String
    public let isBluetooth: Bool

    public init(uid: String, title: String, isBluetooth: Bool) {
        self.uid = uid
        self.title = title
        self.isBluetooth = isBluetooth
    }
}

public enum DeviceOrdering {
    /// FR-1: output devices only (outputChannels > 0), Bluetooth and Bluetooth LE first, then the rest (the UI puts a
    /// separator between). Each section is sorted by name (localizedStandardCompare), then UID, so the order is stable.
    public static func sections(_ devices: [AudioDevice]) -> (bluetooth: [DeviceMenuEntry], other: [DeviceMenuEntry]) {
        let outputs = devices.filter { $0.outputChannels > 0 }
        var uidsByName: [String: [String]] = [:]
        for device in outputs {
            uidsByName[device.name.lowercased(), default: []].append(device.uid)
        }

        func entries(_ group: [AudioDevice]) -> [DeviceMenuEntry] {
            let sorted = group.sorted { lhs, rhs in
                let order = lhs.name.localizedStandardCompare(rhs.name)
                return order == .orderedSame ? lhs.uid < rhs.uid : order == .orderedAscending
            }
            return sorted.map { device in
                let sameName = uidsByName[device.name.lowercased()] ?? []
                let title = sameName.count > 1
                    ? "\(device.name) (\(shortUID(device.uid, among: sameName)))"
                    : device.name
                return DeviceMenuEntry(uid: device.uid, title: title, isBluetooth: device.transport.isBluetooth)
            }
        }

        return (
            bluetooth: entries(outputs.filter(\.transport.isBluetooth)),
            other: entries(outputs.filter { !$0.transport.isBluetooth })
        )
    }

    /// EC-2: shortest tail (at least 4 characters) of the UID, without a trailing `:output`/`:input`, that no other
    /// UID in `others` ends with; the whole UID when no tail is unique.
    static func shortUID(_ uid: String, among others: [String]) -> String {
        let own = stripDirection(uid)
        let rivals = others.map(stripDirection).filter { $0 != own }
        var length = min(4, own.count)
        while length <= own.count {
            let tail = String(own.suffix(length))
            if !rivals.contains(where: { $0.hasSuffix(tail) }) {
                return tail
            }
            length += 1
        }
        return uid
    }

    private static func stripDirection(_ uid: String) -> String {
        for suffix in [":output", ":input"] where uid.hasSuffix(suffix) {
            return String(uid.dropLast(suffix.count))
        }
        return uid
    }
}
