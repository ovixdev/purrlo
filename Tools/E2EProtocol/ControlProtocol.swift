#if E2E_HOOKS
    import Foundation

    /// Newline-delimited JSON spoken between the E2E app build and `kactl` (PRD §6, test hooks).
    enum ControlProtocol {
        static let socketName = "control.sock"

        /// `~/Library/Application Support/<bundle ID>/control.sock`.
        static func socketURL(bundleID: String) -> URL {
            FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
                .appendingPathComponent(bundleID, isDirectory: true)
                .appendingPathComponent(socketName)
        }
    }
#endif
