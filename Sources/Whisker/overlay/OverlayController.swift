import AppKit
import CoreGraphics

// `@MainActor`: owns AppKit objects (NSPanel, RadialNSView, NSScreen) which are
// main-actor-isolated under Swift 6.
@MainActor
final class OverlayController {
    private var panel: NSPanel?
    private var radialView: RadialNSView?
    private var panelOrigin: CGPoint = .zero        // Cocoa-global origin of the panel
    private let panelSize: CGFloat = 260            // fits radius 90 + 26px buttons + margin

    func showRadial(_ kind: RadialKind, atGlobalPoint cgPoint: CGPoint) {
        hide()

        // Cursor in Cocoa-global coords; the panel is centered on it.
        let center = Coords.cocoaGlobal(fromCG: cgPoint)
        let origin = CGPoint(x: center.x - panelSize / 2, y: center.y - panelSize / 2)
        let frame = NSRect(origin: origin, size: CGSize(width: panelSize, height: panelSize))

        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.ignoresMouseEvents = true   // selection is programmatic via the event tap
        panel.hasShadow = false

        // The menu is centered in the panel's own view coords (bottom-left origin).
        let viewCenter = CGPoint(x: panelSize / 2, y: panelSize / 2)
        let menu = RadialMenu(kind: kind, center: viewCenter, radius: 90)
        let view = RadialNSView(menu: menu)
        view.frame = NSRect(origin: .zero, size: frame.size)
        view.onSelect = { [weak self] button in
            if case let .key(combo) = button.action { InputSynth.post(combo) }
            self?.hide()
        }
        panel.contentView = view
        panel.orderFrontRegardless()

        self.panel = panel
        self.radialView = view
        self.panelOrigin = origin
    }

    /// Hit-test at the given CG-global release point; fire the button if one is hit;
    /// then always hide. Hit-testing is pure math (sectors extend beyond the panel),
    /// so a release outside the small panel still selects correctly.
    func selectAndHide(atGlobalPoint cgPoint: CGPoint) {
        defer { hide() }
        guard let view = radialView else { return }
        let cocoa = Coords.cocoaGlobal(fromCG: cgPoint)
        let viewPoint = CGPoint(x: cocoa.x - panelOrigin.x, y: cocoa.y - panelOrigin.y)
        view.selectButton(at: viewPoint)
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
        radialView = nil
    }
}
