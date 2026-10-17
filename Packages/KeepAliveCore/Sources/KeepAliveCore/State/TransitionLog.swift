import Foundation

/// One processed event, including self-transitions, so E2E can see engine restarts (PRD §5, A13).
public struct TransitionEntry: Sendable, Equatable, Codable {
    public let seq: Int
    /// Seconds since the log was created (app launch).
    public let time: Double
    public let from: KeepAliveState
    public let event: String
    public let to: KeepAliveState
    public let effects: [String]
}

@MainActor
public final class TransitionLog {
    public private(set) var entries: [TransitionEntry] = []
    private let started = ContinuousClock.now
    private let limit: Int

    /// Keeps the newest `limit` entries so a week-long run stays bounded (NFR-2, NFR-4).
    public init(limit: Int = 5000) {
        self.limit = limit
    }

    @discardableResult
    public func record(
        from: KeepAliveState,
        event: String,
        to: KeepAliveState,
        effects: [KeepAliveEffect]
    ) -> TransitionEntry {
        let elapsed = ContinuousClock.now - started
        let seconds = Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18
        let entry = TransitionEntry(
            seq: (entries.last?.seq ?? 0) + 1,
            time: seconds,
            from: from,
            event: event,
            to: to,
            effects: effects.map(\.logDescription)
        )
        entries.append(entry)
        if entries.count > limit {
            entries.removeFirst(entries.count - limit)
        }
        return entry
    }
}

public extension KeepAliveEvent {
    /// Stable, privacy-light names for logs (NFR-9): device UIDs and rates, never full device lists.
    var logDescription: String {
        switch self {
        case let .configChanged(config):
            "configChanged(keepAlive=\(config.keepAlive), target=\(config.targetUID.map(logUID) ?? "none"), "
                + "signal=\(config.signal.rawValue), preventIdleSleep=\(config.preventIdleSleep))"
        case let .devicesChanged(devices): "devicesChanged(\(devices.count))"
        case .engineStarted: "engineStarted"
        case let .engineFailed(message): "engineFailed(\(message))"
        case let .timerFired(id): "timerFired(\(id.rawValue))"
        case let .cutOffChanged(active, reason): "cutOffChanged(\(active), \(reason))"
        case .systemWillSleep: "systemWillSleep"
        case .systemDidWake: "systemDidWake"
        case .screenUnlocked: "screenUnlocked"
        case .reconnectFailed: "reconnectFailed"
        }
    }
}

public extension KeepAliveEffect {
    private static func describe(_ device: AudioDevice, _ signal: SignalKind) -> String {
        "\(logUID(device.uid))@\(Int(device.nominalSampleRate)), \(signal)"
    }

    var logDescription: String {
        switch self {
        case let .startEngine(device, signal): "startEngine(\(Self.describe(device, signal)))"
        case let .restartEngine(device, signal): "restartEngine(\(Self.describe(device, signal)))"
        case .stopEngine: "stopEngine"
        case .holdAssertion: "holdAssertion"
        case .releaseAssertion: "releaseAssertion"
        case let .setLidBlock(blocked): "setLidBlock(\(blocked))"
        case let .saveAndZeroVolume(uid): "saveAndZeroVolume(\(logUID(uid)))"
        case let .restoreVolume(uid): "restoreVolume(\(logUID(uid)))"
        case let .disconnectBluetooth(uid): "disconnectBluetooth(\(logUID(uid)))"
        case let .connectBluetooth(uid): "connectBluetooth(\(logUID(uid)))"
        case let .scheduleTimer(id, seconds): "scheduleTimer(\(id.rawValue), \(seconds))"
        case let .cancelTimer(id): "cancelTimer(\(id.rawValue))"
        case let .notify(kind): "notify(\(kind))"
        case .allowSleep: "allowSleep"
        }
    }
}

/// Bluetooth UIDs embed the speaker's hardware address; logs keep only its last two bytes (NFR-9).
func logUID(_ uid: String) -> String {
    guard BluetoothAddress(coreAudioUID: uid) != nil else { return uid }
    return "bt…" + uid.prefix { $0 != ":" }.suffix(5)
}
