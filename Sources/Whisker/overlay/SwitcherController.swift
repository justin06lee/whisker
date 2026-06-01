import AppKit
import CoreGraphics

/// Owns the Switcher HUD panel and all switching state: the active category, the
/// selection index, the per-category sources, and which categories are enabled.
/// Driven by the gesture actions via main.swift.
@MainActor
final class SwitcherController {
    private var panel: NSPanel?
    private var view: SwitcherNSView?
    private var screenOrigin: CGPoint = .zero

    private let sources: [SwitcherCategory: SwitcherSource] = [
        .apps: AppsSource(),
        .windows: WindowsSource(),
        .desktops: SpacesSource(),
        .tabs: TabsSource(),
    ]
    private var category: SwitcherCategory = .apps
    private var items: [SwitcherItem] = []
    private var selection = 0

    func open(seed: SwitcherCategory, atGlobalPoint cgPoint: CGPoint) {
        removePanel()
        category = seed

        let cursor = Coords.cocoaGlobal(fromCG: cgPoint)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) })
            ?? NSScreen.main ?? NSScreen.screens.first
        guard let screen else { return }
        screenOrigin = screen.frame.origin

        let panel = NSPanel(contentRect: screen.frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let view = SwitcherNSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.enabledCategories = Set(SwitcherCategory.allCases.filter { sources[$0]?.isAvailable ?? false })
        panel.contentView = view
        self.panel = panel
        self.view = view

        loadCategory(seed, resetSelection: true)
        panel.orderFrontRegardless()
        view.fadeIn()
    }

    func step(forward: Bool) {
        guard view != nil else { return }
        selection = SwitcherSelection.step(current: selection, forward: forward, count: items.count)
        view?.selection = selection
    }

    func click(atGlobalPoint cgPoint: CGPoint) {
        guard let view else { return }
        let cocoa = Coords.cocoaGlobal(fromCG: cgPoint)
        let viewPoint = CGPoint(x: cocoa.x - screenOrigin.x, y: cocoa.y - screenOrigin.y)
        switch view.hit(at: viewPoint) {
        case let .category(cat):
            if (sources[cat]?.isAvailable ?? false) { loadCategory(cat, resetSelection: true) }
        case let .item(i):
            selection = SwitcherSelection.clamp(i, count: items.count)
            view.selection = selection
        case .none:
            break
        }
    }

    func commit() {
        sources[category]?.commit(index: selection)
        removePanel()
    }

    func cancel() { removePanel() }

    private func loadCategory(_ cat: SwitcherCategory, resetSelection: Bool) {
        category = cat
        items = sources[cat]?.items() ?? []
        if resetSelection {
            selection = (cat == .apps && items.count > 1) ? 1 : 0
        } else {
            selection = SwitcherSelection.clamp(selection, count: items.count)
        }
        view?.items = items
        view?.activeCategory = cat
        view?.selection = selection
    }

    private func removePanel() {
        view?.stopAnimating()
        panel?.orderOut(nil)
        panel = nil
        view = nil
        items = []
        selection = 0
    }
}
