import Foundation
import Observation
#if !E2E_HOOKS
    import Sparkle
#endif

/// Sparkle (FR-16). Stays idle until `SUPublicEDKey` is in the app's Info.plist.
@MainActor
@Observable
final class Updates {
    private(set) var automatic = false
    private(set) var error: String?
    #if !E2E_HOOKS
        private let controller: SPUStandardUpdaterController?
    #endif

    init() {
        #if E2E_HOOKS
            automatic = false
        #else
            if Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") is String {
                let controller = SPUStandardUpdaterController(
                    startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil
                )
                self.controller = controller
                automatic = controller.updater.automaticallyChecksForUpdates
            } else {
                controller = nil
            }
        #endif
    }

    func setAutomatic(_ enabled: Bool) {
        #if !E2E_HOOKS
            controller?.updater.automaticallyChecksForUpdates = enabled
            automatic = controller?.updater.automaticallyChecksForUpdates ?? false
        #else
            automatic = enabled
        #endif
    }

    func check() {
        #if E2E_HOOKS
            error = "Updates aren't set up yet"
        #else
            guard let controller else {
                error = "Updates aren't set up yet"
                return
            }
            error = nil
            controller.checkForUpdates(nil)
        #endif
    }
}
