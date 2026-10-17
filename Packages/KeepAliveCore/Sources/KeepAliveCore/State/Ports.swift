import Foundation
import ServiceManagement

// Side-effect boundaries the state machine drives. M1 ships real implementations for the engine,
// power assertion, scheduler and login item; the rest get theirs in M2 (sleep) and M3 (helper).

/// `SleepHelper` over XPC (FR-10, M3): sets and clears the system sleep-disabled flag.
@MainActor
public protocol HelperControlling: AnyObject {
    func setSleepDisabled(_ disabled: Bool)
}

/// FR-11 and FR-12 (M2). `connect` is only ever reached from the single post-unlock reconnect (FR-5).
@MainActor
public protocol BluetoothControlling: AnyObject {
    /// One pass over the device list. The default stamps a parseable UID as `.byAddress` and does not
    /// call IOBluetooth, which is what the E2E build relies on.
    func controls(for devices: [AudioDevice]) -> [String: BluetoothControl]
    func disconnect(uid: String)
    /// Returns whether `openConnection` succeeded.
    func connect(uid: String) async -> Bool
}

public extension BluetoothControlling {
    func controls(for devices: [AudioDevice]) -> [String: BluetoothControl] {
        var result: [String: BluetoothControl] = [:]
        for device in devices {
            result[device.uid] = BluetoothAddress(coreAudioUID: device.uid) != nil ? .byAddress : .unavailable
        }
        return result
    }
}

/// FR-13 (M2): saves, zeroes and restores the target's output volume.
@MainActor
public protocol VolumeControlling: AnyObject {
    /// A saved volume is waiting to be restored, also across launches (EC-12).
    var hasPendingRestore: Bool { get }
    func saveAndZero(uid: String)
    func restore(uid: String)
}

/// FR-15 and engine errors (M2/M3).
@MainActor
public protocol Notifying: AnyObject {
    func post(_ notification: NotificationKind)
}

/// `IOAllowPowerChange` once the sleep sequence is done (M2).
@MainActor
public protocol SleepAcknowledging: AnyObject {
    func allowSleep()
}

@MainActor
public protocol Scheduling: AnyObject {
    /// Replaces any pending timer with the same id.
    func schedule(_ id: TimerID, after seconds: Double, _ fire: @escaping @MainActor () -> Void)
    func cancel(_ id: TimerID)
}

/// FR-7: Launch at Login.
@MainActor
public protocol LoginItemControlling: AnyObject {
    var isEnabled: Bool { get }
    func setEnabled(_ enabled: Bool) throws
}

/// Ports with no M1 implementation: they do nothing, so M1 builds never touch Bluetooth, volume or the helper.
@MainActor
public final class InactivePort: HelperControlling, BluetoothControlling, VolumeControlling, Notifying,
    SleepAcknowledging
{
    public init() {}
    public func setSleepDisabled(_: Bool) {}
    public func disconnect(uid _: String) {}
    public func connect(uid _: String) async -> Bool {
        false
    }

    public var hasPendingRestore: Bool {
        false
    }

    public func saveAndZero(uid _: String) {}
    public func restore(uid _: String) {}
    public func post(_: NotificationKind) {}
    public func allowSleep() {}
}

@MainActor
public final class TaskScheduler: Scheduling {
    private var tasks: [TimerID: Task<Void, Never>] = [:]

    public init() {}

    public func schedule(_ id: TimerID, after seconds: Double, _ fire: @escaping @MainActor () -> Void) {
        tasks[id]?.cancel()
        tasks[id] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled else { return }
            self?.tasks[id] = nil
            fire()
        }
    }

    public func cancel(_ id: TimerID) {
        tasks.removeValue(forKey: id)?.cancel()
    }
}

@MainActor
public final class MainAppLoginItem: LoginItemControlling {
    public init() {}

    public var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    public func setEnabled(_ enabled: Bool) throws {
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}
