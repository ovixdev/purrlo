import AppKit
import KeepAliveCore
import SwiftUI

@main
struct PurrloApp: App {
    @State private var appState: AppState
    private let updates = Updates()
    private let windows = SupportWindows()

    init() {
        let state = Composition.makeAppState()
        state.start()
        _appState = State(initialValue: state)
        let windows = windows
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { state.stop() }
        }
        #if !E2E_HOOKS
            DispatchQueue.main.async {
                MainActor.assumeIsolated { windows.showFirstRunIfNeeded(state) }
            }
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(
                appState: appState,
                updates: updates,
                showHelp: { windows.showHelp() },
                showAbout: { windows.showAbout() }
            )
        } label: {
            Image(systemName: appState.status.symbol)
                .accessibilityLabel(appState.status.text)
        }
        .menuBarExtraStyle(.menu)
    }
}
