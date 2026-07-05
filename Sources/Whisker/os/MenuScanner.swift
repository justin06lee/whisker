import AppKit
import ApplicationServices

/// One executable menu-bar command of the target app.
struct PaletteCommand {
    let path: String            // "File ▸ Export ▸ PDF…"
    let element: AXUIElement    // the AXMenuItem to AXPress
}

/// Scans an app's menu bar into a flat, searchable command list via the
/// Accessibility API. Depth-capped and enabled-items-only. Synchronous —
/// called once when the palette opens (a deliberate user action), typically
/// tens of milliseconds for ordinary menu bars.
enum MenuScanner {
    /// Pure helper: does `query` match `path` (case-insensitive substring;
    /// empty query matches everything)? Unit-tested.
    static func matches(path: String, query: String) -> Bool {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return true }
        return path.range(of: q, options: [.caseInsensitive, .diacriticInsensitive]) != nil
    }

    static func commands(forPID pid: pid_t) -> [PaletteCommand] {
        let app = AXUIElementCreateApplication(pid)
        var barRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, "AXMenuBar" as CFString, &barRef) == .success,
              let bar = barRef else { return [] }

        var out: [PaletteCommand] = []
        // Menu-bar items: [Apple, <App>, File, Edit, …]. Skip the Apple menu; the
        // app menu and the rest are all useful.
        for (i, top) in children(of: bar as! AXUIElement).enumerated() {
            if i == 0 { continue }   // Apple menu
            let topTitle = title(of: top)
            guard !topTitle.isEmpty else { continue }
            for menu in children(of: top) {   // the AXMenu container under the bar item
                collect(menu: menu, pathPrefix: topTitle, depth: 0, into: &out)
            }
        }
        return out
    }

    // MARK: - Private

    private static let maxDepth = 3       // File ▸ Export ▸ PDF ▸ … is deep enough
    private static let maxCommands = 2000 // runaway-menu backstop

    private static func collect(menu: AXUIElement, pathPrefix: String, depth: Int,
                                into out: inout [PaletteCommand]) {
        guard depth <= maxDepth, out.count < maxCommands else { return }
        for item in children(of: menu) {
            let t = title(of: item)
            guard !t.isEmpty else { continue }   // separators have no title
            let sub = children(of: item)
            let submenu = sub.first(where: { role(of: $0) == "AXMenu" })
            if let submenu {
                collect(menu: submenu, pathPrefix: "\(pathPrefix) ▸ \(t)", depth: depth + 1, into: &out)
            } else if isEnabled(item) {
                out.append(PaletteCommand(path: "\(pathPrefix) ▸ \(t)", element: item))
                if out.count >= maxCommands { return }
            }
        }
    }

    private static func children(of el: AXUIElement) -> [AXUIElement] {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, "AXChildren" as CFString, &ref) == .success,
              let arr = ref as? [AXUIElement] else { return [] }
        return arr
    }

    private static func title(of el: AXUIElement) -> String {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, "AXTitle" as CFString, &ref) == .success else { return "" }
        return (ref as? String) ?? ""
    }

    private static func role(of el: AXUIElement) -> String {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, "AXRole" as CFString, &ref) == .success else { return "" }
        return (ref as? String) ?? ""
    }

    private static func isEnabled(_ el: AXUIElement) -> Bool {
        var ref: CFTypeRef?
        guard AXUIElementCopyAttributeValue(el, "AXEnabled" as CFString, &ref) == .success,
              let b = ref as? Bool else { return true }
        return b
    }
}
