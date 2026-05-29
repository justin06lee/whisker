import ApplicationServices
import CoreGraphics

/// Reads the system-wide focused UI element and its text selection via the
/// Accessibility API.
///
/// Editable-text detection is intentionally broad: an element counts as a text
/// field if its AX role is one of the known text roles (`AXTextField`,
/// `AXTextArea`, `AXComboBox`, `AXSearchField`) OR it exposes editable-text
/// attributes — specifically an `AXSelectedTextRange` together with an `AXValue`
/// or `AXSelectedText`. Browser tabs, web inputs, Electron apps, and
/// `contenteditable` fields frequently report nonstandard roles (or focus lands
/// on an `AXWebArea`) yet still expose those text attributes; the strict
/// role-only check made the floating buttons vanish permanently in those
/// contexts. Tradeoff: the heuristic may occasionally false-positive on some web
/// areas that expose a selection range without being truly editable. That is
/// accepted to avoid the buttons disappearing in browsers/Electron.
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

        var selRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, "AXSelectedText" as CFString, &selRef)
        let selected = (selRef as? String) ?? ""

        let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
        var isText = textRoles.contains(role)

        if !isText {
            // Web / Electron / contenteditable inputs often report nonstandard roles but still
            // expose an editable-text selection range. Treat presence of AXSelectedTextRange
            // (plus a value/selected-text attribute) as an editable text field.
            var namesRef: CFArray?
            if AXUIElementCopyAttributeNames(el, &namesRef) == .success,
               let attrs = namesRef as? [String],
               attrs.contains("AXSelectedTextRange"),
               attrs.contains("AXValue") || attrs.contains("AXSelectedText") {
                isText = true
            }
        }

        return Focus(isTextField: isText, selectedText: selected)
    }
}
