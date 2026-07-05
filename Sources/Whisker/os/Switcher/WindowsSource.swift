import AppKit
import ApplicationServices

/// Windows of ALL running regular apps, frontmost app's windows first. Label =
/// window title, icon = the owning app's icon. Commit raises + focuses the
/// chosen window and activates its app.
@MainActor
final class WindowsSource: SwitcherSource {
    let category: SwitcherCategory = .windows
    var isAvailable: Bool { true }

    private struct Entry {
        let window: AXUIElement
        let app: NSRunningApplication
    }

    private var entries: [Entry] = []

    func items() -> [SwitcherItem] {
        entries = []
        let frontPID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let regular = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
        let apps = regular.filter { $0.processIdentifier == frontPID }
                 + regular.filter { $0.processIdentifier != frontPID }   // frontmost first

        var out: [SwitcherItem] = []
        for app in apps {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            var value: CFTypeRef?
            guard AXUIElementCopyAttributeValue(appElement, "AXWindows" as CFString, &value) == .success,
                  let windows = value as? [AXUIElement], !windows.isEmpty else { continue }
            let icon = app.icon
            for win in windows {
                var titleRef: CFTypeRef?
                let title = (AXUIElementCopyAttributeValue(win, "AXTitle" as CFString, &titleRef) == .success
                             ? (titleRef as? String) : nil) ?? ""
                // Skip untitled chrome (palettes, hidden helpers) unless the app
                // has nothing else to show.
                if title.isEmpty && windows.count > 1 { continue }
                entries.append(Entry(window: win, app: app))
                out.append(SwitcherItem(icon: icon,
                                        label: title.isEmpty ? (app.localizedName ?? "Window") : title))
            }
        }
        return out
    }

    func commit(index: Int) {
        guard entries.indices.contains(index) else { return }
        let entry = entries[index]
        AXUIElementSetAttributeValue(entry.window, "AXMain" as CFString, kCFBooleanTrue)
        AXUIElementPerformAction(entry.window, "AXRaise" as CFString)
        entry.app.activate()
    }
}
