import KeepAliveCore
import SwiftUI

@main
struct PurrloApp: App {
    var body: some Scene {
        MenuBarExtra("Purrlo", systemImage: "hifispeaker") {
            Button("Quit Purrlo") { NSApplication.shared.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
