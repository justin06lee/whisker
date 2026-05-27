import AppKit
import CoreGraphics

enum TextEditButton: Equatable { case deleteChar, deleteSelection, cut, copy, paste }

// `@MainActor` is required: `NSView`/`NSPanel` and their drawing surfaces are
// main-actor-isolated under Swift 6 strict concurrency, and the stored
// `onTap` closures are touched from drawing/event callbacks.

@MainActor
final class TextButtonsView: NSView {
    private let buttons: [TextEditButton]
    var onTap: ((TextEditButton) -> Void)?
    private var rects: [(TextEditButton, NSRect)] = []

    init(buttons: [TextEditButton]) { self.buttons = buttons; super.init(frame: .zero) }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        rects = []
        for (i, b) in buttons.enumerated() {
            let rect = NSRect(x: CGFloat(i) * 44, y: 0, width: 40, height: 40)
            rects.append((b, rect))
            NSColor(white: 0.1, alpha: 0.85).setFill()
            NSBezierPath(ovalIn: rect).fill()
            let label: String
            switch b {
            case .deleteChar, .deleteSelection: label = "🗑"
            case .cut: label = "✂️"
            case .copy: label = "⧉"
            case .paste: label = "📋"
            }
            NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: 16)])
                .draw(at: NSPoint(x: rect.midX - 9, y: rect.midY - 10))
        }
    }

    override func mouseDown(with event: NSEvent) {
        let p = convert(event.locationInWindow, from: nil)
        for (b, r) in rects where r.contains(p) { onTap?(b); return }
    }
}

@MainActor
final class TextButtonsController {
    private var panel: NSPanel?
    private var shownButtons: [TextEditButton] = []
    var onTap: ((TextEditButton) -> Void)?

    /// Show the given button set anchored just ABOVE the given screen point (Cocoa coords, bottom-left origin).
    /// If the same set is already shown, just reposition. Pass [] / call hide() to remove.
    func show(_ buttons: [TextEditButton], atCocoaPoint point: CGPoint) {
        if buttons.isEmpty { hide(); return }
        let width = CGFloat(buttons.count) * 44
        let frame = NSRect(x: point.x, y: point.y + 28, width: width, height: 40) // offset above cursor
        if panel == nil || shownButtons != buttons {
            hide()
            let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                            backing: .buffered, defer: false)
            p.isOpaque = false; p.backgroundColor = .clear; p.level = .statusBar; p.hasShadow = false
            let v = TextButtonsView(buttons: buttons)
            v.frame = NSRect(origin: .zero, size: frame.size)
            v.onTap = { [weak self] b in self?.onTap?(b) }
            p.contentView = v
            p.orderFrontRegardless()
            panel = p
            shownButtons = buttons
        } else {
            panel?.setFrame(frame, display: true)
        }
    }

    func hide() {
        panel?.orderOut(nil); panel = nil; shownButtons = []
    }
}
