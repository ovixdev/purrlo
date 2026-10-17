#if E2E_HOOKS
    import Foundation

    /// Newline-delimited JSON spoken between the E2E app build and `kactl` (PRD §6, test hooks).
    /// One request per connection: `{"cmd": "...", "args": [...]}` → `{"ok": true, "result": ...}`.
    enum ControlProtocol {
        static let socketName = "control.sock"
        static let e2eBundleID = "io.github.ovixdev.purrlo.e2e"

        /// `~/Library/Application Support/<bundle ID>/control.sock`.
        static func socketURL(bundleID: String = e2eBundleID) -> URL {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent(bundleID, isDirectory: true)
                .appendingPathComponent(socketName)
        }
    }

    struct ControlRequest: Codable, Sendable {
        var cmd: String
        var args: [String] = []
    }

    struct ControlError: Encodable {
        let ok = false
        let error: String
    }

    struct ControlSuccess<Result: Encodable>: Encodable {
        let ok = true
        let result: Result
    }

    /// `kactl status`.
    struct StatusPayload: Codable, Sendable {
        let pid: Int32
        let state: String
        let text: String
        let symbol: String
        let sleepBlocked: Bool
        let targetUID: String?
        let targetName: String?
        let targetPresent: Bool
        let engineRunning: Bool
        let assertionHeld: Bool
        let lidBlockSet: Bool
        let keepAlive: Bool
        let signal: String
        let preventIdleSleep: Bool
    }

    /// One call recorded by a `--fake-*` port (`kactl calls`).
    struct RecordedCall: Codable, Sendable {
        let time: Double
        let call: String
    }
#endif
