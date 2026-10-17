import Foundation
import KeepAliveCore

/// Composition root: the only place that picks concrete implementations for AppState's ports.
@MainActor
enum Composition {
    static func makeAppState(arguments: [String] = CommandLine.arguments) -> AppState {
        let inactive = InactivePort()
        let subsystem = Bundle.main.bundleIdentifier ?? KeepAliveCore.defaultSubsystem
        let sleep = SleepCoordinator()
        var ports = AppState.Ports(
            deviceMonitor: CoreAudioDeviceMonitor(),
            engine: AUHALEngine(),
            power: IOPMPowerManager(),
            helper: inactive,
            bluetooth: inactive,
            volume: inactive,
            notifier: inactive,
            sleep: sleep,
            scheduler: TaskScheduler(),
            loginItem: MainAppLoginItem()
        )
        #if E2E_HOOKS
            // The E2E binary never constructs BluetoothController, so it never links a live IOBluetooth call.
            E2EHooks.configure(&ports, arguments: arguments)
        #else
            ports.bluetooth = BluetoothController(subsystem: subsystem)
        #endif
        let appState = AppState(settings: Settings(defaults: .standard), ports: ports, subsystem: subsystem)
        #if E2E_HOOKS
            E2EHooks.start(appState)
        #else
            sleep.install { [weak appState] event in
                appState?.send(event)
            }
        #endif
        return appState
    }
}
