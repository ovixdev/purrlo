import Foundation

/// Persisted preferences. The target is identified by CoreAudio UID only (FR-2).
@MainActor
public final class Settings {
    private enum Key {
        static let targetUID = "targetUID"
        static let targetDisplayName = "targetDisplayName"
        static let keepAlive = "keepAlive"
        static let signal = "signal"
        static let preventIdleSleep = "preventIdleSleep"
        static let disconnectBeforeSleep = "disconnectBeforeSleep"
        static let reconnectAfterUnlock = "reconnectAfterUnlock"
        static let didCompleteFirstRun = "didCompleteFirstRun"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults) {
        self.defaults = defaults
    }

    public var targetUID: String? {
        defaults.string(forKey: Key.targetUID)
    }

    /// Last-seen name, for display only; never used for matching (FR-2).
    public var targetDisplayName: String? {
        defaults.string(forKey: Key.targetDisplayName)
    }

    public func setTarget(uid: String, name: String) {
        defaults.set(uid, forKey: Key.targetUID)
        defaults.set(name, forKey: Key.targetDisplayName)
    }

    public func clearTarget() {
        defaults.removeObject(forKey: Key.targetUID)
        defaults.removeObject(forKey: Key.targetDisplayName)
    }

    /// EC-3: the target was renamed; updates the display name only if a target is set.
    public func noteTargetName(_ name: String) {
        guard targetUID != nil else { return }
        defaults.set(name, forKey: Key.targetDisplayName)
    }

    /// FR-6: master toggle, on by default.
    public var keepAlive: Bool {
        get { bool(Key.keepAlive, default: true) }
        set { defaults.set(newValue, forKey: Key.keepAlive) }
    }

    /// FR-4: tone by default; an unknown stored value also reads as tone.
    public var signal: SignalKind {
        get { defaults.string(forKey: Key.signal).flatMap(SignalKind.init(rawValue:)) ?? .tone }
        set { defaults.set(newValue.rawValue, forKey: Key.signal) }
    }

    /// FR-9: on by default.
    public var preventIdleSleep: Bool {
        get { bool(Key.preventIdleSleep, default: true) }
        set { defaults.set(newValue, forKey: Key.preventIdleSleep) }
    }

    /// FR-11: on by default.
    public var disconnectBeforeSleep: Bool {
        get { bool(Key.disconnectBeforeSleep, default: true) }
        set { defaults.set(newValue, forKey: Key.disconnectBeforeSleep) }
    }

    /// FR-12: on by default.
    public var reconnectAfterUnlock: Bool {
        get { bool(Key.reconnectAfterUnlock, default: true) }
        set { defaults.set(newValue, forKey: Key.reconnectAfterUnlock) }
    }

    /// FR-18: false until the first-run window's Start button.
    public var didCompleteFirstRun: Bool {
        get { bool(Key.didCompleteFirstRun, default: false) }
        set { defaults.set(newValue, forKey: Key.didCompleteFirstRun) }
    }

    private func bool(_ key: String, default fallback: Bool) -> Bool {
        defaults.object(forKey: key) as? Bool ?? fallback
    }
}
