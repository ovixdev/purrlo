@testable import KeepAliveCore
import Testing

@Suite("EC-9 session and §6 disconnect gate")
struct KeepAliveMachineSessionTests {
    @Test("§6: a unique paired name disconnects on sleep")
    func uniqueNameDisconnects() {
        var device = speaker(uid: "kitchen-speaker", name: "Kitchen", transport: .bluetooth)
        device.bluetoothControl = .byUniqueName
        var machine = KeepAliveMachineTests.machine(in: .streaming, target: device)
        let effects = KeepAliveMachineTests.actions(machine.reduce(.systemWillSleep))
        #expect(effects.contains(.disconnectBluetooth(uid: "kitchen-speaker")))
        #expect(machine.disconnectedByApp)
    }

    @Test("EC-18: an unmatched Bluetooth target is not disconnected")
    func unmatchedBluetoothStaysUp() {
        let device = speaker(uid: "BlackHole2ch_UID", name: "Echo", transport: .bluetooth)
        var machine = KeepAliveMachineTests.machine(in: .streaming, target: device)
        let effects = machine.reduce(.systemWillSleep)
        #expect(!effects.contains {
            if case .disconnectBluetooth = $0 { true } else { false }
        })
        #expect(!machine.disconnectedByApp)
    }

    @Test("FR-11: disconnect before sleep off leaves the link up")
    func disconnectBeforeSleepOff() {
        var machine = KeepAliveMachineTests.machine(in: .streaming, target: echo())
        var config = machine.config
        config.disconnectBeforeSleep = false
        _ = machine.reduce(.configChanged(config))
        let effects = machine.reduce(.systemWillSleep)
        #expect(!effects.contains {
            if case .disconnectBluetooth = $0 { true } else { false }
        })
        #expect(!machine.disconnectedByApp)
        #expect(machine.state == .suspended)
    }

    @Test("EC-9: session resign stops the engine and does not disconnect or leave Streaming")
    func sessionResignStopsEngine() {
        var machine = KeepAliveMachineTests.machine(in: .streaming, target: echo(), lid: true)
        let effects = machine.reduce(.sessionActiveChanged(false))
        #expect(machine.state == .streaming)
        #expect(effects.contains(.stopEngine))
        #expect(!effects.contains {
            if case .disconnectBluetooth = $0 { true } else { false }
        })
        #expect(machine.lidBlockSet)
    }

    @Test("EC-9: session active resumes the engine")
    func sessionActiveResumesEngine() {
        var machine = KeepAliveMachineTests.machine(in: .streaming, target: echo())
        _ = machine.reduce(.sessionActiveChanged(false))
        let effects = machine.reduce(.sessionActiveChanged(true))
        #expect(machine.state == .streaming)
        #expect(effects.contains(.startEngine(echo(), .tone)))
        #expect(machine.engineRunning)
    }

    @Test("EC-9: unlock forces the session active")
    func unlockForcesSessionActive() {
        var machine = KeepAliveMachineTests.machine(in: .streaming, target: echo())
        _ = machine.reduce(.sessionActiveChanged(false))
        #expect(!machine.engineRunning)
        let effects = machine.reduce(.screenUnlocked)
        #expect(machine.state == .streaming)
        #expect(effects.contains(.startEngine(echo(), .tone)))
    }

    @Test("EC-9: resign does not change disconnectedByApp, engineFailures, or the assertion")
    func resignLeavesBookkeeping() {
        var machine = KeepAliveMachineTests.machine(in: .streaming, target: echo())
        _ = machine.reduce(.engineFailed("boom"))
        let failures = machine.engineFailures
        let held = machine.assertionHeld
        let disconnected = machine.disconnectedByApp
        _ = machine.reduce(.sessionActiveChanged(false))
        #expect(machine.engineFailures == failures)
        #expect(machine.assertionHeld == held)
        #expect(machine.disconnectedByApp == disconnected)
        #expect(machine.state == .streaming)
    }

    @Test("EC-9: a resign while Suspended only stores the flag")
    func resignWhileSuspended() {
        var machine = KeepAliveMachineTests.machine(in: .suspended, target: echo())
        let effects = KeepAliveMachineTests.actions(machine.reduce(.sessionActiveChanged(false)))
        #expect(machine.state == .suspended)
        #expect(effects.isEmpty)
        #expect(machine.disconnectedByApp)
    }
}
