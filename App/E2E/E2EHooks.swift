#if E2E_HOOKS
    import AppKit
    import Foundation
    import KeepAliveCore

    /// Records every Bluetooth and helper call so E2E scripts can assert on them without hardware or root.
    @MainActor
    final class CallRecorder: HelperControlling, BluetoothControlling {
        private(set) var calls: [RecordedCall] = []
        /// `kactl set fake-connect fail|succeed` (E2E-10, M2).
        var connectSucceeds = true
        private let started = Date()

        func setSleepDisabled(_ disabled: Bool) {
            record("helper.setSleepDisabled(\(disabled))")
        }

        func disconnect(uid: String) {
            record("bluetooth.closeConnection(\(uid))")
        }

        func connect(uid: String) async -> Bool {
            record("bluetooth.openConnection(\(uid))")
            return connectSucceeds
        }

        private func record(_ call: String) {
            calls.append(RecordedCall(time: Date().timeIntervalSince(started), call: call))
        }
    }

    /// E2E builds never register a real login item (M1 plan, A2).
    @MainActor
    final class FakeLoginItem: LoginItemControlling {
        private(set) var isEnabled = false

        func setEnabled(_ enabled: Bool) throws {
            isEnabled = enabled
        }
    }

    @MainActor
    enum E2EHooks {
        private static var server: ControlServer?
        private static let recorder = CallRecorder()

        /// Swaps in recording fakes for `--fake-bluetooth` and `--fake-helper` (PRD §6).
        static func configure(_ ports: inout AppState.Ports, arguments: [String]) {
            if arguments.contains("--fake-helper") {
                ports.helper = recorder
            }
            if arguments.contains("--fake-bluetooth") {
                ports.bluetooth = recorder
            }
            ports.loginItem = FakeLoginItem()
        }

        static func start(_ appState: AppState) {
            let url = ControlProtocol.socketURL(bundleID: Bundle.main.bundleIdentifier ?? ControlProtocol.e2eBundleID)
            let server = ControlServer(url: url) { request in handle(request, appState) }
            do {
                try server.start()
                self.server = server
            } catch {
                fatalError("E2E control socket failed at \(url.path): \(error)")
            }
        }

        private static func handle(_ request: ControlRequest, _ appState: AppState) -> Data {
            do {
                return try response(for: request, appState)
            } catch {
                return encode(ControlError(error: String(describing: error)))
            }
        }

        private struct CommandError: Error, CustomStringConvertible {
            let description: String
        }

        private static func response(for request: ControlRequest, _ appState: AppState) throws -> Data {
            switch (request.cmd, request.args) {
            case ("status", []):
                return encode(ControlSuccess(result: status(appState)))
            case ("devices", []):
                return encode(ControlSuccess(result: appState.devices))
            case let ("set-target", args) where args.count == 1:
                appState.selectTarget(uid: args[0])
                return encode(ControlSuccess(result: status(appState)))
            case let ("set", args) where args.count == 2:
                try set(args[0], args[1], appState)
                return encode(ControlSuccess(result: status(appState)))
            case ("transitions", []):
                return encode(ControlSuccess(result: appState.log.entries))
            case ("calls", []):
                return encode(ControlSuccess(result: recorder.calls))
            case ("quit", []):
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    appState.stop()
                    NSApplication.shared.terminate(nil)
                }
                return encode(ControlSuccess(result: "quitting"))
            case ("simulate", _):
                throw CommandError(description: "simulate arrives with sleep handling (M2) and lid mode (M3)")
            default:
                throw CommandError(
                    description: "unknown command: \(request.cmd) \(request.args.joined(separator: " "))"
                )
            }
        }

        /// `kactl set <setting> <value>` (M1 plan, A14).
        private static func set(_ key: String, _ value: String, _ appState: AppState) throws {
            func bool() throws -> Bool {
                switch value {
                case "true", "on", "1": return true
                case "false", "off", "0": return false
                default: throw CommandError(description: "\(key) expects true or false, got \(value)")
                }
            }
            switch key {
            case "keepAlive": try appState.setKeepAlive(bool())
            case "preventIdleSleep": try appState.setPreventIdleSleep(bool())
            case "launchAtLogin": try appState.setLaunchAtLogin(bool())
            case "fake-connect": recorder.connectSucceeds = value == "succeed"
            case "signal":
                guard let signal = SignalKind(rawValue: value) else {
                    throw CommandError(description: "signal expects tone or silence, got \(value)")
                }
                appState.setSignal(signal)
            default:
                throw CommandError(description: "unknown setting: \(key)")
            }
        }

        private static func status(_ appState: AppState) -> StatusPayload {
            let machine = appState.machine
            let line = appState.status
            return StatusPayload(
                pid: ProcessInfo.processInfo.processIdentifier,
                state: machine.state.rawValue,
                text: line.text,
                symbol: line.symbol,
                sleepBlocked: line.sleepBlocked,
                targetUID: machine.config.targetUID,
                targetName: machine.target?.name,
                targetPresent: machine.target != nil,
                engineRunning: machine.engineRunning,
                assertionHeld: machine.assertionHeld,
                lidBlockSet: machine.lidBlockSet,
                keepAlive: machine.config.keepAlive,
                signal: machine.config.signal.rawValue,
                preventIdleSleep: machine.config.preventIdleSleep
            )
        }

        private static func encode(_ value: some Encodable) -> Data {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return (try? encoder.encode(value)) ?? Data(#"{"ok":false,"error":"encoding failed"}"#.utf8)
        }
    }
#endif
