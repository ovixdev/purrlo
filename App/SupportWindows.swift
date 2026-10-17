import AppKit
import KeepAliveCore
import SwiftUI

/// AppKit windows. A SwiftUI `Window` scene does not come forward reliably under `MenuBarExtra`.
@MainActor
final class SupportWindows {
    private var firstRun: NSWindow?
    private var help: NSWindow?
    private var about: NSWindow?

    func showFirstRunIfNeeded(_ appState: AppState) {
        guard appState.needsFirstRun, firstRun == nil else { return }
        let window = makeWindow(title: "Purrlo", size: NSSize(width: 440, height: 460))
        window.contentViewController = NSHostingController(rootView: FirstRunView(appState: appState) { [weak window] in
            appState.completeFirstRun()
            window?.close()
        })
        firstRun = window
        present(window)
    }

    func showHelp() {
        help = show(help, title: "Help", size: NSSize(width: 460, height: 360), view: HelpView())
    }

    func showAbout() {
        about = show(about, title: "About Purrlo", size: NSSize(width: 360, height: 180), view: AboutView())
    }

    private func show(_ existing: NSWindow?, title: String, size: NSSize, view: some View) -> NSWindow {
        if let existing {
            present(existing)
            return existing
        }
        let window = makeWindow(title: title, size: size)
        window.contentViewController = NSHostingController(rootView: view)
        present(window)
        return window
    }

    private func makeWindow(title: String, size: NSSize) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = title
        window.isReleasedWhenClosed = false
        return window
    }

    private func present(_ window: NSWindow) {
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}

private struct FirstRunView: View {
    let appState: AppState
    let start: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Keep a speaker connected")
                .font(.title2)
            Text(
                "Purrlo keeps one Bluetooth speaker connected by playing a sound you can't hear. "
                    + "The Mac stops dropping the link, so the speaker stops announcing itself."
            )
            speakerPicker
            Toggle(
                "Launch at Login",
                isOn: Binding(get: { appState.launchAtLogin }, set: { appState.setLaunchAtLogin($0) })
            )
            Text(
                "While the speaker is connected, the Mac will not idle-sleep, on battery or on power. "
                    + "That uses more battery. Staying awake with the lid closed uses more still, "
                    + "and the Mac can get warm. That option is off."
            )
            .font(.callout)
            HStack {
                Spacer()
                Button("Start", action: start)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private var speakerPicker: some View {
        let sections = DeviceOrdering.sections(appState.devices)
        let selected = appState.machine.config.targetUID
        return Picker("Speaker", selection: Binding(
            get: { selected ?? "" },
            set: { appState.selectTarget(uid: $0) }
        )) {
            Text("Choose a speaker").tag("")
            ForEach(sections.bluetooth + sections.other, id: \.uid) { entry in
                Text(entry.title).tag(entry.uid)
            }
        }
    }
}

private struct HelpView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(
                "While your speaker is connected and Prevent idle sleep is on, the Mac will not idle-sleep. "
                    + "The display can still sleep, and the screen can still lock. Those do not drop the link. "
                    + "If the Mac does sleep, Purrlo disconnects the speaker first and reconnects it "
                    + "once after you unlock."
            )
            Text(
                "Staying awake with the lid closed is not in this version. When it is, use Sleep Now in this menu. "
                    + "The Apple menu will not sleep the Mac while that mode is on."
            )
            Text(
                "Echo (4th generation), Echo Studio and Echo Plus (2nd generation) have a headphone jack. "
                    + "A cable avoids Bluetooth, and the announcement, entirely."
            )
            if let faq = URL(string: "https://ovixdev.github.io/purrlo/faq") {
                Link("FAQ", destination: faq)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 460, alignment: .leading)
    }
}

private struct AboutView: View {
    var body: some View {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        return VStack(alignment: .leading, spacing: 8) {
            Text("Purrlo \(version) (\(build))")
            Text("MIT License")
            if let project = URL(string: "https://github.com/ovixdev/purrlo") {
                Link("https://github.com/ovixdev/purrlo", destination: project)
            }
            Spacer(minLength: 0)
        }
        .padding(20)
        .frame(width: 360, alignment: .leading)
    }
}
