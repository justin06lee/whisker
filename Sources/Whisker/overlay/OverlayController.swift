import AppKit
import CoreGraphics

// `@MainActor`: this controller owns AppKit objects (`NSPanel`, `RadialNSView`,
// `NSScreen`) which are main-actor-isolated under Swift 6 strict concurrency.
// Annotating the whole class keeps all access on the main actor; the existing
// main-actor `AppDelegate` callers reach it without hops.
@MainActor
final class OverlayController {
    private var panel: NSPanel?
    private var radialView: RadialNSView?

    func showRadial(_ kind: RadialKind, atGlobalPoint global: CGPoint) {
        guard let screen = NSScreen.main else { return }
        hide()

        let panel = NSPanel(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hasShadow = false

        // Convert CG global (top-left origin) to Cocoa (bottom-left origin).
        let local = CGPoint(x: global.x - screen.frame.minX,
                            y: screen.frame.height - (global.y - screen.frame.minY))
        let menu = RadialMenu(kind: kind, center: local, radius: 90)
        let view = RadialNSView(menu: menu)
        view.frame = NSRect(origin: .zero, size: screen.frame.size)
        view.onSelect = { [weak self] button in
            switch button.action { case let .key(combo): InputSynth.post(combo) }
            self?.hide()
        }
        panel.contentView = view
        panel.orderFrontRegardless()
        self.panel = panel
        self.radialView = view
    }

    /// Route a global click (from the event tap) into the radial for hit-testing.
    func handleClick(atGlobalPoint global: CGPoint) {
        guard let screen = NSScreen.main, let view = radialView else { return }
        let local = CGPoint(x: global.x - screen.frame.minX,
                            y: screen.frame.height - (global.y - screen.frame.minY))
        view.selectButton(at: local)
    }

    /// Hit-test at the given global point; fire the button if one is hit; then always hide.
    func selectAndHide(atGlobalPoint global: CGPoint) {
        handleClick(atGlobalPoint: global)  // fires onSelect (which posts the combo) if a button was hit
        hide()                              // always hide, even on a dead-zone miss
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        radialView = nil
    }
}
