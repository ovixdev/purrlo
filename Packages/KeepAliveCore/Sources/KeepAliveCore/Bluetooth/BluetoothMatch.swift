/// How a CoreAudio device maps to one paired Bluetooth device (PRD §6, EC-18).
public enum BluetoothControl: String, Codable, Sendable {
    case byAddress
    case byUniqueName
    case unavailable
}

public enum BluetoothMatch {
    /// Address in the UID wins and the name list is ignored.
    /// Otherwise an exact, case-sensitive name match: one paired name is `.byUniqueName`,
    /// and zero or two or more is `.unavailable`.
    public static func resolve(uid: String, name: String, pairedNames: [String]) -> BluetoothControl {
        if BluetoothAddress(coreAudioUID: uid) != nil {
            return .byAddress
        }
        return matchName(name, pairedNames: pairedNames)
    }

    /// Exact `==` against the paired names. Used after an address fails to find a device.
    public static func matchName(_ name: String, pairedNames: [String]) -> BluetoothControl {
        pairedNames.filter { $0 == name }.count == 1 ? .byUniqueName : .unavailable
    }
}
