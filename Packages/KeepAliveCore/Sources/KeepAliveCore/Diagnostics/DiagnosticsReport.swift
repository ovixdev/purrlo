import Foundation

/// Copy Diagnostics text (NFR-9). Pure: the app supplies the log extract and the home path.
public struct DiagnosticsReport: Sendable {
    public struct Version: Sendable {
        public var marketing: String
        public var build: String
        public var system: String

        public init(marketing: String, build: String, system: String) {
            self.marketing = marketing
            self.build = build
            self.system = system
        }
    }

    public var marketingVersion: String
    public var build: String
    public var osVersion: String
    public var state: String
    public var keepAlive: Bool
    public var signal: String
    public var preventIdleSleep: Bool
    public var disconnectBeforeSleep: Bool
    public var reconnectAfterUnlock: Bool
    public var targetName: String?
    public var targetUID: String?
    public var transitions: [TransitionEntry]

    public init(
        version: Version,
        state: String,
        config: KeepAliveConfig,
        targetName: String?,
        transitions: [TransitionEntry]
    ) {
        marketingVersion = version.marketing
        build = version.build
        osVersion = version.system
        self.state = state
        keepAlive = config.keepAlive
        signal = config.signal.rawValue
        preventIdleSleep = config.preventIdleSleep
        disconnectBeforeSleep = config.disconnectBeforeSleep
        reconnectAfterUnlock = config.reconnectAfterUnlock
        self.targetName = targetName
        targetUID = config.targetUID
        self.transitions = transitions
    }

    public func text(logExtract: String, homeDirectory: String) -> String {
        var lines = [
            "Purrlo \(marketingVersion) (\(build))",
            "macOS \(osVersion)",
            "state: \(state)",
            "keepAlive: \(keepAlive)",
            "signal: \(signal)",
            "preventIdleSleep: \(preventIdleSleep)",
            "disconnectBeforeSleep: \(disconnectBeforeSleep)",
            "reconnectAfterUnlock: \(reconnectAfterUnlock)",
            "target: \(targetName ?? "none")",
            "targetUID: \(targetUID.map(logUID) ?? "none")",
            "transitions:",
        ]
        if transitions.isEmpty {
            lines.append("(none)")
        } else {
            for entry in transitions {
                let effects = entry.effects.joined(separator: ", ")
                lines.append(
                    "\(entry.seq) \(entry.from.rawValue) --\(entry.event)--> \(entry.to.rawValue) [\(effects)]"
                )
            }
        }
        lines.append("---")
        lines.append(logExtract)
        return Self.redact(lines.joined(separator: "\n"), homeDirectory: homeDirectory)
    }

    /// Replaces Bluetooth addresses with `logUID` and removes the home-directory path.
    static func redact(_ text: String, homeDirectory: String) -> String {
        let pattern = "[0-9A-Fa-f]{2}(?:[:-][0-9A-Fa-f]{2}){5}"
        guard let expression = try? NSRegularExpression(pattern: pattern) else { return text }
        let editable = NSMutableString(string: text)
        let range = NSRange(location: 0, length: editable.length)
        let matches = expression.matches(in: editable as String, range: range)
        for match in matches.reversed() {
            let found = editable.substring(with: match.range)
            editable.replaceCharacters(in: match.range, with: logUID(found))
        }
        var redacted = editable as String
        if !homeDirectory.isEmpty {
            redacted = redacted.replacingOccurrences(of: homeDirectory, with: "")
        }
        return redacted
    }
}
