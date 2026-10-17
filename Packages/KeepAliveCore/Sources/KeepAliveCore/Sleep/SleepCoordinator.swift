import AppKit
import Darwin
import Foundation
import IOKit.pwr_mgt
import os

/// Notes the power callback asks the main actor to apply. Dark-wake messages are not notes.
enum SleepNote: Sendable {
    case willSleep
    case willNotSleep
}

/// Allows a power-change token at most once. The watchdog runs on a private queue, so a blocked main
/// thread still answers `kIOMessageSystemWillSleep` inside the deadline (FR-11).
final class SleepAllowance: @unchecked Sendable {
    let queue = DispatchQueue(label: "io.github.ovixdev.purrlo.sleep")
    private let lock = NSLock()
    private let deadline: TimeInterval
    private var allow: @Sendable (Int) -> Void
    private var token: Int?
    private var work: DispatchWorkItem?

    init(deadline: TimeInterval, allow: @escaping @Sendable (Int) -> Void) {
        self.deadline = deadline
        self.allow = allow
    }

    func allowNow(_ token: Int) {
        currentAllow()(token)
    }

    /// Production swaps in `IOAllowPowerChange` once the root port exists. Tests keep the closure from `init`.
    func redirect(_ allow: @escaping @Sendable (Int) -> Void) {
        lock.lock()
        self.allow = allow
        lock.unlock()
    }

    private func currentAllow() -> @Sendable (Int) -> Void {
        lock.lock()
        defer { lock.unlock() }
        return allow
    }

    func arm(_ token: Int) {
        let item = DispatchWorkItem { [weak self] in self?.fire() }
        lock.lock()
        self.token = token
        work?.cancel()
        work = item
        lock.unlock()
        queue.asyncAfter(deadline: .now() + deadline, execute: item)
    }

    /// The machine finished its sleep sequence, or there was nothing to do. A second call is a no-op.
    func acknowledge() {
        guard let token = take() else { return }
        currentAllow()(token)
    }

    private func fire() {
        guard let token = take() else { return }
        currentAllow()(token)
    }

    private func take() -> Int? {
        lock.lock()
        defer { lock.unlock() }
        let current = token
        token = nil
        work?.cancel()
        work = nil
        return current
    }
}

// IOKit's kIOMessage* power constants are function-like C macros that Swift does not import.
// Values from <IOKit/IOMessage.h>: iokit_common_msg(x) == 0xE0000000 | x.
let kIOMessageCanSystemSleep: UInt32 = 0xE000_0270
let kIOMessageSystemWillSleep: UInt32 = 0xE000_0280
let kIOMessageSystemWillNotSleep: UInt32 = 0xE000_0290
let kIOMessageSystemHasPoweredOn: UInt32 = 0xE000_0300
let kIOMessageSystemWillPowerOn: UInt32 = 0xE000_0320

/// Maps an IOKit system-power message onto an immediate allow or a main-actor note.
func routeSystemPowerMessage(
    _ message: UInt32,
    token: Int,
    allowance: SleepAllowance,
    deliver: @escaping @Sendable (SleepNote) -> Void
) {
    switch message {
    case UInt32(kIOMessageCanSystemSleep):
        allowance.allowNow(token)
    case UInt32(kIOMessageSystemWillSleep):
        allowance.arm(token)
        deliver(.willSleep)
    case UInt32(kIOMessageSystemWillNotSleep):
        deliver(.willNotSleep)
    case UInt32(kIOMessageSystemHasPoweredOn), UInt32(kIOMessageSystemWillPowerOn):
        break
    default:
        break
    }
}

/// `IOAllowPowerChange` and the notifications that become machine events (FR-11, FR-12, EC-8, EC-9).
@MainActor
public final class SleepCoordinator: SleepAcknowledging {
    public static let watchdogSeconds: TimeInterval = 5

    private let allowance: SleepAllowance
    private let screenLocked: () -> Bool
    private var send: ((KeepAliveEvent) -> Void)?
    private var phase: Phase = .idle
    private var waitingForUnlock = false
    private var registration: SystemPowerRegistration?
    private var observers: [NSObjectProtocol] = []
    private let logger = Logger(subsystem: KeepAliveCore.defaultSubsystem, category: "sleep")

    private enum Phase {
        case idle
        case canSleepNoted
        case willSleepSent
    }

    public init(
        watchdogSeconds: TimeInterval = SleepCoordinator.watchdogSeconds,
        allow: @escaping @Sendable (Int) -> Void = { _ in },
        screenLocked: @escaping () -> Bool = { ScreenLock.isLocked() }
    ) {
        allowance = SleepAllowance(deadline: watchdogSeconds, allow: allow)
        self.screenLocked = screenLocked
    }

    /// Registers for system power and workspace notifications. Events go to `send`.
    public func install(send: @escaping (KeepAliveEvent) -> Void) {
        bind(send)
        let registration = SystemPowerRegistration(allowance: allowance) { [weak self] note in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.apply(note) }
            }
        }
        registration.start(logger: logger)
        self.registration = registration
        observeWorkspace()
    }

    func bind(_ send: @escaping (KeepAliveEvent) -> Void) {
        self.send = send
    }

    public func allowSleep() {
        allowance.acknowledge()
    }

    func receiveCanSystemSleep(token: Int) {
        allowance.allowNow(token)
        phase = .canSleepNoted
    }

    func receiveWillSleep(token: Int) {
        allowance.arm(token)
        phase = .willSleepSent
        emit(.systemWillSleep)
    }

    /// Arms the watchdog now and delivers `systemWillSleep` on a later main-queue turn.
    func receiveWillSleepDeferred(token: Int) {
        allowance.arm(token)
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.apply(.willSleep) }
        }
    }

    func receiveWillNotSleep() {
        if phase == .willSleepSent {
            emit(.screenUnlocked)
        }
        phase = .idle
        waitingForUnlock = false
    }

    func receivePoweredOn() {}

    func receiveDidWake() {
        emit(.systemDidWake)
        if screenLocked() {
            waitingForUnlock = true
        } else {
            waitingForUnlock = false
            emit(.screenUnlocked)
        }
    }

    func receiveScreenUnlocked() {
        guard waitingForUnlock else { return }
        waitingForUnlock = false
        emit(.screenUnlocked)
    }

    func receiveScreenLocked() {}

    func receiveDisplaySleep() {}

    func receiveScreenSaver() {}

    func receiveSessionResign() {
        emit(.sessionActiveChanged(false))
    }

    func receiveSessionActive() {
        emit(.sessionActiveChanged(true))
    }

    private func apply(_ note: SleepNote) {
        switch note {
        case .willSleep:
            phase = .willSleepSent
            emit(.systemWillSleep)
        case .willNotSleep:
            receiveWillNotSleep()
        }
    }

    private func emit(_ event: KeepAliveEvent) {
        send?(event)
    }

    private func observeWorkspace() {
        let workspace = NSWorkspace.shared.notificationCenter
        func watch(_ name: Notification.Name, _ body: @escaping @MainActor (SleepCoordinator) -> Void) {
            let token = workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    body(self)
                }
            }
            observers.append(token)
        }
        watch(NSWorkspace.didWakeNotification) { $0.receiveDidWake() }
        watch(NSWorkspace.screensDidSleepNotification) { $0.receiveDisplaySleep() }
        watch(NSWorkspace.screensDidWakeNotification) { _ in }
        watch(NSWorkspace.sessionDidResignActiveNotification) { $0.receiveSessionResign() }
        watch(NSWorkspace.sessionDidBecomeActiveNotification) { $0.receiveSessionActive() }

        let distributed = DistributedNotificationCenter.default()
        func watchDistributed(_ name: String, _ body: @escaping @MainActor (SleepCoordinator) -> Void) {
            let token = distributed.addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    body(self)
                }
            }
            observers.append(token)
        }
        watchDistributed("com.apple.screenIsUnlocked") { $0.receiveScreenUnlocked() }
        watchDistributed("com.apple.screenIsLocked") { $0.receiveScreenLocked() }
        watchDistributed("com.apple.screensaver.didstart") { $0.receiveScreenSaver() }
        watchDistributed("com.apple.screensaver.didstop") { $0.receiveScreenSaver() }
    }
}

/// `CGSSessionScreenIsLocked` is present and true when the screen is locked, and absent otherwise.
public enum ScreenLock {
    public static func isLocked() -> Bool {
        guard let dictionary = copySessionDictionary(),
              let value = dictionary.object(forKey: "CGSSessionScreenIsLocked") else { return false }
        return (value as? NSNumber)?.boolValue ?? false
    }

    private static func copySessionDictionary() -> NSDictionary? {
        guard let handle = dlopen(
            "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY
        ), let symbol = dlsym(handle, "CGSessionCopyCurrentDictionary") else { return nil }
        typealias Copy = @convention(c) () -> Unmanaged<CFDictionary>?
        let copy = unsafeBitCast(symbol, to: Copy.self)
        return copy()?.takeRetainedValue()
    }
}

/// Holds the IOKit registration for the life of the coordinator.
private final class SystemPowerRegistration: @unchecked Sendable {
    private let allowance: SleepAllowance
    private let deliver: @Sendable (SleepNote) -> Void
    private var root: io_connect_t = 0
    private var port: IONotificationPortRef?
    private var notifier: io_object_t = 0

    init(allowance: SleepAllowance, deliver: @escaping @Sendable (SleepNote) -> Void) {
        self.allowance = allowance
        self.deliver = deliver
    }

    func start(logger: Logger) {
        var port: IONotificationPortRef?
        var notifier: io_object_t = 0
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let root = IORegisterForSystemPower(refcon, &port, systemPowerCallback, &notifier)
        guard root != 0, let port else {
            logger.error("IORegisterForSystemPower failed")
            return
        }
        self.root = root
        self.port = port
        self.notifier = notifier
        allowance.redirect { token in
            IOAllowPowerChange(root, token)
        }
        IONotificationPortSetDispatchQueue(port, allowance.queue)
    }

    fileprivate func handle(_ message: UInt32, token: Int) {
        routeSystemPowerMessage(message, token: token, allowance: allowance, deliver: deliver)
    }

    deinit {
        if notifier != 0 {
            var notifier = notifier
            IODeregisterForSystemPower(&notifier)
        }
        if let port {
            IONotificationPortDestroy(port)
        }
        if root != 0 {
            IOServiceClose(root)
        }
    }
}

private func systemPowerCallback(
    _ refcon: UnsafeMutableRawPointer?,
    _: io_service_t,
    _ message: UInt32,
    _ argument: UnsafeMutableRawPointer?
) {
    guard let refcon else { return }
    let registration = Unmanaged<SystemPowerRegistration>.fromOpaque(refcon).takeUnretainedValue()
    registration.handle(message, token: Int(bitPattern: argument))
}
