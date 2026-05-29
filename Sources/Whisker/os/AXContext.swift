import ApplicationServices
import CoreGraphics

/// Reads the system-wide focused UI element, its text selection, and the screen
/// rect of the caret/selection via the Accessibility API.
///
/// Text-field detection is intentionally broad: known text roles
/// (AXTextField/AXTextArea/AXComboBox/AXSearchField) OR any element exposing a
/// text-control attribute (AXSelectedTextRange / AXInsertionPointLineNumber /
/// AXNumberOfCharacters). This biases toward showing the edit buttons in more
/// places (Terminal, web/native inputs) at the cost of occasional false-positives
/// on non-editable text areas — preferred over the buttons silently not appearing.
///
/// The caret rect comes from the `AXBoundsForRange` parameterized attribute applied
/// to the current selected-text range (zero-length range => caret rect). Apps that
/// don't implement it (e.g. canvas-based editors like Google Docs) yield a nil rect.
///
/// AX attribute/role constants are global `var CFString`s the SDK exposes, which
/// Swift 6 strict concurrency rejects as shared mutable state; we use their stable
/// string-literal values instead (same approach as Permissions).
enum AXContext {
    struct Focus: Equatable {
        let isTextField: Bool
        let selectedText: String      // empty if none
        let caretRect: CGRect?        // screen rect (CG global, top-left origin) of caret/selection; nil if unavailable
        var hasSelection: Bool { !selectedText.isEmpty }
    }

    static func current() -> Focus {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, "AXFocusedUIElement" as CFString, &focused) == .success,
              let element = focused else {
            return Focus(isTextField: false, selectedText: "", caretRect: nil)
        }
        let el = element as! AXUIElement

        var roleRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, "AXRole" as CFString, &roleRef)
        let role = roleRef as? String ?? ""

        var selRef: CFTypeRef?
        AXUIElementCopyAttributeValue(el, "AXSelectedText" as CFString, &selRef)
        let selected = (selRef as? String) ?? ""

        // --- broad text detection ---
        let textRoles: Set<String> = ["AXTextField", "AXTextArea", "AXComboBox", "AXSearchField"]
        var isText = textRoles.contains(role)
        var attrNames: [String] = []
        var namesRef: CFArray?
        if AXUIElementCopyAttributeNames(el, &namesRef) == .success, let arr = namesRef as? [String] {
            attrNames = arr
        }
        if !isText {
            if attrNames.contains("AXSelectedTextRange")
                || attrNames.contains("AXInsertionPointLineNumber")
                || attrNames.contains("AXNumberOfCharacters") {
                isText = true
            }
        }

        // --- caret rect via AXBoundsForRange on the selected range ---
        var caretRect: CGRect? = nil
        if isText, attrNames.contains("AXSelectedTextRange") {
            var rangeRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(el, "AXSelectedTextRange" as CFString, &rangeRef) == .success,
               let rangeVal = rangeRef, CFGetTypeID(rangeVal) == AXValueGetTypeID() {
                let axRange = rangeVal as! AXValue
                var boundsRef: CFTypeRef?
                if AXUIElementCopyParameterizedAttributeValue(el, "AXBoundsForRange" as CFString, axRange, &boundsRef) == .success,
                   let boundsVal = boundsRef, CFGetTypeID(boundsVal) == AXValueGetTypeID() {
                    var rect = CGRect.zero
                    if AXValueGetValue(boundsVal as! AXValue, .cgRect, &rect) {
                        caretRect = rect
                    }
                }
            }
        }

        return Focus(isTextField: isText, selectedText: selected, caretRect: caretRect)
    }

    /// One-shot diagnostic: dumps the focused element's role/subrole/attributes and
    /// whether the caret rect resolves, plus the frontmost bundle id. For debugging
    /// why the edit buttons do/don't appear in a given app. Run on the main thread.
    static func debugSnapshot(frontmostBundleID: String?) -> String {
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, "AXFocusedUIElement" as CFString, &focused) == .success,
              let el0 = focused else {
            return "frontmost=\(frontmostBundleID ?? "nil")\nfocused element: NONE"
        }
        let el = el0 as! AXUIElement

        func attr(_ name: String) -> String {
            var r: CFTypeRef?
            AXUIElementCopyAttributeValue(el, name as CFString, &r)
            return (r as? String) ?? "—"
        }

        var namesRef: CFArray?
        AXUIElementCopyAttributeNames(el, &namesRef)
        let attrs = (namesRef as? [String]) ?? []

        var paramRef: CFArray?
        AXUIElementCopyParameterizedAttributeNames(el, &paramRef)
        let params = (paramRef as? [String]) ?? []

        let f = current()
        let caretDesc = f.caretRect.map { "\($0)" } ?? "nil"

        return """
        frontmost=\(frontmostBundleID ?? "nil")
        role=\(attr("AXRole"))  subrole=\(attr("AXSubrole"))
        isTextField=\(f.isTextField)  hasSelection=\(f.hasSelection)  caretRect=\(caretDesc)
        attrs=[\(attrs.joined(separator: ", "))]
        params=[\(params.joined(separator: ", "))]
        """
    }
}
