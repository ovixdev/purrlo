import Foundation
@testable import KeepAliveCore
import Testing

/// A throwaway `UserDefaults` domain, removed when the value goes away.
@MainActor
private final class ScratchDefaults {
    let name = "test-\(UUID())"
    let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: name))
    }

    /// A fresh `Settings` over the same persistent domain, as after a relaunch.
    func settings() -> Settings {
        Settings(defaults: defaults)
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: name)
    }
}

@MainActor
@Suite("Settings")
struct SettingsTests {
    @Test("FR-2: the target is persisted by UID with its display name, and survives a new instance")
    func targetPersists() throws {
        let suite = try ScratchDefaults()
        defer { suite.cleanUp() }
        let settings = suite.settings()
        #expect(settings.targetUID == nil)
        #expect(settings.targetDisplayName == nil)

        settings.setTarget(uid: "E8-4C-4A-8A-9A-39:output", name: "Echo Dot")

        let reread = suite.settings()
        #expect(reread.targetUID == "E8-4C-4A-8A-9A-39:output")
        #expect(reread.targetDisplayName == "Echo Dot")
        #expect(suite.defaults.string(forKey: "targetUID") == "E8-4C-4A-8A-9A-39:output")
        #expect(suite.defaults.string(forKey: "targetDisplayName") == "Echo Dot")
    }

    @Test("FR-2: setting a new target replaces both UID and name")
    func targetReplaced() throws {
        let suite = try ScratchDefaults()
        defer { suite.cleanUp() }
        let settings = suite.settings()
        settings.setTarget(uid: "old", name: "Old")
        settings.setTarget(uid: "new", name: "New")
        #expect(suite.settings().targetUID == "new")
        #expect(suite.settings().targetDisplayName == "New")
    }

    @Test("FR-2: clearTarget removes the UID and the name")
    func clearTarget() throws {
        let suite = try ScratchDefaults()
        defer { suite.cleanUp() }
        let settings = suite.settings()
        settings.setTarget(uid: "uid", name: "Speaker")
        settings.clearTarget()
        #expect(settings.targetUID == nil)
        #expect(settings.targetDisplayName == nil)
        #expect(suite.settings().targetUID == nil)
    }

    @Test("EC-3: noteTargetName updates the display name but never the UID")
    func renameUpdatesNameOnly() throws {
        let suite = try ScratchDefaults()
        defer { suite.cleanUp() }
        let settings = suite.settings()
        settings.setTarget(uid: "uid", name: "Echo Dot")
        settings.noteTargetName("Kitchen Speaker")
        #expect(settings.targetUID == "uid")
        #expect(settings.targetDisplayName == "Kitchen Speaker")
        #expect(suite.settings().targetDisplayName == "Kitchen Speaker")
    }

    @Test("EC-3: noteTargetName is ignored when no target is set")
    func renameIgnoredWithoutTarget() throws {
        let suite = try ScratchDefaults()
        defer { suite.cleanUp() }
        let settings = suite.settings()
        settings.noteTargetName("Stray")
        #expect(settings.targetUID == nil)
        #expect(settings.targetDisplayName == nil)
    }

    @Test("FR-6: keepAlive defaults to true and a stored false survives a new instance")
    func keepAlive() throws {
        let suite = try ScratchDefaults()
        defer { suite.cleanUp() }
        #expect(suite.settings().keepAlive)
        let settings = suite.settings()
        settings.keepAlive = false
        #expect(!settings.keepAlive)
        #expect(!suite.settings().keepAlive)
        settings.keepAlive = true
        #expect(suite.settings().keepAlive)
    }

    @Test("FR-4: signal defaults to tone and persists each choice", arguments: SignalKind.allCases)
    func signalPersists(kind: SignalKind) throws {
        let suite = try ScratchDefaults()
        defer { suite.cleanUp() }
        #expect(suite.settings().signal == .tone)
        suite.settings().signal = kind
        #expect(suite.settings().signal == kind)
        #expect(suite.defaults.string(forKey: "signal") == kind.rawValue)
    }

    @Test("FR-4: an unknown stored signal falls back to tone", arguments: ["", "noise", "TONE", "42"])
    func signalGarbage(stored: String) throws {
        let suite = try ScratchDefaults()
        defer { suite.cleanUp() }
        suite.defaults.set(stored, forKey: "signal")
        #expect(suite.settings().signal == .tone)
    }

    @Test("FR-4: a stored value of the wrong type falls back to tone")
    func signalWrongType() throws {
        let suite = try ScratchDefaults()
        defer { suite.cleanUp() }
        suite.defaults.set(7, forKey: "signal")
        #expect(suite.settings().signal == .tone)
    }

    @Test("FR-9: preventIdleSleep defaults to true and persists")
    func preventIdleSleep() throws {
        let suite = try ScratchDefaults()
        defer { suite.cleanUp() }
        #expect(suite.settings().preventIdleSleep)
        suite.settings().preventIdleSleep = false
        #expect(!suite.settings().preventIdleSleep)
        suite.settings().preventIdleSleep = true
        #expect(suite.settings().preventIdleSleep)
    }

    @Test("FR-6/FR-9: the toggles are independent")
    func togglesIndependent() throws {
        let suite = try ScratchDefaults()
        defer { suite.cleanUp() }
        let settings = suite.settings()
        settings.keepAlive = false
        #expect(settings.preventIdleSleep)
        settings.preventIdleSleep = false
        settings.keepAlive = true
        #expect(!settings.preventIdleSleep)
    }
}
