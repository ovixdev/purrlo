import Foundation
import IOKit.pwr_mgt

/// Holds the idle-sleep assertion while the target is connected (FR-9). Display sleep and screen lock stay allowed.
@MainActor
public protocol PowerManaging: AnyObject {
    var isHoldingIdleSleepAssertion: Bool { get }
    /// Idempotent: a second call while held keeps the existing assertion.
    func holdIdleSleepAssertion(reason: String) throws
    /// Idempotent.
    func releaseIdleSleepAssertion()
}

public struct PowerAssertionError: Error, Equatable {
    public let status: IOReturn
}

@MainActor
public final class IOPMPowerManager: PowerManaging {
    private var assertionID: IOPMAssertionID?

    public init() {}

    public var isHoldingIdleSleepAssertion: Bool {
        assertionID != nil
    }

    public func holdIdleSleepAssertion(reason: String) throws {
        guard assertionID == nil else { return }
        var id = IOPMAssertionID(0)
        let status = IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason as CFString,
            &id
        )
        guard status == kIOReturnSuccess else { throw PowerAssertionError(status: status) }
        assertionID = id
    }

    public func releaseIdleSleepAssertion() {
        guard let id = assertionID else { return }
        IOPMAssertionRelease(id)
        assertionID = nil
    }
}
