import Foundation
@testable import KeepAliveCore
import Testing

@MainActor
@Suite("AppState wiring")
final class AppStateTests {
    let suite = "test-appstate-\(UUID().uuidString)"
    let log = CallLog()
    let monitor: FakeDeviceMonitor
    let engine: RecordingEngine
    let power: FakePower
    let recording: RecordingPorts
    let scheduler = ManualScheduler()
    let loginItem = FakeLoginItem()

    init() {
        monitor = FakeDeviceMonitor()
        engine = RecordingEngine(log: log)
        power = FakePower(log: log)
        recording = RecordingPorts(log: log)
    }

    deinit {
        UserDefaults().removePersistentDomain(forName: suite)
    }

    private func makeSettings() throws -> Settings {
        try Settings(defaults: #require(UserDefaults(suiteName: suite)))
    }

    private func makeState(_ settings: Settings? = nil) throws -> AppState {
        let ports = AppState.Ports(
            deviceMonitor: monitor, engine: engine, power: power, helper: recording,
            bluetooth: recording, volume: recording, notifier: recording, sleep: recording,
            scheduler: scheduler, loginItem: loginItem
        )
        return try AppState(settings: settings ?? makeSettings(), ports: ports)
    }

    @Test("EC-1, FR-8: launch with no target → Waiting, 'Choose a speaker', sleep allowed")
    func launchWithoutTarget() throws {
        let state = try makeState()
        state.start()
        #expect(state.state == .waiting)
        #expect(state.status.text == "Choose a speaker · Sleep allowed: no speaker connected")
        #expect(state.status.symbol == "hifispeaker")
        #expect(!state.status.sleepBlocked)
        #expect(log.calls.isEmpty)
    }

    @Test("FR-1, FR-2, FR-3, FR-9: selecting a present device streams to it and blocks idle sleep")
    func selectTargetStreams() throws {
        monitor.publish([speaker(), echo()])
        let state = try makeState()
        state.start()
        state.selectTarget(uid: echoUID)
        #expect(state.state == .streaming)
        #expect(log.calls == ["engine.start(\(echoUID)@44100,tone)", "power.hold"])
        #expect(state.status.text == "Streaming to Echo Dot · Sleep blocked while Echo Dot is connected")
        #expect(state.status.symbol == "hifispeaker.fill")
        #expect(state.status.sleepBlocked)
    }

    @Test("FR-2, FR-6, FR-4: settings survive a relaunch and the target is found again by UID")
    func persistsAcrossLaunches() throws {
        monitor.publish([echo()])
        let first = try makeState()
        first.start()
        first.selectTarget(uid: echoUID)
        first.setSignal(.silence)
        first.stop()

        monitor.publish([echo(id: 555)])
        log.calls.removeAll()
        let second = try makeState()
        second.start()
        #expect(second.state == .streaming)
        #expect(log.calls.first == "engine.start(\(echoUID)@44100,silence)")
        #expect(engine.startedWith.last?.0.objectID == 555)
    }

    @Test("FR-6: Keep alive off survives a relaunch")
    func keepAliveOffPersists() throws {
        let first = try makeState()
        first.start()
        first.setKeepAlive(false)
        #expect(first.state == .off)
        #expect(first.status.text == "Off · Sleep allowed: Keep alive is off")

        let second = try makeState()
        second.start()
        #expect(second.state == .off)
    }

    @Test("FR-8: Waiting for a known target shows its last-seen name")
    func waitingShowsLastName() throws {
        monitor.publish([echo()])
        let state = try makeState()
        state.start()
        state.selectTarget(uid: echoUID)
        monitor.publish([])
        #expect(state.state == .waiting)
        #expect(state.status.text == "Waiting for Echo Dot · Sleep allowed: no speaker connected")
    }

    @Test("FR-8, FR-9: with Prevent idle sleep off the status says why sleep is allowed")
    func statusExplainsAllowedSleep() throws {
        monitor.publish([echo()])
        let state = try makeState()
        state.start()
        state.selectTarget(uid: echoUID)
        state.setPreventIdleSleep(false)
        #expect(state.state == .streaming)
        #expect(log.calls.last == "power.release")
        #expect(state.status.text == "Streaming to Echo Dot · Sleep allowed: Prevent idle sleep is off")
    }

    @Test("EC-3: a renamed target keeps streaming and its new name is remembered")
    func renameRemembered() throws {
        monitor.publish([echo()])
        let settings = try makeSettings()
        let state = try makeState(settings)
        state.start()
        state.selectTarget(uid: echoUID)
        var renamed = echo()
        renamed.name = "Kitchen"
        monitor.publish([renamed])
        #expect(settings.targetDisplayName == "Kitchen")
        #expect(settings.targetUID == echoUID)
        #expect(state.status.text.hasPrefix("Streaming to Kitchen"))
    }

    @Test("A6, FR-8: engine failures go through the retry timer and end in Error")
    func engineFailuresReachError() throws {
        monitor.publish([echo()])
        engine.failuresLeft = 10
        let state = try makeState()
        state.start()
        state.selectTarget(uid: echoUID)
        #expect(scheduler.pending[.engineRetry]?.seconds == 1)
        scheduler.fire(.engineRetry)
        scheduler.fire(.engineRetry)
        scheduler.fire(.engineRetry)
        #expect(state.state == .error)
        #expect(recording.notifications == [.engineError])
        #expect(state.status.text == "Can't stream to Echo Dot · Sleep blocked while Echo Dot is connected")
        #expect(scheduler.pending[.engineRetry]?.seconds == 10)

        engine.failuresLeft = 0
        scheduler.fire(.engineRetry)
        #expect(state.state == .streaming)
    }

    @Test("FR-9: a failing power assertion is logged and does not stop streaming")
    func assertionFailureTolerated() throws {
        monitor.publish([echo()])
        power.failHold = true
        let state = try makeState()
        state.start()
        state.selectTarget(uid: echoUID)
        #expect(state.state == .streaming)
        #expect(engine.isRunning)
    }

    @Test("E2E-6, A13: the transition log records every event, restarts included")
    func transitionLog() throws {
        monitor.publish([echo()])
        let state = try makeState()
        state.start()
        state.selectTarget(uid: echoUID)
        monitor.publish([echo(rate: 48000)])
        let entries = state.log.entries
        #expect(entries.first?.event == "launch")
        #expect(entries.map(\.seq) == Array(1 ... entries.count))
        #expect(entries.contains { $0.from == .waiting && $0.to == .streaming })
        let restarts = entries.flatMap(\.effects).filter { $0.hasPrefix("restartEngine") }
        #expect(restarts == ["restartEngine(bt…9A-39@48000, tone)"])
        // NFR-9: the speaker's Bluetooth address never reaches the log.
        #expect(!entries.flatMap(\.effects).joined().contains("E8-4C-4A-8A"))
        #expect(!entries.map(\.event).joined().contains("E8-4C-4A-8A"))
        #expect(zip(entries, entries.dropFirst()).allSatisfy { $0.time <= $1.time })
    }

    @Test("A4, E2E-4: losing the target clears the lid block through the helper")
    func lidClearedThroughHelper() throws {
        monitor.publish([echo()])
        let state = try makeState()
        state.start()
        state.selectTarget(uid: echoUID)
        log.calls.removeAll()
        monitor.publish([])
        #expect(log.calls == ["engine.stop", "helper.setSleepDisabled(false)", "power.release"])
    }

    @Test("FR-6: stop() on quit releases the stream and the assertion")
    func stopReleasesEverything() throws {
        monitor.publish([echo()])
        let state = try makeState()
        state.start()
        state.selectTarget(uid: echoUID)
        state.stop()
        #expect(!engine.isRunning)
        #expect(!power.isHoldingIdleSleepAssertion)
        #expect(monitor.stopped)
    }

    @Test("FR-7: Launch at Login toggles the login item and reflects its state")
    func launchAtLogin() throws {
        let state = try makeState()
        #expect(!state.launchAtLogin)
        state.setLaunchAtLogin(true)
        #expect(state.launchAtLogin)
        #expect(loginItem.calls == [true])
        state.setLaunchAtLogin(false)
        #expect(!state.launchAtLogin)
    }

    @Test("FR-7: a failing login-item change is surfaced, not swallowed")
    func launchAtLoginFailure() throws {
        let state = try makeState()
        loginItem.failNext = true
        state.setLaunchAtLogin(true)
        #expect(!state.launchAtLogin)
        #expect(state.lastError?.hasPrefix("Launch at Login") == true)
    }

    @Test("FR-5, FR-12: the reconnect runs through the Bluetooth port and a failure schedules one retry")
    func reconnectThroughPort() async throws {
        monitor.publish([echo()])
        let state = try makeState()
        state.start()
        state.selectTarget(uid: echoUID)
        state.send(.systemWillSleep)
        // E2E-7 order: stop, close the connection, clear the flag, release, allow sleep; FR-13 is dropped.
        #expect(Array(log.calls.suffix(5)) == [
            "engine.stop", "bt.closeConnection(\(echoUID))",
            "helper.setSleepDisabled(false)", "power.release", "allowSleep",
        ])
        #expect(!log.calls.contains { $0.hasPrefix("volume.") })
        monitor.publish([])
        state.send(.systemDidWake)
        state.send(.screenUnlocked)
        let retried = await waitFor { self.scheduler.pending[.reconnectRetry] != nil }
        #expect(retried)
        #expect(log.calls.count { $0.hasPrefix("bt.openConnection") } == 1)
    }

    @Test("EC-12: a volume left at 0 by a previous run is restored as soon as the target appears")
    func pendingVolumeAtLaunch() throws {
        recording.hasPendingRestore = true
        let settings = try makeSettings()
        settings.setTarget(uid: echoUID, name: "Echo Dot")
        let state = try makeState(settings)
        state.start()
        monitor.publish([echo()])
        #expect(scheduler.pending[.volumeRestore]?.seconds == 3)
        scheduler.fire(.volumeRestore)
        #expect(log.calls.last == "volume.restore(\(echoUID))")
    }

    @Test("TaskScheduler fires once, replaces and cancels timers")
    func taskScheduler() async {
        let scheduler = TaskScheduler()
        var fired: [String] = []
        scheduler.schedule(.engineRetry, after: 0.01) { fired.append("first") }
        scheduler.schedule(.engineRetry, after: 0.02) { fired.append("second") }
        scheduler.schedule(.volumeRestore, after: 0.02) { fired.append("cancelled") }
        scheduler.cancel(.volumeRestore)
        _ = await waitFor { !fired.isEmpty }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(fired == ["second"])
    }

    @Test("FR-11, FR-12: disconnect and reconnect settings survive a relaunch")
    func sleepSettingsPersist() throws {
        let first = try makeState()
        first.start()
        first.setDisconnectBeforeSleep(false)
        first.setReconnectAfterUnlock(false)
        let second = try makeState()
        second.start()
        #expect(!second.machine.config.disconnectBeforeSleep)
        #expect(!second.machine.config.reconnectAfterUnlock)
    }

    @Test("FR-18: first run stays incomplete until marked done")
    func firstRunStaysUntilDone() throws {
        let state = try makeState()
        #expect(state.needsFirstRun)
        state.completeFirstRun()
        #expect(!state.needsFirstRun)
        let relaunch = try makeState()
        #expect(!relaunch.needsFirstRun)
    }

    @Test("EC-18: an unmatched Bluetooth target produces the menu warning")
    func unmatchedBluetoothWarning() throws {
        let device = speaker(uid: "kitchen", name: "Kitchen", transport: .bluetooth)
        monitor.publish([device])
        let state = try makeState()
        state.start()
        state.selectTarget(uid: "kitchen")
        #expect(state.bluetoothMatchWarning?.contains("won't disconnect") == true)
        state.selectTarget(uid: echoUID)
        monitor.publish([device, echo()])
        #expect(state.bluetoothMatchWarning == nil)
    }

    @Test("InactivePort does nothing and never connects (FR-5 in M1 builds)")
    func inactivePort() async {
        let port = InactivePort()
        port.setSleepDisabled(true)
        port.disconnect(uid: echoUID)
        port.saveAndZero(uid: echoUID)
        port.restore(uid: echoUID)
        port.post(.engineError)
        port.allowSleep()
        #expect(!port.hasPendingRestore)
        #expect(await !port.connect(uid: echoUID))
    }

    private func waitFor(_ condition: () -> Bool) async -> Bool {
        for _ in 0 ..< 200 {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }
}

@Test("NFR-9: log UIDs keep virtual UIDs readable and mask Bluetooth addresses")
func logUIDMasking() {
    #expect(logUID("e2e-speaker") == "e2e-speaker")
    #expect(logUID("E8-4C-4A-8A-9A-39:output") == "bt…9A-39")
    #expect(logUID("E8-4C-4A-8A-9A-39") == "bt…9A-39")
}
