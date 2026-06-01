import AppKit
import ApplicationServices

/// Windows of the frontmost application (⌘` analogue). Label = window title,
/// icon = the app's icon. Commit raises + focuses the chosen window.
@MainActor
final class WindowsSource: SwitcherSource {
    let category: SwitcherCategory = .windows
    var isAvailable: Bool { true }

    private var windows: [AXUIElement] = []
    private var owningApp: NSRunningApplication?

    func items() -> [SwitcherItem] {
        windows = []
        guard let app = NSWorkspace.shared.frontmostApplication else { return [] }
        owningApp = app
        let appElement = AXUIElementCreateApplication(app.processIdentifier)

        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, "AXWindows" as CFString, &value) == .success,
              let arr = value as? [AXUIElement] else { return [] }
        windows = arr

        let icon = app.icon
        return windows.map { win in
            var titleRef: CFTypeRef?
            let title = (AXUIElementCopyAttributeValue(win, "AXTitle" as CFString, &titleRef) == .success
                         ? (titleRef as? String) : nil) ?? "Untitled"
            return SwitcherItem(icon: icon, label: title)
        }
    }

    func commit(index: Int) {
        guard windows.indices.contains(index) else { return }
        let win = windows[index]
        AXUIElementSetAttributeValue(win, "AXMain" as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(win, "AXRaise" as CFString)
        owningApp?.activate(options: [.activateIgnoringOtherApps])
    }
}
