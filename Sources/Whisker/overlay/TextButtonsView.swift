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

    /// SF Symbol name for each text-edit button.
    private static func symbolName(for b: TextEditButton) -> String {
        switch b {
        case .deleteChar, .deleteSelection: return "delete.left"
        case .cut:   return "scissors"
        case .copy:  return "doc.on.doc"
        case .paste: return "doc.on.clipboard"
        }
    }

    /// Accessible label for fallback rendering when a symbol is unavailable.
    private static func fallbackLabel(for b: TextEditButton) -> String {
        switch b {
        case .deleteChar, .deleteSelection: return "Delete"
        case .cut:   return "Cut"
        case .copy:  return "Copy"
        case .paste: return "Paste"
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        rects = []
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        for (i, b) in buttons.enumerated() {
            let rect = NSRect(x: CGFloat(i) * 44, y: 0, width: 40, height: 40)
            rects.append((b, rect))
            NSColor(white: 0.1, alpha: 0.85).setFill()
            NSBezierPath(ovalIn: rect).fill()

            let symbol = Self.symbolName(for: b)
            let accLabel = Self.fallbackLabel(for: b)
            if let raw = NSImage(systemSymbolName: symbol, accessibilityDescription: accLabel),
               let glyph = raw.withSymbolConfiguration(config) {
                let size = glyph.size
                let tinted = NSImage(size: size, flipped: false) { dstRect in
                    glyph.draw(in: dstRect)
                    NSColor.white.set()
                    dstRect.fill(using: .sourceAtop)
                    return true
                }
                let glyphRect = NSRect(x: rect.midX - size.width / 2,
                                       y: rect.midY - size.height / 2,
                                       width: size.width,
                                       height: size.height)
                tinted.draw(in: glyphRect)
            } else {
                let attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: NSColor.white,
                    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                ]
                let s = NSAttributedString(string: accLabel, attributes: attrs)
                let size = s.size()
                s.draw(at: NSPoint(x: rect.midX - size.width / 2,
                                   y: rect.midY - size.height / 2))
            }
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

    /// Show the given button set with its bottom-left placed EXACTLY at `point`
    /// (global Cocoa coords, bottom-left origin). The caller bakes in any gap/offset.
    ///
    /// - Empty set => hide.
    /// - Panel nil or button set changed => (re)create the panel at `point`.
    /// - Same button set => just `setFrame` the existing panel to the new point so it
    ///   tracks the caret as it moves (no recreation, no redraw: `display: false`).
    func show(_ buttons: [TextEditButton], atCocoaPoint point: CGPoint) {
        if buttons.isEmpty { hide(); return }
        let width = CGFloat(buttons.count) * 44
        let frame = NSRect(x: point.x, y: point.y, width: width, height: 40)

        if let panel, shownButtons == buttons {
            panel.setFrame(frame, display: false)
            return
        }

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
    }

    func hide() {
        panel?.orderOut(nil); panel = nil; shownButtons = []
    }
}
