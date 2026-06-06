import SwiftUI

@main
struct screen_shootApp: App {

    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
        } label: {
            Image(systemName: "camera.viewfinder")
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView()
        }
    }
}

struct MenuContent: View {

    var body: some View {
        Button("About ScreenShoot") {
            NSApp.activate(ignoringOtherApps: true)
            NSApp.orderFrontStandardAboutPanel(options: [
                NSApplication.AboutPanelOptionKey.applicationName: "ScreenShoot",
                NSApplication.AboutPanelOptionKey.applicationVersion: "1.0.0"
            ])
        }

        Divider()

        Button("Take Screenshot (Full)") {
            ScreenshotManager.shared.captureFullscreenFromMenu()
        }

        Button("Take Screenshot (Area)...") {
            ScreenshotManager.shared.captureAreaFromMenu()
        }

        Divider()

        SettingsLink()

        Divider()

        Button("Accessibility Settings...") {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }

        Divider()

        Button("Quit ScreenShoot") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {

    private var settingsWindowObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !HotkeyInterceptor.checkAccessibilityPermission() {
            showAccessibilityPrompt()
        }

        ScreenshotManager.shared.start()

        // Use a block-based observer that automatically removes itself on deallocation
        settingsWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification,
            object: nil,
            queue: .main
        ) { notification in
            guard let window = notification.object as? NSWindow else { return }
            // SwiftUI Settings windows have a title containing "Settings"
            if window.title.contains("Settings") {
                window.level = .floating
                window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let observer = settingsWindowObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        ScreenshotManager.shared.stop()
    }

    // MARK: - Accessibility

    private func showAccessibilityPrompt() {
        let alert = NSAlert()
        alert.messageText = "Enable Screenshot Interception"
        alert.informativeText = """
        ScreenShoot can intercept macOS screenshot shortcuts (⌘⇧3/4/5) to provide enhanced screenshot management.

        To enable this feature:
        1. Open System Settings → Privacy & Security → Accessibility
        2. Toggle ScreenShoot to enabled
        3. Restart ScreenShoot

        You can also use ScreenShoot without this feature — screenshots will still be detected when saved to Desktop.
        """
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Skip")

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
