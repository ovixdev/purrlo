@testable import KeepAliveCore
import Testing

/// Every row of the PRD §5 transition table, plus the rules around it.
@Suite("KeepAliveMachine (§5 transitions)")
struct KeepAliveMachineTests {
    // MARK: Builders

    static func config(
        target: String? = "e2e-speaker",
        keepAlive: Bool = true,
        lid: Bool = false,
        preventIdleSleep: Bool = true,
        quietReconnect: Bool = false
    ) -> KeepAliveConfig {
        var config = KeepAliveConfig()
        config.quietReconnect = quietReconnect
        config.targetUID = target
        config.keepAlive = keepAlive
        config.lidClosedMode = lid
        config.preventIdleSleep = preventIdleSleep
        return config
    }

    /// A machine in `state`, built only through events, with the effects so far discarded.
    static func machine(
        in state: KeepAliveState,
        target: AudioDevice = speaker(),
        lid: Bool = false,
        volumePending: Bool = false,
        quietReconnect: Bool = false
    ) -> KeepAliveMachine {
        var machine = KeepAliveMachine(
            config: config(target: target.uid, keepAlive: state != .off, lid: lid, quietReconnect: quietReconnect),
            volumePending: volumePending
        )
        _ = machine.start()
        switch state {
        case .off, .waiting:
            break
        case .streaming:
            _ = machine.reduce(.devicesChanged([target]))
            _ = machine.reduce(.engineStarted)
        case .suspended:
            _ = machine.reduce(.devicesChanged([target]))
            _ = machine.reduce(.engineStarted)
            _ = machine.reduce(.systemWillSleep)
        case .error:
            _ = machine.reduce(.devicesChanged([target]))
            for _ in 0 ..< KeepAliveMachine.failuresBeforeError {
                _ = machine.reduce(.engineFailed("boom"))
                _ = machine.reduce(.timerFired(.engineRetry))
            }
            _ = machine.reduce(.engineFailed("boom"))
        }
        #expect(machine.state == state)
        return machine
    }

    /// Effects without timer bookkeeping, for order assertions.
    static func actions(_ effects: [KeepAliveEffect]) -> [KeepAliveEffect] {
        effects.filter {
            if case .cancelTimer = $0 {
                return false
            }
            return true
        }
    }

    // MARK: Off → Waiting

    @Test("FR-6: Off + user enables → Waiting, no side effects")
    func enable() {
        var machine = Self.machine(in: .off)
        let effects = machine.reduce(.configChanged(Self.config()))
        #expect(machine.state == .waiting)
        #expect(effects.isEmpty)
    }

    @Test("FR-6: Off + user enables with the target present → Streaming")
    func enableWithTargetPresent() {
        var machine = Self.machine(in: .off)
        _ = machine.reduce(.devicesChanged([speaker()]))
        let effects = machine.reduce(.configChanged(Self.config()))
        #expect(machine.state == .streaming)
        #expect(effects.contains(.startEngine(speaker(), .tone)))
    }

    @Test("EC-1: target absent at launch → Waiting with no effects or retries")
    func absentAtLaunch() {
        var machine = KeepAliveMachine(config: Self.config(), devices: [speaker(uid: "other")])
        #expect(machine.start().isEmpty)
        #expect(machine.state == .waiting)
    }

    @Test("FR-1: no target chosen → Waiting, nothing streams whatever devices exist")
    func noTargetChosen() {
        var machine = KeepAliveMachine(config: Self.config(target: nil), devices: [speaker(), echo()])
        #expect(machine.start().isEmpty)
        #expect(machine.reduce(.devicesChanged([speaker(), echo()])).isEmpty)
        #expect(machine.state == .waiting)
    }

    @Test("FR-6: Keep alive off at launch → Off")
    func offAtLaunch() {
        var machine = KeepAliveMachine(config: Self.config(keepAlive: false), devices: [speaker()])
        #expect(machine.start().isEmpty)
        #expect(machine.state == .off)
    }

    // MARK: Waiting → Streaming

    @Test("FR-3, FR-9: Waiting + target appears → Streaming; start engine, hold assertion")
    func targetAppears() {
        var machine = Self.machine(in: .waiting)
        let effects = machine.reduce(.devicesChanged([speaker()]))
        #expect(machine.state == .streaming)
        #expect(effects == [
            .startEngine(speaker(), .tone),
            .holdAssertion(reason: "Purrlo is keeping E2E Speaker connected"),
        ])
    }

    @Test("FR-3: target present at launch → Streaming at once")
    func presentAtLaunch() {
        var machine = KeepAliveMachine(config: Self.config(), devices: [speaker()])
        let effects = machine.start()
        #expect(machine.state == .streaming)
        #expect(effects.first == .startEngine(speaker(), .tone))
    }

    @Test("FR-10: Waiting + target appears with lid mode on → lid block set")
    func targetAppearsLidMode() {
        var machine = Self.machine(in: .waiting, lid: true)
        let effects = machine.reduce(.devicesChanged([speaker()]))
        #expect(effects.contains(.setLidBlock(true)))
    }

    @Test("FR-13: Waiting + target appears with a pending volume → restore scheduled 3 s after streaming starts")
    func targetAppearsVolumePending() {
        var machine = Self.machine(in: .waiting, volumePending: true)
        let effects = machine.reduce(.devicesChanged([speaker()]))
        #expect(effects.contains(.scheduleTimer(.volumeRestore, seconds: 3)))
        #expect(machine.reduce(.timerFired(.volumeRestore)) == [.restoreVolume(uid: "e2e-speaker")])
        #expect(!machine.volumePending)
    }

    @Test("FR-2: matched by UID only; a same-named device with another UID is ignored")
    func matchesByUIDOnly() {
        var machine = Self.machine(in: .waiting)
        #expect(machine.reduce(.devicesChanged([speaker(uid: "impostor")])).isEmpty)
        #expect(machine.state == .waiting)
    }

    @Test("FR-3: a target that is present but not alive does not stream")
    func deadTargetIgnored() {
        var machine = Self.machine(in: .waiting)
        _ = machine.reduce(.devicesChanged([speaker(alive: false)]))
        #expect(machine.state == .waiting)
    }

    // MARK: Streaming → Waiting

    @Test("FR-3, FR-9, EC-7: Streaming + target disappears → Waiting; stop, clear lid block, release")
    func targetDisappears() {
        var machine = Self.machine(in: .streaming)
        let effects = Self.actions(machine.reduce(.devicesChanged([])))
        #expect(machine.state == .waiting)
        #expect(effects == [.stopEngine, .setLidBlock(false), .releaseAssertion])
    }

    @Test("FR-10, A4: leaving Streaming clears the lid block even when lid mode is off")
    func lidClearedOnExitAlways() {
        var machine = Self.machine(in: .streaming, lid: false)
        #expect(machine.reduce(.devicesChanged([])).contains(.setLidBlock(false)))
    }

    @Test("FR-2, EC-6: a new AudioObjectID or sample rate restarts the engine once")
    func restartsOnDeviceChange() {
        var machine = Self.machine(in: .streaming)
        let moved = speaker(id: 99)
        #expect(machine.reduce(.devicesChanged([moved])) == [.restartEngine(moved, .tone)])
        let resampled = speaker(id: 99, rate: 44100)
        #expect(machine.reduce(.devicesChanged([resampled])) == [.restartEngine(resampled, .tone)])
        #expect(machine.reduce(.devicesChanged([resampled])).isEmpty)
        #expect(machine.state == .streaming)
    }

    @Test("EC-3: a rename alone does not restart the engine")
    func renameKeepsStreaming() {
        var machine = Self.machine(in: .streaming)
        #expect(machine.reduce(.devicesChanged([speaker(name: "Renamed")])).isEmpty)
        #expect(machine.target?.name == "Renamed")
    }

    // MARK: Cut-offs

    @Test("FR-10, FR-15: Streaming + cut-off → Streaming; clear lid block, notify, assertion stays")
    func cutOff() {
        var machine = Self.machine(in: .streaming, lid: true)
        #expect(machine.lidBlockSet)
        let effects = machine.reduce(.cutOffChanged(active: true, reason: "Battery at 20%"))
        #expect(machine.state == .streaming)
        #expect(effects == [.notify(.cutOff("Battery at 20%")), .setLidBlock(false)])
        #expect(machine.assertionHeld)
        #expect(machine.reduce(.cutOffChanged(active: false, reason: "")) == [.setLidBlock(true)])
    }

    @Test("FR-15: a cut-off with lid mode off changes nothing and does not notify")
    func cutOffWithoutLidMode() {
        var machine = Self.machine(in: .streaming)
        #expect(machine.reduce(.cutOffChanged(active: true, reason: "Battery")).isEmpty)
        #expect(machine.reduce(.cutOffChanged(active: true, reason: "Battery")).isEmpty)
    }

    // MARK: Disable

    @Test(
        "FR-6: Any + user disables → Off and everything released",
        arguments: [KeepAliveState.waiting, .streaming, .suspended, .error]
    )
    func disableFromAnyState(state: KeepAliveState) {
        var machine = Self.machine(in: state, target: echo(), lid: true)
        var config = machine.config
        config.keepAlive = false
        let effects = machine.reduce(.configChanged(config))
        #expect(machine.state == .off)
        #expect(!machine.engineRunning && !machine.assertionHeld && !machine.lidBlockSet)
        for id in TimerID.allCases {
            #expect(effects.contains(.cancelTimer(id)))
        }
        if state == .streaming {
            #expect(Self.actions(effects) == [.stopEngine, .setLidBlock(false), .releaseAssertion])
        }
    }

    @Test("FR-13 (dropped, kept off), EC-12: disabling restores a pending volume when the target is present")
    func disableRestoresVolume() {
        var suspended = Self.machine(in: .suspended, target: echo(), quietReconnect: true)
        _ = suspended.reduce(.devicesChanged([echo()]))
        var config = suspended.config
        config.keepAlive = false
        #expect(suspended.reduce(.configChanged(config)).contains(.restoreVolume(uid: echoUID)))
        #expect(!suspended.volumePending)
    }

    @Test("EC-12: a volume left at 0 by a crash is restored when the target next appears, even while Off")
    func volumeRestoredWhileOff() {
        var machine = KeepAliveMachine(config: Self.config(target: echoUID, keepAlive: false), volumePending: true)
        _ = machine.start()
        #expect(machine.reduce(.devicesChanged([echo()])) == [.restoreVolume(uid: echoUID)])
        #expect(machine.reduce(.devicesChanged([echo()])).isEmpty)
    }

    // MARK: Settings changes

    @Test("FR-9: turning Prevent idle sleep off releases the assertion and on holds it again")
    func preventIdleSleepToggle() {
        var machine = Self.machine(in: .streaming)
        var config = machine.config
        config.preventIdleSleep = false
        #expect(machine.reduce(.configChanged(config)) == [.releaseAssertion])
        #expect(machine.state == .streaming)
        config.preventIdleSleep = true
        #expect(machine
            .reduce(.configChanged(config)) == [.holdAssertion(reason: "Purrlo is keeping E2E Speaker connected")])
    }

    @Test("FR-4: switching the signal restarts the engine with the new signal")
    func signalChange() {
        var machine = Self.machine(in: .streaming)
        var config = machine.config
        config.signal = .silence
        #expect(machine.reduce(.configChanged(config)) == [.restartEngine(speaker(), .silence)])
    }

    @Test("FR-1, FR-2: choosing another present target stops the old stream and starts the new one at once")
    func targetChange() {
        var machine = Self.machine(in: .streaming)
        _ = machine.reduce(.devicesChanged([speaker(), echo()]))
        var config = machine.config
        config.targetUID = echoUID
        let effects = Self.actions(machine.reduce(.configChanged(config)))
        #expect(effects.first == .stopEngine)
        #expect(effects.contains(.startEngine(echo(), .tone)))
        #expect(machine.state == .streaming)
        #expect(machine.target == echo())
    }

    @Test("FR-1, FR-2: choosing a target that is not present → Waiting with everything released")
    func targetChangeToAbsent() {
        var machine = Self.machine(in: .streaming)
        var config = machine.config
        config.targetUID = echoUID
        let effects = Self.actions(machine.reduce(.configChanged(config)))
        #expect(effects == [.stopEngine, .setLidBlock(false), .releaseAssertion])
        #expect(machine.state == .waiting)
    }
}
