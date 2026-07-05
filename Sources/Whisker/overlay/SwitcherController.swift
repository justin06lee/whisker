import AppKit
import CoreGraphics

/// Owns the Switcher overlay (the circular category buttons + the custom HUD
/// strip) and all switching state.
///
/// Apps mode shows the REAL macOS ⌘Tab switcher (driven by a held ⌘ + Tab via
/// InputSynth) so it's pixel-identical to the system; our circular category
/// buttons float above it. The other dimensions (windows/desktops/tabs) have no
/// native switcher, so we render our own glass HUD strip below the circles.
@MainActor
final class SwitcherController {
    private enum Mode: Equatable { case nativeApps; case custom }

    private var panel: NSPanel?
    private var view: SwitcherNSView?
    private var screenOrigin: CGPoint = .zero

    private let sources: [SwitcherCategory: SwitcherSource] = [
        .windows: WindowsSource(),
        .desktops: SpacesSource(),
        .tabs: TabsSource(),
    ]
    private var category: SwitcherCategory = .apps
    private var mode: Mode = .nativeApps
    /// True while a synthetic ⌘ is actually held (native ⌘Tab session live).
    /// `mode` alone can't be used: it defaults to .nativeApps before any
    /// session has started, so gating dismissal on it would inject a spurious
    /// ⌘-Escape into the frontmost app on every open.
    private var nativeSessionActive = false
    private var items: [SwitcherItem] = []
    private var selection = 0

    func open(seed: SwitcherCategory, atGlobalPoint cgPoint: CGPoint) {
        removePanel()

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
        // Above the native ⌘Tab switcher so our circles stay visible over it.
        panel.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        let view = SwitcherNSView(frame: NSRect(origin: .zero, size: screen.frame.size))
        view.enabledCategories = enabledCategories()
        panel.contentView = view
        self.panel = panel
        self.view = view

        enter(seed)
        panel.orderFrontRegardless()
        view.fadeIn()
    }

    func step(forward: Bool) {
        guard view != nil else { return }
        switch mode {
        case .nativeApps:
            InputSynth.tabStep(forward: forward)
        case .custom:
            selection = SwitcherSelection.step(current: selection, forward: forward, count: items.count)
            view?.selection = selection
        }
    }

    func click(atGlobalPoint cgPoint: CGPoint) {
        guard let view else { return }
        let cocoa = Coords.cocoaGlobal(fromCG: cgPoint)
        let viewPoint = CGPoint(x: cocoa.x - screenOrigin.x, y: cocoa.y - screenOrigin.y)
        switch view.hit(at: viewPoint) {
        case let .category(cat):
            guard cat != category, isEnabled(cat) else { return }
            enter(cat)
        case let .item(i):
            guard mode == .custom else { return }
            selection = SwitcherSelection.clamp(i, count: items.count)
            view.selection = selection
        case .none:
            break
        }
    }

    func commit() {
        switch mode {
        case .nativeApps:
            InputSynth.commandUp()                 // releases ⌘ -> switches to highlighted app
            nativeSessionActive = false
        case .custom:
            sources[category]?.commit(index: selection)
        }
        removePanel()
    }

    func cancel() {
        dismissNativeIfNeeded()
        removePanel()
    }

    // MARK: - Mode entry

    /// Switch the active category, tearing down the previous mode and starting
    /// the new one. Apps -> native ⌘Tab; others -> custom HUD strip.
    private func enter(_ cat: SwitcherCategory) {
        dismissNativeIfNeeded()
        category = cat
        view?.activeCategory = cat

        if cat == .apps {
            mode = .nativeApps
            items = []
            view?.items = []                       // hides the strip, leaves circles
            nativeSessionActive = true
            InputSynth.commandDown()               // show the real switcher…
            InputSynth.tabStep(forward: true)      // …highlighting the previous app, like ⌘Tab
        } else {
            mode = .custom
            items = sources[cat]?.items() ?? []
            selection = 0
            view?.items = items
            view?.selection = selection
        }
    }

    private func dismissNativeIfNeeded() {
        guard nativeSessionActive else { return }
        nativeSessionActive = false
        InputSynth.pressEscape()               // dismiss the switcher without switching
        InputSynth.commandUp()                 // release the held ⌘
    }

    // MARK: - Availability

    private func isEnabled(_ cat: SwitcherCategory) -> Bool {
        cat == .apps || (sources[cat]?.isAvailable ?? false)
    }

    private func enabledCategories() -> Set<SwitcherCategory> {
        Set(SwitcherCategory.allCases.filter { isEnabled($0) })
    }

    private func removePanel() {
        view?.stopAnimating()
        panel?.orderOut(nil)
        panel = nil
        view = nil
        items = []
        selection = 0
        mode = .nativeApps
        category = .apps
    }
}
