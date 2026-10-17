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
        configureForTesting(&ports, arguments: arguments)
        let subsystem = Bundle.main.bundleIdentifier ?? KeepAliveCore.defaultSubsystem
        return AppState(settings: Settings(defaults: .standard), ports: ports, subsystem: subsystem)
    }

    /// E2E builds swap in recording fakes (PRD §6, test hooks); Release builds compile this to nothing.
    private static func configureForTesting(_: inout AppState.Ports, arguments _: [String]) {}
}
