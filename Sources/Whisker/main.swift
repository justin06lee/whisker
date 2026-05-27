import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var eventTap: EventTap?
    private var overlay: OverlayController?
    private var screenshot: ScreenshotController?

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

        let overlay = OverlayController()
        let screenshot = ScreenshotController()
        self.overlay = overlay
        self.screenshot = screenshot

        let tap = EventTap(settings: .defaults) { [weak self] actions in
            guard self != nil else { return }
            for action in actions {
                switch action {
                case .passThroughRightClick:
                    break
                case let .showRadial(kind, at: point):
                    overlay.showRadial(kind, atGlobalPoint: point)
                case .hideRadial:
                    overlay.hide()
                case let .selectRadial(at: point):
                    overlay.selectAndHide(atGlobalPoint: point)
                case let .switchAppStep(forward):
                    InputSynth.switchApp(forward: forward)
                case let .commandClick(at: point):
                    InputSynth.modifiedClick(at: point, command: true, shift: false)
                case let .shiftClick(at: point):
                    InputSynth.modifiedClick(at: point, command: false, shift: true)
                case .beginScreenshotRegion, .updateScreenshotRegion,
                     .commitScreenshotRegion, .cancelScreenshotRegion:
                    screenshot.handle(action)
                }
            }
        }
        self.eventTap = tap
        tap.start()
    }

    @MainActor @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // no Dock icon
let delegate = AppDelegate()
app.delegate = delegate
app.run()
