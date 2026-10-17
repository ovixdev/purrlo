import AppKit
import Foundation
import KeepAliveCore

/// Copies a redacted diagnostics report. `log show` runs off the main actor (NFR-9).
enum DiagnosticsCopy {
    static func copy(_ appState: AppState) {
        let subsystem = Bundle.main.bundleIdentifier ?? KeepAliveCore.defaultSubsystem
        let machine = appState.machine
        let snapshot = Snapshot(
            marketingVersion: string("CFBundleShortVersionString"),
            build: string("CFBundleVersion"),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            state: machine.state.rawValue,
            keepAlive: machine.config.keepAlive,
            signal: machine.config.signal.rawValue,
            preventIdleSleep: machine.config.preventIdleSleep,
            disconnectBeforeSleep: machine.config.disconnectBeforeSleep,
            reconnectAfterUnlock: machine.config.reconnectAfterUnlock,
            targetName: machine.target?.name,
            targetUID: machine.config.targetUID,
            transitions: appState.log.entries,
            homeDirectory: NSHomeDirectory()
        )
        Task.detached {
            let extract = logExtract(subsystem)
            let report = DiagnosticsReport.make(
                marketingVersion: snapshot.marketingVersion,
                build: snapshot.build,
                osVersion: snapshot.osVersion,
                state: snapshot.state,
                keepAlive: snapshot.keepAlive,
                signal: snapshot.signal,
                preventIdleSleep: snapshot.preventIdleSleep,
                disconnectBeforeSleep: snapshot.disconnectBeforeSleep,
                reconnectAfterUnlock: snapshot.reconnectAfterUnlock,
                targetName: snapshot.targetName,
                targetUID: snapshot.targetUID,
                transitions: snapshot.transitions,
                logExtract: extract,
                homeDirectory: snapshot.homeDirectory
            )
            await MainActor.run {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(report, forType: .string)
            }
        }
    }

    private struct Snapshot: Sendable {
        var marketingVersion: String
        var build: String
        var osVersion: String
        var state: String
        var keepAlive: Bool
        var signal: String
        var preventIdleSleep: Bool
        var disconnectBeforeSleep: Bool
        var reconnectAfterUnlock: Bool
        var targetName: String?
        var targetUID: String?
        var transitions: [TransitionEntry]
        var homeDirectory: String
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
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(decoding: data, as: UTF8.self)
        } catch {
            return ""
        }
    }
}
