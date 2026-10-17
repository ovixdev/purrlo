import AppKit
import Foundation
import KeepAliveCore

/// Copies a redacted diagnostics report. `log show` runs off the main actor (NFR-9).
enum DiagnosticsCopy {
    @MainActor
    static func copy(_ appState: AppState) {
        let subsystem = Bundle.main.bundleIdentifier ?? KeepAliveCore.defaultSubsystem
        let machine = appState.machine
        let report = DiagnosticsReport(
            version: DiagnosticsReport.Version(
                marketing: string("CFBundleShortVersionString"),
                build: string("CFBundleVersion"),
                system: ProcessInfo.processInfo.operatingSystemVersionString
            ),
            state: machine.state.rawValue,
            config: machine.config,
            targetName: machine.target?.name,
            transitions: appState.log.entries
        )
        let homeDirectory = NSHomeDirectory()
        Task.detached {
            let text = report.text(logExtract: logExtract(subsystem), homeDirectory: homeDirectory)
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }

    private static func string(_ key: String) -> String {
        Bundle.main.object(forInfoDictionaryKey: key) as? String ?? ""
    }

    private static func logExtract(_ subsystem: String) -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/log")
        process.arguments = [
            "show", "--last", "30m", "--style", "compact", "--predicate",
            "subsystem == \"\(subsystem)\"",
        ]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            return String(bytes: data, encoding: .utf8) ?? ""
        } catch {
            return ""
        }
    }
}
