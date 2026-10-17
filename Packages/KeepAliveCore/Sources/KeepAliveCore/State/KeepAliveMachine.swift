import Foundation

/// The five states of PRD §5.
public enum KeepAliveState: String, Sendable, Codable, CaseIterable {
    case off, waiting, streaming, suspended, error
}

/// User preferences the machine reads. Defaults follow PRD §4 and the M1 plan (A7).
public struct KeepAliveConfig: Sendable, Equatable, Codable {
    public var keepAlive = true
    public var targetUID: String?
    public var signal: SignalKind = .tone
    public var preventIdleSleep = true
    public var lidClosedMode = false
    public var disconnectBeforeSleep = true
    public var reconnectAfterUnlock = true
    public var quietReconnect = true

    public init() {}
}

public enum TimerID: String, Sendable, Codable, CaseIterable {
    case engineRetry, reconnectRetry, volumeRestore
}

public enum NotificationKind: Sendable, Equatable, Codable {
    case engineError
    case cutOff(String)
}

public enum KeepAliveEvent: Sendable, Equatable {
    case configChanged(KeepAliveConfig)
    case devicesChanged([AudioDevice])
    case engineStarted
    case engineFailed(String)
    case timerFired(TimerID)
    case cutOffChanged(active: Bool, reason: String)
    case systemWillSleep
    case systemDidWake
    case screenUnlocked
    case reconnectFailed
}

public enum KeepAliveEffect: Sendable, Equatable {
    case startEngine(AudioDevice, SignalKind)
    /// Stop and start again, e.g. on a sample-rate or AudioObjectID change (EC-6); logged separately for E2E-6.
    case restartEngine(AudioDevice, SignalKind)
    case stopEngine
    case holdAssertion(reason: String)
    case releaseAssertion
    case setLidBlock(Bool)
    case saveAndZeroVolume(uid: String)
    case restoreVolume(uid: String)
    case disconnectBluetooth(uid: String)
    case connectBluetooth(uid: String)
    case scheduleTimer(TimerID, seconds: Double)
    case cancelTimer(TimerID)
    case notify(NotificationKind)
    case allowSleep
}

/// Pure state machine of PRD §5: `reduce` maps one event to the next machine and its side effects.
/// Resources (engine, assertion, lid block) are reconciled from the desired state after every event,
/// so no path can leak one; one-shot actions (volume, Bluetooth, timers) are emitted by the event handlers.
public struct KeepAliveMachine: Sendable, Equatable {
    /// Engine restart delays after consecutive failures; Error after the third failed restart (M1 plan, A6).
    public static let engineRetryDelays: [Double] = [1, 2, 5, 10, 30]
    public static let failuresBeforeError = 4
    public static let reconnectRetryDelay: Double = 10
    public static let volumeRestoreDelay: Double = 3

    public private(set) var state: KeepAliveState
    public private(set) var config: KeepAliveConfig
    /// The present, alive target device, matched by UID only (FR-2).
    public private(set) var target: AudioDevice?
    public private(set) var engineRunning = false
    public private(set) var engineFailures = 0
    public private(set) var assertionHeld = false
    public private(set) var lidBlockSet = false
    public private(set) var cutOffActive = false
    /// FR-12: the app closed the target's connection before sleep.
    public private(set) var disconnectedByApp = false
    /// FR-13: a saved volume waits to be restored (persisted by the volume manager, EC-12).
    public private(set) var volumePending = false
    public private(set) var reconnectAttempts = 0
    private var lastStartedDevice: AudioDevice?
    /// Latest device list, so a newly chosen target that is already present streams at once.
    private var devices: [AudioDevice]

    public init(config: KeepAliveConfig, devices: [AudioDevice] = [], volumePending: Bool = false) {
        self.config = config
        self.volumePending = volumePending
        state = config.keepAlive ? .waiting : .off
        self.devices = devices
        target = Self.findTarget(config.targetUID, in: devices)
    }

    /// Effects needed right after launch (EC-1: target absent gives Waiting and no effects).
    public mutating func start() -> [KeepAliveEffect] {
        var effects: [KeepAliveEffect] = []
        restoreVolumeIfIdle(&effects)
        reconcile(&effects, previous: .off)
        return effects
    }

    public mutating func reduce(_ event: KeepAliveEvent) -> [KeepAliveEffect] {
        let previous = state
        var effects: [KeepAliveEffect] = []
        switch event {
        case let .configChanged(new): configChanged(new, &effects)
        case let .devicesChanged(devices): devicesChanged(devices, &effects)
        case .engineStarted: engineStarted()
        case .engineFailed: engineFailed(&effects)
        case let .timerFired(id): timerFired(id, &effects)
        case let .cutOffChanged(active, reason): cutOffChanged(active, reason: reason, &effects)
        case .systemWillSleep: willSleep(&effects)
        case .systemDidWake: break // Suspended waits for unlock; other states ignore wakes (§5 wake sequence).
        case .screenUnlocked: unlocked(&effects)
        case .reconnectFailed: reconnectFailed(&effects)
        }
        reconcile(&effects, previous: previous)
        return effects
    }

    // MARK: Events

    private mutating func configChanged(_ new: KeepAliveConfig, _ effects: inout [KeepAliveEffect]) {
        let old = config
        config = new
        if old.targetUID != new.targetUID {
            // A different speaker: drop everything tied to the old one.
            if engineRunning {
                stopEngine(&effects)
            }
            target = Self.findTarget(new.targetUID, in: devices)
            engineFailures = 0
            disconnectedByApp = false
            reconnectAttempts = 0
            effects.append(.cancelTimer(.reconnectRetry))
            if state == .streaming || state == .error {
                state = .waiting
            }
        }
        if !new.keepAlive, state != .off {
            disable(&effects)
            return
        }
        if new.keepAlive, state == .off {
            state = .waiting
        }
        if old.signal != new.signal, engineRunning, let target {
            effects.append(.restartEngine(target, new.signal))
            lastStartedDevice = target
        }
        if state == .error, old != new {
            retryNow(&effects) // A user action resets the retry schedule (A6).
        }
    }

    private mutating func devicesChanged(_ devices: [AudioDevice], _ effects: inout [KeepAliveEffect]) {
        self.devices = devices
        let found = Self.findTarget(config.targetUID, in: devices)
        let appeared = target == nil && found != nil
        target = found

        switch state {
        case .off:
            restoreVolumeIfIdle(&effects)
        case .waiting:
            break // reconcile promotes Waiting to Streaming once the target is present.
        case .streaming, .error:
            if found == nil {
                state = .waiting
                engineFailures = 0
                effects.append(.cancelTimer(.engineRetry))
                effects.append(.cancelTimer(.volumeRestore))
            } else if state == .error, let found, found != lastStartedDevice {
                retryNow(&effects) // Device change resets the schedule (A6).
            }
        case .suspended:
            // §5 wake step 5: the target came back on its own, so the unlock skips the reconnect.
            if appeared {
                disconnectedByApp = false
            }
        }
    }

    private mutating func engineStarted() {
        engineFailures = 0
        if state == .error {
            state = .streaming
        }
    }

    private mutating func engineFailed(_ effects: inout [KeepAliveEffect]) {
        guard state == .streaming || state == .error else { return }
        engineRunning = false
        lastStartedDevice = nil
        engineFailures += 1
        if engineFailures >= Self.failuresBeforeError, state != .error {
            state = .error
            effects.append(.notify(.engineError))
        }
        let delay = Self.engineRetryDelays[min(engineFailures - 1, Self.engineRetryDelays.count - 1)]
        effects.append(.scheduleTimer(.engineRetry, seconds: delay))
    }

    private mutating func timerFired(_ id: TimerID, _ effects: inout [KeepAliveEffect]) {
        switch id {
        case .engineRetry:
            guard state == .streaming || state == .error, !engineRunning, let target else { return }
            startEngine(target, &effects)
        case .reconnectRetry:
            guard state == .waiting, target == nil, disconnectedByApp, reconnectAttempts == 1,
                  let uid = config.targetUID else { return }
            reconnectAttempts = 2
            effects.append(.connectBluetooth(uid: uid))
        case .volumeRestore:
            guard volumePending, let target, state == .streaming || state == .off else { return }
            volumePending = false
            effects.append(.restoreVolume(uid: target.uid))
        }
    }

    private mutating func cutOffChanged(_ active: Bool, reason: String, _ effects: inout [KeepAliveEffect]) {
        guard active != cutOffActive else { return }
        cutOffActive = active
        if active, lidBlockSet {
            effects.append(.notify(.cutOff(reason))) // FR-15; the block itself is cleared by reconcile.
        }
    }

    private mutating func willSleep(_ effects: inout [KeepAliveEffect]) {
        guard state == .streaming || state == .waiting || state == .error else {
            effects.append(.allowSleep)
            return
        }
        // §5 sleep sequence: stop engine, FR-13 volume, FR-11 disconnect, clear lid block, release, allow.
        if engineRunning {
            stopEngine(&effects)
        }
        effects.append(.cancelTimer(.engineRetry))
        effects.append(.cancelTimer(.volumeRestore))
        effects.append(.cancelTimer(.reconnectRetry))
        engineFailures = 0
        if let target, target.bluetoothAddress != nil {
            if config.quietReconnect, !volumePending {
                volumePending = true
                effects.append(.saveAndZeroVolume(uid: target.uid))
            }
            if config.disconnectBeforeSleep {
                disconnectedByApp = true
                effects.append(.disconnectBluetooth(uid: target.uid))
            }
        }
        state = .suspended
        lidBlockSet = false
        effects.append(.setLidBlock(false))
        releaseAssertion(&effects)
        effects.append(.allowSleep)
    }

    private mutating func unlocked(_ effects: inout [KeepAliveEffect]) {
        guard state == .suspended else { return }
        state = config.keepAlive ? .waiting : .off
        if target != nil {
            disconnectedByApp = false
        } else if disconnectedByApp, config.reconnectAfterUnlock, state == .waiting, let uid = config.targetUID {
            reconnectAttempts = 1
            effects.append(.connectBluetooth(uid: uid)) // FR-5: the only connect the app ever makes.
        }
    }

    private mutating func reconnectFailed(_ effects: inout [KeepAliveEffect]) {
        guard state == .waiting, target == nil, disconnectedByApp else { return }
        if reconnectAttempts == 1 {
            effects.append(.scheduleTimer(.reconnectRetry, seconds: Self.reconnectRetryDelay))
        } else {
            // EC-11: one retry, then stay Waiting with no further attempts.
            disconnectedByApp = false
            reconnectAttempts = 0
        }
    }

    // MARK: Helpers

    private mutating func disable(_ effects: inout [KeepAliveEffect]) {
        state = .off
        engineFailures = 0
        disconnectedByApp = false
        reconnectAttempts = 0
        for id in TimerID.allCases {
            effects.append(.cancelTimer(id))
        }
        restoreVolumeIfIdle(&effects)
    }

    private mutating func retryNow(_ effects: inout [KeepAliveEffect]) {
        engineFailures = 0
        effects.append(.cancelTimer(.engineRetry))
        if !engineRunning, let target {
            startEngine(target, &effects)
        }
    }

    /// While Off the target gets its saved volume back as soon as it is present (EC-12, "restore volume if pending").
    private mutating func restoreVolumeIfIdle(_ effects: inout [KeepAliveEffect]) {
        guard state == .off, volumePending, let target else { return }
        volumePending = false
        effects.append(.restoreVolume(uid: target.uid))
    }

    private mutating func startEngine(_ device: AudioDevice, _ effects: inout [KeepAliveEffect]) {
        effects.append(.startEngine(device, config.signal))
        engineRunning = true
        lastStartedDevice = device
    }

    private mutating func stopEngine(_ effects: inout [KeepAliveEffect]) {
        effects.append(.stopEngine)
        engineRunning = false
        lastStartedDevice = nil
    }

    private mutating func releaseAssertion(_ effects: inout [KeepAliveEffect]) {
        guard assertionHeld else { return }
        assertionHeld = false
        effects.append(.releaseAssertion)
    }

    /// Brings engine, lid block and assertion in line with the state table of §5.
    private mutating func reconcile(_ effects: inout [KeepAliveEffect], previous: KeepAliveState) {
        // Waiting means "enabled, target not present": the moment it is present, stream.
        if state == .waiting, target != nil {
            state = .streaming
            if reconnectAttempts > 0 {
                effects.append(.cancelTimer(.reconnectRetry))
            }
            reconnectAttempts = 0
            disconnectedByApp = false
        }
        reconcileEngine(&effects)
        reconcileLidBlock(&effects, leftStreaming: previous == .streaming && state != .streaming)
        reconcileAssertion(&effects)
    }

    /// Runs only in Streaming; while a failed start waits for its retry timer it stays stopped.
    private mutating func reconcileEngine(_ effects: inout [KeepAliveEffect]) {
        guard state == .streaming, let target else {
            // Error keeps its pending retry while the target is present.
            if engineRunning, state != .error || target == nil {
                stopEngine(&effects)
            }
            return
        }
        if !engineRunning {
            guard engineFailures == 0 else { return }
            startEngine(target, &effects)
            if volumePending {
                effects.append(.scheduleTimer(.volumeRestore, seconds: Self.volumeRestoreDelay))
            }
        } else if let last = lastStartedDevice, Self.needsRestart(last, target) {
            effects.append(.restartEngine(target, config.signal)) // EC-6 sample rate, new AudioObjectID.
            lastStartedDevice = target
        }
    }

    /// Set only in Streaming; cleared on any exit from Streaming and on every cut-off (§5, A4).
    private mutating func reconcileLidBlock(_ effects: inout [KeepAliveEffect], leftStreaming: Bool) {
        let wanted = state == .streaming && engineRunning && config.lidClosedMode && !cutOffActive
        if wanted, !lidBlockSet {
            lidBlockSet = true
            effects.append(.setLidBlock(true))
        } else if !wanted, lidBlockSet || leftStreaming, !effects.contains(.setLidBlock(false)) {
            lidBlockSet = false
            effects.append(.setLidBlock(false))
        }
    }

    /// FR-9 and §5: held in Streaming, and in Error while the target is present (A9).
    private mutating func reconcileAssertion(_ effects: inout [KeepAliveEffect]) {
        let wanted = config.keepAlive && config.preventIdleSleep && target != nil
            && (state == .streaming || state == .error)
        if wanted, !assertionHeld {
            assertionHeld = true
            effects.append(.holdAssertion(reason: Self.assertionReason(target)))
        } else if !wanted {
            releaseAssertion(&effects)
        }
    }

    private static func needsRestart(_ old: AudioDevice, _ new: AudioDevice) -> Bool {
        old.objectID != new.objectID || old.nominalSampleRate != new.nominalSampleRate
            || old.outputChannels != new.outputChannels
    }

    private static func findTarget(_ uid: String?, in devices: [AudioDevice]) -> AudioDevice? {
        guard let uid else { return nil }
        return devices.first { $0.uid == uid && $0.isAlive && $0.outputChannels > 0 }
    }

    static func assertionReason(_ target: AudioDevice?) -> String {
        "Purrlo is keeping \(target?.name ?? "the speaker") connected"
    }
}
