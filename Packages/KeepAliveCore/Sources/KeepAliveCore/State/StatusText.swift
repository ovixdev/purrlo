/// FR-8: the status line and icon for each state, including whether sleep is blocked and why.
public struct StatusLine: Sendable, Equatable, Codable {
    public let state: KeepAliveState
    public let text: String
    /// SF Symbol name; the text always carries the same information (NFR-7).
    public let symbol: String
    public let sleepBlocked: Bool
}

public enum StatusText {
    public static func make(_ machine: KeepAliveMachine, targetName: String?) -> StatusLine {
        let name = machine.target?.name ?? targetName ?? "your speaker"
        let blocked = machine.assertionHeld
        let sleep = blocked ? "Sleep blocked while \(name) is connected" : "Sleep allowed: \(allowedReason(machine))"
        let (text, symbol) = switch machine.state {
        case .off: ("Off", "hifispeaker.slash")
        case .waiting where machine.config.targetUID == nil: ("Choose a speaker", "hifispeaker")
        case .waiting: ("Waiting for \(name)", "hifispeaker")
        case .streaming: ("Streaming to \(name)", "hifispeaker.fill")
        case .suspended: ("Paused for sleep", "moon.zzz")
        case .error: ("Can't stream to \(name)", "exclamationmark.triangle")
        }
        return StatusLine(state: machine.state, text: "\(text) · \(sleep)", symbol: symbol, sleepBlocked: blocked)
    }

    private static func allowedReason(_ machine: KeepAliveMachine) -> String {
        if !machine.config.keepAlive {
            return "Keep alive is off"
        }
        if machine.state == .suspended {
            return "the Mac is going to sleep"
        }
        if !machine.config.preventIdleSleep {
            return "Prevent idle sleep is off"
        }
        return "no speaker connected"
    }
}
