import Foundation
import IOKit.pwr_mgt
@testable import KeepAliveCore
import Testing

@MainActor
@Suite("PowerManager against IOKit")
struct PowerManagerIntegrationTests {
    /// Names of this process's assertions of the given type, as `pmset -g assertions` reports them.
    private func ownAssertionNames(type: String) -> [String] {
        ownAssertions().filter { $0.type == type }.map(\.name)
    }

    private func ownAssertions() -> [(type: String, name: String)] {
        var unmanaged: Unmanaged<CFDictionary>?
        guard IOPMCopyAssertionsByProcess(&unmanaged) == kIOReturnSuccess,
              let byProcess = unmanaged?.takeRetainedValue() as? [Int: [[String: Any]]]
        else { return [] }
        return (byProcess[Int(getpid())] ?? []).compactMap { assertion in
            guard let type = assertion[kIOPMAssertionTypeKey] as? String,
                  let name = assertion[kIOPMAssertionNameKey] as? String else { return nil }
            return (type, name)
        }
    }

    @Test("FR-9: holding creates a PreventUserIdleSystemSleep assertion and release removes it")
    func holdAndRelease() throws {
        let manager = IOPMPowerManager()
        let reason = "Purrlo test \(UUID().uuidString)"
        let idleType = kIOPMAssertionTypePreventUserIdleSystemSleep as String

        try manager.holdIdleSleepAssertion(reason: reason)
        #expect(manager.isHoldingIdleSleepAssertion)
        #expect(ownAssertionNames(type: idleType).contains(reason))

        manager.releaseIdleSleepAssertion()
        #expect(!manager.isHoldingIdleSleepAssertion)
        #expect(!ownAssertionNames(type: idleType).contains(reason))
    }

    @Test("FR-9: display sleep is never prevented")
    func displaySleepStaysAllowed() throws {
        let manager = IOPMPowerManager()
        let reason = "Purrlo display test \(UUID().uuidString)"
        try manager.holdIdleSleepAssertion(reason: reason)
        defer { manager.releaseIdleSleepAssertion() }
        let types = ownAssertions().filter { $0.name == reason }.map(\.type)
        #expect(types == [kIOPMAssertionTypePreventUserIdleSystemSleep as String])
    }

    @Test("FR-9: hold and release are idempotent")
    func idempotent() throws {
        let manager = IOPMPowerManager()
        let reason = "Purrlo idempotent \(UUID().uuidString)"
        let idleType = kIOPMAssertionTypePreventUserIdleSystemSleep as String
        try manager.holdIdleSleepAssertion(reason: reason)
        try manager.holdIdleSleepAssertion(reason: reason)
        #expect(ownAssertionNames(type: idleType).count(where: { $0 == reason }) == 1)
        manager.releaseIdleSleepAssertion()
        manager.releaseIdleSleepAssertion()
        #expect(!ownAssertionNames(type: idleType).contains(reason))
    }
}
