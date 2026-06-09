import AppKit

/// Browser tabs of the front window. Only available when the frontmost app is a
/// supported browser. Uses AppleScript (needs Automation permission); degrades to
/// an empty list if denied or scripting fails.
@MainActor
final class TabsSource: SwitcherSource {
    enum Browser: Sendable { case safari, chrome }

    let category: SwitcherCategory = .tabs

    var isAvailable: Bool {
        TabsSource.supportedBrowser(
            bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier) != nil
    }

    /// Pure mapping from bundle id to a supported browser (unit-tested).
    nonisolated static func supportedBrowser(bundleID: String?) -> Browser? {
        switch bundleID {
        case "com.apple.Safari": return .safari
        case "com.google.Chrome": return .chrome
        default: return nil
        }
    }

    private var browser: Browser?

    func items() -> [SwitcherItem] {
        guard let app = NSWorkspace.shared.frontmostApplication,
              let b = TabsSource.supportedBrowser(bundleID: app.bundleIdentifier) else { return [] }
        browser = b
        let icon = app.icon
        let titles = runListScript(for: b)
        return titles.map { SwitcherItem(icon: icon, label: $0) }
    }

    func commit(index: Int) {
        guard let b = browser, index >= 0 else { return }
        runSelectScript(for: b, index: index + 1)   // AppleScript tab indices are 1-based
    }

    // MARK: - AppleScript

    private func runListScript(for b: Browser) -> [String] {
        let source: String
        switch b {
        case .safari:
            source = #"tell application "Safari" to get name of every tab of front window"#
        case .chrome:
            source = #"tell application "Google Chrome" to get title of every tab of front window"#
        }
        guard let desc = run(source) else { return [] }
        guard desc.numberOfItems > 0 else {
            return desc.stringValue.map { [$0] } ?? []
        }
        var out: [String] = []
        for i in 1...desc.numberOfItems {
            out.append(desc.atIndex(i)?.stringValue ?? "Tab \(i)")
        }
        return out
    }

    private func runSelectScript(for b: Browser, index: Int) {
        let source: String
        switch b {
        case .safari:
            source = "tell application \"Safari\" to set current tab of front window to tab \(index) of front window"
        case .chrome:
            source = "tell application \"Google Chrome\" to set active tab index of front window to \(index)"
        }
        _ = run(source)
    }

    private func run(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var err: NSDictionary?
        let result = script.executeAndReturnError(&err)
        if let err { FileHandle.standardError.write(Data("whisker tabs: \(err)\n".utf8)); return nil }
        return result
    }
}
