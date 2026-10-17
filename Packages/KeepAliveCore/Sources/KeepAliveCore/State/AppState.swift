import Foundation
import Observation
import os

/// Owns the §5 state machine and executes its effects. The UI only reads it (PRD §5).
@MainActor
@Observable
public final class AppState {
    public struct Ports {
        public var deviceMonitor: any DeviceMonitoring
        public var engine: any KeepAliveEngine
        public var power: any PowerManaging
        public var helper: any HelperControlling
        public var bluetooth: any BluetoothControlling
        public var volume: any VolumeControlling
        public var notifier: any Notifying
        public var sleep: any SleepAcknowledging
        public var scheduler: any Scheduling
        public var loginItem: any LoginItemControlling

        public init(
            deviceMonitor: any DeviceMonitoring,
            engine: any KeepAliveEngine,
            power: any PowerManaging,
            helper: any HelperControlling,
            bluetooth: any BluetoothControlling,
            volume: any VolumeControlling,
            notifier: any Notifying,
            sleep: any SleepAcknowledging,
            scheduler: any Scheduling,
            loginItem: any LoginItemControlling
        ) {
            self.deviceMonitor = deviceMonitor
            self.engine = engine
            self.power = power
            self.helper = helper
            self.bluetooth = bluetooth
            self.volume = volume
            self.notifier = notifier
            self.sleep = sleep
            self.scheduler = scheduler
            self.loginItem = loginItem
        }
    }

    public private(set) var machine: KeepAliveMachine
    public private(set) var devices: [AudioDevice] = []
    public private(set) var launchAtLogin: Bool
    /// Last error from a user action that failed outside the machine, such as Launch at Login.
    public private(set) var lastError: String?
    @ObservationIgnored public let log = TransitionLog()

    @ObservationIgnored private let settings: Settings
    @ObservationIgnored private let ports: Ports
    @ObservationIgnored private let logger: Logger
    @ObservationIgnored private var pending: [KeepAliveEvent] = []
    @ObservationIgnored private var processing = false
    @ObservationIgnored private var started = false

    public init(settings: Settings, ports: Ports, subsystem: String = KeepAliveCore.defaultSubsystem) {
        self.settings = settings
        self.ports = ports
        logger = Logger(subsystem: subsystem, category: "state")
        machine = KeepAliveMachine(config: Self.config(from: settings), volumePending: ports.volume.hasPendingRestore)
        launchAtLogin = ports.loginItem.isEnabled
    }

    public var status: StatusLine {
        StatusText.make(machine, targetName: settings.targetDisplayName)
    }

    public var state: KeepAliveState {
        machine.state
    }

    /// Starts device monitoring and applies the launch state (EC-1: an absent target leaves the app Waiting).
    public func start() {
        guard !started else { return }
        started = true
        ports.deviceMonitor.start { [weak self] devices in
            guard let self else { return }
            self.send(.devicesChanged(self.annotate(devices)))
        }
        devices = annotate(ports.deviceMonitor.devices)
        machine = KeepAliveMachine(
            config: Self.config(from: settings),
            devices: devices,
            volumePending: ports.volume.hasPendingRestore
        )
        let before = machine.state
        let effects = machine.start()
        record(from: before, event: "launch", effects: effects)
        noteTargetRename()
        execute(effects)
        drain()
    }

    public func stop() {
        ports.deviceMonitor.stop()
        send(.configChanged(Self.config(keepAlive: false, from: settings)))
    }

    // MARK: User actions

    public func setKeepAlive(_ enabled: Bool) {
        settings.keepAlive = enabled
        configChanged()
    }

    /// FR-1, FR-2: picks the target by UID and remembers its current name for display.
    public func selectTarget(uid: String) {
        let name = devices.first { $0.uid == uid }?.name ?? uid
        settings.setTarget(uid: uid, name: name)
        configChanged()
    }

    public func setSignal(_ signal: SignalKind) {
        settings.signal = signal
        configChanged()
    }

    public func setPreventIdleSleep(_ enabled: Bool) {
        settings.preventIdleSleep = enabled
        configChanged()
    }

    /// FR-7.
    public func setLaunchAtLogin(_ enabled: Bool) {
        do {
            try ports.loginItem.setEnabled(enabled)
            lastError = nil
        } catch {
            lastError = "Launch at Login: \(error.localizedDescription)"
            logger.error("Launch at Login failed: \(error.localizedDescription, privacy: .public)")
        }
        launchAtLogin = ports.loginItem.isEnabled
    }

    // MARK: Events

    /// Feeds one event to the machine. Events raised while effects run are queued, so the log stays ordered.
    public func send(_ event: KeepAliveEvent) {
        pending.append(event)
        drain()
    }

    private func drain() {
        guard !processing else { return }
        processing = true
        defer { processing = false }
        while !pending.isEmpty {
            let event = pending.removeFirst()
            if case let .devicesChanged(list) = event {
                devices = list
            }
            let before = machine.state
            let effects = machine.reduce(event)
            record(from: before, event: event.logDescription, effects: effects)
            if case .devicesChanged = event {
                noteTargetRename()
            }
            execute(effects)
        }
    }

    private func configChanged() {
        send(.configChanged(Self.config(from: settings)))
    }

    private func record(from: KeepAliveState, event: String, effects: [KeepAliveEffect]) {
        let entry = log.record(from: from, event: event, to: machine.state, effects: effects)
        // Device names are the only personal data and never appear here (NFR-9), so the line is public.
        let effects = entry.effects.joined(separator: ", ")
        let line = "\(entry.from.rawValue) --\(entry.event)--> \(entry.to.rawValue) [\(effects)]"
        logger.info("\(line, privacy: .public)")
    }

    /// EC-3: the target is matched by UID; a new name is only remembered for display.
    private func noteTargetRename() {
        if let target = machine.target, target.name != settings.targetDisplayName {
            settings.noteTargetName(target.name)
        }
    }

    private func execute(_ effects: [KeepAliveEffect]) {
        for effect in effects {
            execute(effect)
        }
    }

    private func execute(_ effect: KeepAliveEffect) {
        switch effect {
        case let .startEngine(device, signal), let .restartEngine(device, signal):
            do {
                try ports.engine.start(device: device, signal: signal)
                pending.append(.engineStarted)
            } catch {
                logger.error("Engine start failed: \(error.description, privacy: .public)")
                pending.append(.engineFailed(error.description))
            }
        case .stopEngine:
            ports.engine.stop()
        case let .holdAssertion(reason):
            do {
                try ports.power.holdIdleSleepAssertion(reason: reason)
            } catch {
                logger.error("Idle-sleep assertion failed: \(String(describing: error), privacy: .public)")
            }
        case .releaseAssertion:
            ports.power.releaseIdleSleepAssertion()
        case let .setLidBlock(blocked):
            ports.helper.setSleepDisabled(blocked)
        case let .saveAndZeroVolume(uid):
            ports.volume.saveAndZero(uid: uid)
        case let .restoreVolume(uid):
            ports.volume.restore(uid: uid)
        case let .disconnectBluetooth(uid):
            ports.bluetooth.disconnect(uid: uid)
        case let .connectBluetooth(uid):
            Task { [weak self] in
                guard let self, await !ports.bluetooth.connect(uid: uid) else { return }
                send(.reconnectFailed)
            }
        case let .scheduleTimer(id, seconds):
            ports.scheduler.schedule(id, after: seconds) { [weak self] in self?.send(.timerFired(id)) }
        case let .cancelTimer(id):
            ports.scheduler.cancel(id)
        case let .notify(kind):
            ports.notifier.post(kind)
        case .allowSleep:
            ports.sleep.allowSleep()
        }
    }

    /// The Bluetooth port stamps each device before the machine sees it. One call per list update.
    private func annotate(_ list: [AudioDevice]) -> [AudioDevice] {
        let controls = ports.bluetooth.controls(for: list)
        return list.map { device in
            var device = device
            device.bluetoothControl = controls[device.uid] ?? .unavailable
            return device
        }
    }

    private static func config(keepAlive: Bool? = nil, from settings: Settings) -> KeepAliveConfig {
        var config = KeepAliveConfig()
        config.keepAlive = keepAlive ?? settings.keepAlive
        config.targetUID = settings.targetUID
        config.signal = settings.signal
        config.preventIdleSleep = settings.preventIdleSleep
        return config
    }
}
