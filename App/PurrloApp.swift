import AppKit
import KeepAliveCore
import SwiftUI

@main
struct PurrloApp: App {
    @State private var appState: AppState

    init() {
        let state = Composition.makeAppState()
        state.start()
        _appState = State(initialValue: state)
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { state.stop() }
        }
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(appState: appState)
        } label: {
            Image(systemName: appState.status.symbol)
                .accessibilityLabel(appState.status.text)
        }
        .menuBarExtraStyle(.menu)
    }
}
