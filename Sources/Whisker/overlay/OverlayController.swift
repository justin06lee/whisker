import AppKit
import CoreGraphics

@MainActor
final class OverlayController {
    private var panel: NSPanel?
    private var radialView: RadialNSView?
    private var screenOrigin: CGPoint = .zero   // Cocoa-global origin of the overlay's screen

    /// Fired when the user picks the palette button on Radial 2.
    var onPalette: (() -> Void)?

    func showRadial(_ kind: RadialKind, atGlobalPoint cgPoint: CGPoint) {
        removePanel()   // immediate replace; no close animation when re-opening

        let cursor = Coords.cocoaGlobal(fromCG: cgPoint)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(cursor) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else { return }
        let frame = screen.frame
        screenOrigin = frame.origin

        let panel = NSPanel(contentRect: frame,
                            styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]

        // Menu center in the view's local (bottom-left) coords = cursor minus screen origin.
        let viewCenter = CGPoint(x: cursor.x - frame.origin.x, y: cursor.y - frame.origin.y)
        let menu = RadialMenu(kind: kind, center: viewCenter, radius: 90)
        let view = RadialNSView(menu: menu, screenOrigin: frame.origin)
        view.frame = NSRect(origin: .zero, size: frame.size)
        view.onSelect = { [weak self] button in
            switch button.action {
            case let .key(combo): InputSynth.post(combo)
            case .palette: self?.onPalette?()
            }
        }
        panel.contentView = view
        panel.orderFrontRegardless()
        view.startAnimating()

        self.panel = panel
        self.radialView = view
    }

    /// Hit-test at the CG-global release point, fire the hit button, then animate close.
    func selectAndHide(atGlobalPoint cgPoint: CGPoint) {
        if let view = radialView {
            let cocoa = Coords.cocoaGlobal(fromCG: cgPoint)
            let viewPoint = CGPoint(x: cocoa.x - screenOrigin.x, y: cocoa.y - screenOrigin.y)
            view.selectButton(at: viewPoint)
        }
        hide()
    }

    /// Animated hide: collapse the buttons, then remove the panel.
    func hide() {
        if let view = radialView {
            view.beginClose { [weak self] in self?.removePanel() }
        } else {
            removePanel()
        }
    }

    private func removePanel() {
        radialView?.stopAnimating()
        panel?.orderOut(nil)
        panel = nil
        radialView = nil
    }
}
