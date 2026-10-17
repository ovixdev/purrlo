import Foundation
import KeepAliveCore

/// Composition root: the only place that picks concrete implementations for AppState's ports.
@MainActor
enum Composition {
    static func makeAppState(arguments: [String] = CommandLine.arguments) -> AppState {
        let inactive = InactivePort()
        var ports = AppState.Ports(
            deviceMonitor: CoreAudioDeviceMonitor(),
            engine: AUHALEngine(),
            power: IOPMPowerManager(),
            helper: inactive,
            bluetooth: inactive,
            volume: inactive,
            notifier: inactive,
            sleep: inactive,
            scheduler: TaskScheduler(),
            loginItem: MainAppLoginItem()
        )
        #if E2E_HOOKS
            E2EHooks.configure(&ports, arguments: arguments)
        #endif
        let subsystem = Bundle.main.bundleIdentifier ?? KeepAliveCore.defaultSubsystem
        let appState = AppState(settings: Settings(defaults: .standard), ports: ports, subsystem: subsystem)
        #if E2E_HOOKS
            E2EHooks.start(appState)
        #endif
        return appState
    }
}
