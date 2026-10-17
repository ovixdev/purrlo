@testable import KeepAliveCore

/// Recording fakes for every AppState port. `calls` keeps one ordered list across fakes, so tests can assert order.
@MainActor
final class CallLog {
    var calls: [String] = []
}

@MainActor
final class FakeDeviceMonitor: DeviceMonitoring {
    private(set) var devices: [AudioDevice]
    private var onChange: (@MainActor ([AudioDevice]) -> Void)?
    private(set) var stopped = false

    init(_ devices: [AudioDevice] = []) {
        self.devices = devices
    }

    func start(onChange: @escaping @MainActor ([AudioDevice]) -> Void) {
        self.onChange = onChange
    }

    func stop() {
        stopped = true
        onChange = nil
    }

    func publish(_ devices: [AudioDevice]) {
        self.devices = devices
        onChange?(devices)
    }
}

@MainActor
final class RecordingEngine: KeepAliveEngine {
    let log: CallLog
    var failuresLeft = 0
    private(set) var isRunning = false
    private(set) var startedWith: [(AudioDevice, SignalKind)] = []

    init(log: CallLog) {
        self.log = log
    }

    func start(device: AudioDevice, signal: SignalKind) throws(EngineError) {
        log.calls.append("engine.start(\(device.uid)@\(Int(device.nominalSampleRate)),\(signal.rawValue))")
        if failuresLeft > 0 {
            failuresLeft -= 1
            isRunning = false
            throw EngineError(operation: "fake start", status: -1)
        }
        startedWith.append((device, signal))
        isRunning = true
    }

    func stop() {
        log.calls.append("engine.stop")
        isRunning = false
    }
}

@MainActor
final class FakePower: PowerManaging {
    let log: CallLog
    var failHold = false
    private(set) var isHoldingIdleSleepAssertion = false

    init(log: CallLog) {
        self.log = log
    }

    func holdIdleSleepAssertion(reason _: String) throws {
        log.calls.append("power.hold")
        if failHold {
            throw PowerAssertionError(status: -1)
        }
        isHoldingIdleSleepAssertion = true
    }

    func releaseIdleSleepAssertion() {
        log.calls.append("power.release")
        isHoldingIdleSleepAssertion = false
    }
}

@MainActor
final class RecordingPorts: HelperControlling, BluetoothControlling, VolumeControlling, Notifying,
    SleepAcknowledging
{
    let log: CallLog
    var connectSucceeds = false
    var hasPendingRestore = false
    private(set) var notifications: [NotificationKind] = []

    init(log: CallLog) {
        self.log = log
    }

    func setSleepDisabled(_ disabled: Bool) {
        log.calls.append("helper.setSleepDisabled(\(disabled))")
    }

    func disconnect(uid: String) {
        log.calls.append("bt.closeConnection(\(uid))")
    }

    func connect(uid: String) async -> Bool {
        log.calls.append("bt.openConnection(\(uid))")
        return connectSucceeds
    }

    func saveAndZero(uid: String) {
        log.calls.append("volume.saveAndZero(\(uid))")
        hasPendingRestore = true
    }

    func restore(uid: String) {
        log.calls.append("volume.restore(\(uid))")
        hasPendingRestore = false
    }

    func post(_ notification: NotificationKind) {
        notifications.append(notification)
        log.calls.append("notify")
    }

    func allowSleep() {
        log.calls.append("allowSleep")
    }
}

/// Timers fire only when a test says so.
@MainActor
final class ManualScheduler: Scheduling {
    private(set) var pending: [TimerID: (seconds: Double, fire: @MainActor () -> Void)] = [:]

    func schedule(_ id: TimerID, after seconds: Double, _ fire: @escaping @MainActor () -> Void) {
        pending[id] = (seconds, fire)
    }

    func cancel(_ id: TimerID) {
        pending[id] = nil
    }

    func fire(_ id: TimerID) {
        guard let timer = pending.removeValue(forKey: id) else { return }
        timer.fire()
    }
}

@MainActor
final class FakeLoginItem: LoginItemControlling {
    struct Failure: Error {}
    var failNext = false
    private(set) var isEnabled = false
    private(set) var calls: [Bool] = []

    func setEnabled(_ enabled: Bool) throws {
        calls.append(enabled)
        if failNext {
            failNext = false
            throw Failure()
        }
        isEnabled = enabled
    }
}

func speaker(
    uid: String = "e2e-speaker",
    id: UInt32 = 10,
    name: String = "E2E Speaker",
    rate: Double = 48000,
    channels: Int = 2,
    transport: Transport = .aggregate,
    alive: Bool = true
) -> AudioDevice {
    AudioDevice(
        uid: uid, objectID: id, name: name, transport: transport,
        outputChannels: channels, nominalSampleRate: rate, isAlive: alive
    )
}

let echoUID = "E8-4C-4A-8A-9A-39:output"

func echo(id: UInt32 = 20, rate: Double = 44100) -> AudioDevice {
    speaker(uid: echoUID, id: id, name: "Echo Dot", rate: rate, transport: .bluetooth)
}
