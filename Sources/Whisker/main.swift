import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var eventTap: EventTap?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐱"

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Quit Whisker", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        if !Permissions.accessibilityGranted(prompt: true) {
            let alert = NSAlert()
            alert.messageText = "Whisker needs Accessibility access"
            alert.informativeText = "Enable Whisker under Privacy & Security ▸ Accessibility, then relaunch."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Quit")
            if alert.runModal() == .alertFirstButtonReturn {
                Permissions.openAccessibilitySettings()
            }
            NSApp.terminate(nil)
            return
        }

        eventTap = EventTap(settings: .defaults) { actions in
            for action in actions { print("ACTION:", action) }
        }
        eventTap?.start()
    }

    @MainActor @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
