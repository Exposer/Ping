import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    // Single-window utility: closing the window quits instead of leaving an empty app in the Dock.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct PingApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        // Needed when launched as a bare executable (`swift run`) rather than from a .app bundle.
        NSApplication.shared.setActivationPolicy(.regular)
        DispatchQueue.main.async {
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    var body: some Scene {
        WindowGroup("Ping") {
            ContentView()
        }
    }
}
