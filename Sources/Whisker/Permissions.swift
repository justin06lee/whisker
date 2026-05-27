import ApplicationServices
import AppKit

enum Permissions {
    /// True if Accessibility (needed for CGEventTap) is granted. Prompts if requested.
    static func accessibilityGranted(prompt: Bool) -> Bool {
        // kAXTrustedCheckOptionPrompt is a global `var` in the SDK, which the
        // Swift 6 concurrency checker rejects as shared mutable state. Its value
        // is the documented, stable string "AXTrustedCheckOptionPrompt".
        let key = "AXTrustedCheckOptionPrompt"
        return AXIsProcessTrustedWithOptions([key: prompt] as CFDictionary)
    }

    static func openAccessibilitySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!
        NSWorkspace.shared.open(url)
    }
}
