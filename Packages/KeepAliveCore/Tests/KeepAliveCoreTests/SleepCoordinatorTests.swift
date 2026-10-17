import Foundation
import IOKit.pwr_mgt
@testable import KeepAliveCore
import Testing

@MainActor
@Suite("SleepCoordinator")
struct SleepCoordinatorTests {
    private final class Box: @unchecked Sendable {
        private let lock = NSLock()
        private var tokens: [Int] = []
        private(set) var events: [KeepAliveEvent] = []

        func allow(_ token: Int) {
            lock.lock()
            tokens.append(token)
            lock.unlock()
        }

        func allowed() -> [Int] {
            lock.lock()
            defer { lock.unlock() }
            return tokens
        }

        func record(_ event: KeepAliveEvent) {
            events.append(event)
        }
    }

    private func make(
        locked: Bool = false, watchdog: TimeInterval = SleepCoordinator.watchdogSeconds, box: Box
    ) -> SleepCoordinator {
        let coordinator = SleepCoordinator(
            watchdogSeconds: watchdog, allow: { box.allow($0) }, screenLocked: { locked }
        )
        coordinator.bind { box.record($0) }
        return coordinator
    }

    @Test("FR-11: WillSleep sends systemWillSleep and allowSleep acknowledges that token once")
    func willSleepAcknowledgesOnce() {
        let box = Box()
        let coordinator = make(box: box)
        coordinator.receiveWillSleep(token: 4)
        #expect(box.events == [.systemWillSleep])
        coordinator.allowSleep()
        coordinator.allowSleep()
        #expect(box.allowed() == [4])
    }

    @Test("FR-11: allowSleep with no token is a no-op")
    func allowSleepWithoutToken() {
        let box = Box()
        let coordinator = make(box: box)
        coordinator.allowSleep()
        #expect(box.allowed().isEmpty)
        #expect(box.events.isEmpty)
    }

    @Test("FR-11: CanSystemSleep is allowed immediately and sends no event")
    func canSystemSleep() {
        let box = Box()
        let allowance = SleepAllowance(deadline: 5) { box.allow($0) }
        var notes: [SleepNote] = []
        routeSystemPowerMessage(
            UInt32(kIOMessageCanSystemSleep), token: 3, allowance: allowance
        ) { notes.append($0) }
        #expect(box.allowed() == [3])
        #expect(notes.isEmpty)
    }

    @Test("FR-11: a stalled main actor still allows sleep within 5 s")
    func stalledMainAllowsSleep() {
        let box = Box()
        let coordinator = make(watchdog: 0.2, box: box)
        coordinator.receiveWillSleepDeferred(token: 11)
        Thread.sleep(forTimeInterval: 0.7)
        #expect(box.allowed() == [11])
        #expect(box.events.isEmpty)
    }

    @Test("FR-12: poweredOn does not send systemDidWake or screenUnlocked")
    func poweredOnIsIgnored() {
        let box = Box()
        let allowance = SleepAllowance(deadline: 5) { box.allow($0) }
        var notes: [SleepNote] = []
        routeSystemPowerMessage(
            UInt32(kIOMessageSystemHasPoweredOn), token: 1, allowance: allowance
        ) { notes.append($0) }
        routeSystemPowerMessage(
            UInt32(kIOMessageSystemWillPowerOn), token: 2, allowance: allowance
        ) { notes.append($0) }
        let coordinator = make(box: box)
        coordinator.receivePoweredOn()
        #expect(notes.isEmpty)
        #expect(box.events.isEmpty)
        #expect(box.allowed().isEmpty)
    }

    @Test("FR-12: didWake with the lock key set waits; screenIsUnlocked then sends screenUnlocked")
    func didWakeWaitsWhileLocked() {
        let box = Box()
        let coordinator = make(locked: true, box: box)
        coordinator.receiveDidWake()
        coordinator.receiveScreenLocked()
        #expect(box.events == [.systemDidWake])
        coordinator.receiveScreenUnlocked()
        #expect(box.events == [.systemDidWake, .screenUnlocked])
        coordinator.receiveScreenUnlocked()
        #expect(box.events == [.systemDidWake, .screenUnlocked])
    }

    @Test("FR-12: didWake with the lock key absent sends systemDidWake then screenUnlocked")
    func didWakeUnlockedImmediately() {
        let box = Box()
        let coordinator = make(locked: false, box: box)
        coordinator.receiveDidWake()
        #expect(box.events == [.systemDidWake, .screenUnlocked])
    }

    @Test("EC-8: display sleep, screen saver and screen lock send no event")
    func displaySleepIsIgnored() {
        let box = Box()
        let coordinator = make(box: box)
        coordinator.receiveDisplaySleep()
        coordinator.receiveScreenSaver()
        coordinator.receiveScreenLocked()
        #expect(box.events.isEmpty)
    }

    @Test("EC-9: session resign and become-active are forwarded and are not unlocks")
    func sessionIsNotUnlock() {
        let box = Box()
        let coordinator = make(box: box)
        coordinator.receiveSessionResign()
        coordinator.receiveSessionActive()
        #expect(box.events == [.sessionActiveChanged(false), .sessionActiveChanged(true)])
    }

    @Test("M2-A3: WillNotSleep after WillSleep unlocks; after only CanSystemSleep it does not")
    func willNotSleep() {
        let box = Box()
        let coordinator = make(box: box)
        coordinator.receiveCanSystemSleep(token: 2)
        coordinator.receiveWillNotSleep()
        #expect(box.events.isEmpty)
        #expect(box.allowed() == [2])

        coordinator.receiveWillSleep(token: 9)
        coordinator.allowSleep()
        coordinator.receiveWillNotSleep()
        #expect(box.events == [.systemWillSleep, .screenUnlocked])
        #expect(box.allowed() == [2, 9])
    }
}
