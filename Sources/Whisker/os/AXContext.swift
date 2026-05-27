import ApplicationServices
import CoreGraphics

/// Reads the system-wide focused UI element and its text selection via the
/// Accessibility API.
///
/// AX attribute/role constants (`kAXFocusedUIElementAttribute`, `kAXRoleAttribute`,
/// `kAXSelectedTextAttribute`, `kAXTextFieldRole`, `kAXTextAreaRole`) are global
/// `var CFString`s in the SDK, which Swift 6 strict concurrency rejects as shared
/// mutable state (the same issue `Permissions` hit with `kAXTrustedCheckOptionPrompt`).
/// We use their documented, stable string-literal values instead.
enum AXContext {
    struct Focus: Equatable {
        let isTextField: Bool
        let selectedText: String   // empty if none
        var hasSelection: Bool { !selectedText.isEmpty }
    }

    static func current() -> Focus {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, "AXFocusedUIElement" as CFString, &focused) == .success,
              let element = focused else {
            return Focus(isTextField: false, selectedText: "")
        }
        let el = element as! AXUIElement

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, "AXRole" as CFString, &roleRef)
        let role = roleRef as? String ?? ""
        let isText = (role == "AXTextField" || role == "AXTextArea")

        var selRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, "AXSelectedText" as CFString, &selRef)
        let selected = (selRef as? String) ?? ""

        return Focus(isTextField: isText, selectedText: selected)
    }
}
