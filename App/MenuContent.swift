import KeepAliveCore
import SwiftUI

/// Minimal M1 menu (PRD §4 menu layout, items 1–4, 5 in part, 7 and Quit); M2 completes it.
struct MenuContent: View {
    let appState: AppState

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
            Toggle("Prevent idle sleep", isOn: binding(\.config.preventIdleSleep) { appState.setPreventIdleSleep($0) })
        }

        Divider()

        Toggle(
            "Launch at Login",
            isOn: Binding(get: { appState.launchAtLogin }, set: { appState.setLaunchAtLogin($0) })
        )
        if let error = appState.lastError {
            Text(error)
        }

        Divider()

        Button("Quit Purrlo") {
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
