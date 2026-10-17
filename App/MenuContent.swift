import KeepAliveCore
import SwiftUI

/// Menu bar menu (PRD §4).
struct MenuContent: View {
    let appState: AppState
    let updates: Updates
    let showHelp: () -> Void
    let showAbout: () -> Void

    var body: some View {
        Text(appState.status.text)
            .accessibilityLabel("Status: \(appState.status.text)")

        Toggle("Keep alive", isOn: binding(\.config.keepAlive) { appState.setKeepAlive($0) })

        speakerMenu

        Picker("Signal", selection: binding(\.config.signal) { appState.setSignal($0) }) {
            Text("Inaudible tone").tag(SignalKind.tone)
            Text("Silence").tag(SignalKind.silence)
        }
        .pickerStyle(.menu)

        Menu("Sleep") {
            Toggle(
                "Prevent idle sleep",
                isOn: binding(\.config.preventIdleSleep) { appState.setPreventIdleSleep($0) }
            )
            Toggle(
                "Disconnect before sleep",
                isOn: binding(\.config.disconnectBeforeSleep) { appState.setDisconnectBeforeSleep($0) }
            )
            Toggle(
                "Reconnect after unlock",
                isOn: binding(\.config.reconnectAfterUnlock) { appState.setReconnectAfterUnlock($0) }
            )
            if let warning = appState.bluetoothMatchWarning {
                Text(LocalizedStringKey(warning))
            }
        }

        Divider()

        Button("Stay awake with lid closed — not in this version") {}
            .disabled(true)
        Button("Battery cut-off — not in this version") {}
            .disabled(true)
        Button("Sleep Now — not in this version") {}
            .disabled(true)

        Divider()

        Toggle(
            "Launch at Login",
            isOn: Binding(get: { appState.launchAtLogin }, set: { appState.setLaunchAtLogin($0) })
        )
        if let error = appState.lastError {
            Text(error)
        }

        Divider()

        Toggle(
            "Check automatically",
            isOn: Binding(get: { updates.automatic }, set: { updates.setAutomatic($0) })
        )
        Button("Check for Updates…") { updates.check() }
        if let error = updates.error {
            Text(error)
        }

        Divider()

        Button("Help", action: showHelp)
        Button("Copy Diagnostics") { DiagnosticsCopy.copy(appState) }
        Button("About", action: showAbout)
        Button("Quit") {
            appState.stop()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// FR-1: Bluetooth first, then the rest after a separator; ✓ on the target.
    private var speakerMenu: some View {
        let sections = DeviceOrdering.sections(appState.devices)
        let selected = appState.machine.config.targetUID
        return Menu("Speaker") {
            if sections.bluetooth.isEmpty, sections.other.isEmpty {
                Text("No output devices")
            }
            ForEach(sections.bluetooth, id: \.uid) { entry in
                speakerItem(entry, selected: selected)
            }
            if !sections.bluetooth.isEmpty, !sections.other.isEmpty {
                Divider()
            }
            ForEach(sections.other, id: \.uid) { entry in
                speakerItem(entry, selected: selected)
            }
        }
    }

    private func speakerItem(_ entry: DeviceMenuEntry, selected: String?) -> some View {
        Toggle(entry.title, isOn: Binding(
            get: { entry.uid == selected },
            set: {
                if $0 {
                    appState.selectTarget(uid: entry.uid)
                }
            }
        ))
        .accessibilityLabel(entry.uid == selected ? "\(entry.title), selected speaker" : entry.title)
    }

    /// Callers pass closures (`{ appState.setSignal($0) }`), not method references (`appState.setSignal`):
    /// converting a main-actor method reference here crashes Swift 6.3's IR generation.
    private func binding<Value>(
        _ keyPath: KeyPath<KeepAliveMachine, Value>,
        _ set: @escaping @MainActor (Value) -> Void
    ) -> Binding<Value> {
        Binding(get: { appState.machine[keyPath: keyPath] }, set: set)
    }
}
