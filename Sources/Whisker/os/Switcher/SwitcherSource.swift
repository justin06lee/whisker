import AppKit

/// One entry in the Switcher HUD (an app, window, desktop, or tab).
struct SwitcherItem {
    let icon: NSImage?
    let label: String
}

/// A dimension the HUD can cycle. Implementations touch AppKit/AX/AppleScript,
/// so they are MainActor-isolated. `items()` returns the ordered list shown in
/// the HUD; `commit(index:)` performs the actual switch for the chosen index.
@MainActor
protocol SwitcherSource: AnyObject {
    var category: SwitcherCategory { get }
    /// False hides/greys the category (e.g. Tabs when the front app isn't a browser).
    var isAvailable: Bool { get }
    func items() -> [SwitcherItem]
    func commit(index: Int)
}
