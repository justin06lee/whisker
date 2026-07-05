import AppKit

/// Browser tabs of the front window. Only available when the frontmost app is a
/// supported browser. Uses AppleScript (needs Automation permission); degrades to
/// an empty list if denied or scripting fails, and surfaces a one-time prompt
/// pointing at the Automation privacy pane when permission is denied.
@MainActor
final class TabsSource: SwitcherSource {
    /// Safari has its own tab dialect; every Chromium-derived browser shares one,
    /// differing only in the AppleScript application name.
    enum Browser: Equatable, Sendable {
        case safari
        case chromium(appName: String)
    }

    let category: SwitcherCategory = .tabs

    var isAvailable: Bool {
        TabsSource.supportedBrowser(
            bundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier) != nil
    }

    /// Pure mapping from bundle id to a supported browser (unit-tested).
    nonisolated static func supportedBrowser(bundleID: String?) -> Browser? {
        switch bundleID {
        case "com.apple.Safari":            return .safari
        case "com.google.Chrome":           return .chromium(appName: "Google Chrome")
        case "com.microsoft.edgemac":       return .chromium(appName: "Microsoft Edge")
        case "com.brave.Browser":           return .chromium(appName: "Brave Browser")
        case "company.thebrowser.Browser":  return .chromium(appName: "Arc")
        case "com.vivaldi.Vivaldi":         return .chromium(appName: "Vivaldi")
        default: return nil
        }
    }

    private var browser: Browser?
    private static var didPromptAutomation = false

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
        case let .chromium(appName):
            source = "tell application \"\(appName)\" to get title of every tab of front window"
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
        case let .chromium(appName):
            source = "tell application \"\(appName)\" to set active tab index of front window to \(index)"
        }
        _ = run(source)
    }

    private func run(_ source: String) -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else { return nil }
        var err: NSDictionary?
        let result = script.executeAndReturnError(&err)
        if let err {
            FileHandle.standardError.write(Data("whisker tabs: \(err)\n".utf8))
            // -1743 = errAEEventNotPermitted: the user denied (or was never asked
            // for) Automation access for this browser. Point at the fix, once.
            if (err["NSAppleScriptErrorNumber"] as? Int) == -1743 {
                promptForAutomationOnce()
            }
            return nil
        }
        return result
    }

    private func promptForAutomationOnce() {
        guard !Self.didPromptAutomation else { return }
        Self.didPromptAutomation = true
        // items() runs synchronously inside the CGEventTap callback (via
        // SwitcherController.enter). Running a modal loop there stalls the tap
        // until macOS disables it (tapDisabledByTimeout) and re-enters event
        // processing beneath this frame, so defer the alert out of this stack.
        Task { @MainActor in
            Self.presentAutomationAlert()
        }
    }

    @MainActor
    private static func presentAutomationAlert() {
        let alert = NSAlert()
        alert.messageText = "Whisker needs Automation access to list browser tabs"
        alert.informativeText = "Allow Whisker to control your browser in System Settings ▸ Privacy & Security ▸ Automation."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }
}
