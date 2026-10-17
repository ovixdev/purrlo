@testable import KeepAliveCore
import Testing

/// §5 rows for sleep, wake, unlock and engine errors (FR-5, FR-11 to FR-13, A6).
extension KeepAliveMachineTests {
    // MARK: Sleep

    @Test("FR-11: Streaming + will sleep → Suspended in the §5 order, within one event, volume untouched")
    func willSleepOrder() {
        var machine = Self.machine(in: .streaming, target: echo(), lid: true)
        let effects = Self.actions(machine.reduce(.systemWillSleep))
        #expect(machine.state == .suspended)
        #expect(effects == [
            .stopEngine,
            .disconnectBluetooth(uid: echoUID),
            .setLidBlock(false),
            .releaseAssertion,
            .allowSleep,
        ])
        #expect(machine.disconnectedByApp)
        #expect(!machine.volumePending)
    }

    @Test("FR-13 (dropped, kept off): with quiet reconnect enabled the volume is zeroed before the disconnect")
    func willSleepOrderQuietReconnect() {
        var machine = Self.machine(in: .streaming, target: echo(), lid: true, quietReconnect: true)
        let effects = Self.actions(machine.reduce(.systemWillSleep))
        #expect(effects == [
            .stopEngine,
            .saveAndZeroVolume(uid: echoUID),
            .disconnectBluetooth(uid: echoUID),
            .setLidBlock(false),
            .releaseAssertion,
            .allowSleep,
        ])
        #expect(machine.disconnectedByApp)
    }

    @Test("FR-11: Waiting + will sleep → Suspended with nothing to disconnect")
    func willSleepFromWaiting() {
        var machine = Self.machine(in: .waiting, target: echo())
        let effects = Self.actions(machine.reduce(.systemWillSleep))
        #expect(machine.state == .suspended)
        #expect(effects == [.setLidBlock(false), .allowSleep])
        #expect(!machine.disconnectedByApp)
    }

    @Test("EC-18: a target without a Bluetooth address streams but is never disconnected or muted")
    func noBluetoothAddress() {
        var machine = Self.machine(in: .streaming, target: speaker())
        let effects = machine.reduce(.systemWillSleep)
        #expect(!effects.contains {
            if case .disconnectBluetooth = $0 {
                true
            } else {
                false
            }
        })
        #expect(!effects.contains {
            if case .saveAndZeroVolume = $0 {
                true
            } else {
                false
            }
        })
    }

    @Test("FR-11: Off + will sleep only allows sleep")
    func willSleepFromOff() {
        var machine = Self.machine(in: .off)
        #expect(machine.reduce(.systemWillSleep) == [.allowSleep])
        #expect(machine.state == .off)
    }

    @Test("FR-11: a second will-sleep while Suspended only allows sleep")
    func willSleepWhileSuspended() {
        var machine = Self.machine(in: .suspended, target: echo())
        #expect(machine.reduce(.systemWillSleep) == [.allowSleep])
    }

    @Test("FR-12: Suspended + full wake → Suspended, waiting for unlock (dark wakes never reach the machine)")
    func fullWake() {
        var machine = Self.machine(in: .suspended, target: echo())
        #expect(machine.reduce(.systemDidWake).isEmpty)
        #expect(machine.state == .suspended)
    }

    @Test("FR-5, FR-12: Suspended + unlock → Waiting and exactly one connect")
    func unlockReconnects() {
        var machine = Self.machine(in: .suspended, target: echo())
        _ = machine.reduce(.devicesChanged([]))
        _ = machine.reduce(.systemDidWake)
        #expect(machine.reduce(.screenUnlocked) == [.connectBluetooth(uid: echoUID)])
        #expect(machine.state == .waiting)
        #expect(machine.reduce(.screenUnlocked).isEmpty)
    }

    @Test("FR-12, FR-13 (dropped, kept off): after the reconnect the target streams; a saved volume returns 3 s later")
    func reconnectStreamsAndRestores() {
        var machine = Self.machine(in: .suspended, target: echo(), quietReconnect: true)
        _ = machine.reduce(.devicesChanged([]))
        _ = machine.reduce(.screenUnlocked)
        let effects = machine.reduce(.devicesChanged([echo()]))
        #expect(machine.state == .streaming)
        #expect(effects.contains(.startEngine(echo(), .tone)))
        #expect(effects.contains(.scheduleTimer(.volumeRestore, seconds: 3)))
        #expect(effects.contains(.cancelTimer(.reconnectRetry)))
        #expect(machine.reduce(.timerFired(.volumeRestore)) == [.restoreVolume(uid: echoUID)])
    }

    @Test("EC-11: a failed reconnect retries once after 10 s, then stays Waiting with no further calls")
    func reconnectRetriesOnce() {
        var machine = Self.machine(in: .suspended, target: echo())
        _ = machine.reduce(.devicesChanged([]))
        _ = machine.reduce(.screenUnlocked)
        #expect(machine.reduce(.reconnectFailed) == [.scheduleTimer(.reconnectRetry, seconds: 10)])
        #expect(machine.reduce(.timerFired(.reconnectRetry)) == [.connectBluetooth(uid: echoUID)])
        #expect(machine.reduce(.reconnectFailed).isEmpty)
        #expect(machine.reduce(.timerFired(.reconnectRetry)).isEmpty)
        #expect(machine.state == .waiting)
    }

    @Test("FR-12 §5 wake step 4: a target that came back during sleep is not reconnected")
    func targetBackBeforeUnlock() {
        var machine = Self.machine(in: .suspended, target: echo(), quietReconnect: true)
        _ = machine.reduce(.devicesChanged([]))
        _ = machine.reduce(.devicesChanged([echo()]))
        let effects = machine.reduce(.screenUnlocked)
        #expect(machine.state == .streaming)
        #expect(!effects.contains(.connectBluetooth(uid: echoUID)))
        #expect(effects.contains(.scheduleTimer(.volumeRestore, seconds: 3)))
    }

    @Test("FR-12: no reconnect when the setting is off")
    func reconnectDisabled() {
        var machine = Self.machine(in: .suspended, target: echo())
        var config = machine.config
        config.reconnectAfterUnlock = false
        _ = machine.reduce(.configChanged(config))
        _ = machine.reduce(.devicesChanged([]))
        #expect(machine.reduce(.screenUnlocked).isEmpty)
    }

    @Test("FR-5: no event sequence without sleep and unlock ever connects")
    func neverConnectsOtherwise() {
        var machine = Self.machine(in: .waiting, target: echo())
        let events: [KeepAliveEvent] = [
            .devicesChanged([echo()]), .engineStarted, .devicesChanged([]), .reconnectFailed,
            .timerFired(.reconnectRetry), .devicesChanged([echo(id: 5)]), .engineFailed("x"),
            .timerFired(.engineRetry), .systemDidWake, .screenUnlocked, .devicesChanged([]),
            .configChanged(Self.config(target: echoUID, keepAlive: false)),
            .configChanged(Self.config(target: echoUID)),
        ]
        for event in events {
            #expect(!machine.reduce(event).contains {
                if case .connectBluetooth = $0 {
                    true
                } else {
                    false
                }
            })
        }
    }

    // MARK: Engine errors

    @Test("A6: restarts after 1, 2, 5 s; the third failed restart enters Error and notifies; then 10, 30, 30 s")
    func engineRetrySchedule() {
        var machine = Self.machine(in: .streaming)
        var delays: [Double] = []
        var notified = 0
        for _ in 0 ..< 6 {
            let effects = machine.reduce(.engineFailed("boom"))
            for effect in effects {
                if case let .scheduleTimer(.engineRetry, seconds) = effect {
                    delays.append(seconds)
                }
                if case .notify(.engineError) = effect {
                    notified += 1
                }
            }
            if delays.count == 3 {
                #expect(machine.state == .streaming)
            }
            #expect(machine.reduce(.timerFired(.engineRetry)).contains(.startEngine(speaker(), .tone)))
        }
        #expect(delays == [1, 2, 5, 10, 30, 30])
        #expect(machine.state == .error)
        #expect(notified == 1)
    }

    @Test("FR-9: Error holds the assertion while the target is present and releases it when it goes")
    func errorAssertion() {
        var machine = Self.machine(in: .error)
        #expect(machine.assertionHeld)
        let effects = machine.reduce(.devicesChanged([]))
        #expect(machine.state == .waiting)
        #expect(effects.contains(.releaseAssertion))
    }

    @Test("A6: a successful restart from Error returns to Streaming")
    func errorRecovers() {
        var machine = Self.machine(in: .error)
        _ = machine.reduce(.timerFired(.engineRetry))
        _ = machine.reduce(.engineStarted)
        #expect(machine.state == .streaming)
        #expect(machine.engineFailures == 0)
    }

    @Test("A6: a device change in Error retries at once")
    func errorRetriesOnDeviceChange() {
        var machine = Self.machine(in: .error)
        let effects = machine.reduce(.devicesChanged([speaker(id: 77)]))
        #expect(effects.contains(.cancelTimer(.engineRetry)))
        #expect(effects.contains(.startEngine(speaker(id: 77), .tone)))
    }

    @Test("A6: a user action in Error retries at once")
    func errorRetriesOnUserAction() {
        var machine = Self.machine(in: .error)
        var config = machine.config
        config.signal = .silence
        let effects = machine.reduce(.configChanged(config))
        #expect(effects.contains(.startEngine(speaker(), .silence)))
    }

    @Test("A6: a stale retry timer does nothing once the engine runs again")
    func staleRetryIgnored() {
        var machine = Self.machine(in: .streaming)
        #expect(machine.reduce(.timerFired(.engineRetry)).isEmpty)
    }
}
