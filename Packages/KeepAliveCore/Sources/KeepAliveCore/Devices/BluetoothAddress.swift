/// The 6-byte address at the start of a Bluetooth device's CoreAudio UID (`E8-4C-4A-8A-9A-39:output`).
public struct BluetoothAddress: Sendable, Hashable, Codable, CustomStringConvertible {
    /// The six bytes, big-endian, in the low 48 bits.
    private let value: UInt64

    public init?(coreAudioUID: String) {
        let bytes = Array(coreAudioUID.utf8)
        // Six hex pairs and five separators, then the end of the string or `:` and anything.
        guard bytes.count >= 17, bytes.count == 17 || bytes[17] == UInt8(ascii: ":") else { return nil }
        let separator = bytes[2]
        guard separator == UInt8(ascii: "-") || separator == UInt8(ascii: ":") else { return nil }

        var value: UInt64 = 0
        for group in 0 ..< 6 {
            let start = group * 3
            if group > 0, bytes[start - 1] != separator {
                return nil
            }
            guard let high = Self.hexValue(bytes[start]), let low = Self.hexValue(bytes[start + 1]) else { return nil }
            value = value << 8 | UInt64(high << 4 | low)
        }
        self.value = value
    }

    /// Canonical lowercase form, accepted by `IOBluetoothDevice(addressString:)`.
    public var description: String {
        let digits = Array("0123456789abcdef")
        var text = ""
        for index in 0 ..< 6 {
            let byte = Int(value >> UInt64(8 * (5 - index)) & 0xFF)
            if index > 0 {
                text.append("-")
            }
            text.append(digits[byte >> 4])
            text.append(digits[byte & 0xF])
        }
        return text
    }

    private static func hexValue(_ byte: UInt8) -> UInt8? {
        switch byte {
        case UInt8(ascii: "0") ... UInt8(ascii: "9"): byte - UInt8(ascii: "0")
        case UInt8(ascii: "a") ... UInt8(ascii: "f"): byte - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A") ... UInt8(ascii: "F"): byte - UInt8(ascii: "A") + 10
        default: nil
        }
    }
}
