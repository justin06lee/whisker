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

    /// Where the panel's bottom-left should be (global Cocoa coords, bottom-left
    /// origin) and where it currently is. The glide timer eases `currentOrigin`
    /// toward `targetOrigin` so the panel slides smoothly as the caret moves instead
    /// of teleporting character-by-character on every AX poll.
    private var targetOrigin: CGPoint = .zero
    private var currentOrigin: CGPoint = .zero
    private var glideTimer: Timer?

    /// Show the given button set with its bottom-left placed at `point` (global Cocoa
    /// coords, bottom-left origin). The caller bakes in any gap/offset.
    ///
    /// - Empty set => hide.
    /// - Panel nil or button set changed => (re)create the panel; SNAP it to `point`
    ///   immediately, fade in, and start the glide timer.
    /// - Same button set (already visible) => only update `targetOrigin`; the glide
    ///   timer eases the panel there. No setFrame, no re-fade here.
    func show(_ buttons: [TextEditButton], atCocoaPoint point: CGPoint) {
        if buttons.isEmpty { hide(); return }
        let width = CGFloat(buttons.count) * 44
        let size = NSSize(width: width, height: 40)

        // The caret target is always the latest poll's point.
        targetOrigin = point

        // Same set, already visible: leave the glide timer to move the panel. Do NOT
        // setFrame and do NOT re-fade — this is what stops the per-keystroke teleport.
        if panel != nil, shownButtons == buttons { return }

        // (Re)create: snap to the target and place there immediately.
        hide()
        currentOrigin = point
        let frame = NSRect(origin: point, size: size)
        let p = NSPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: false)
        p.isOpaque = false; p.backgroundColor = .clear; p.level = .statusBar; p.hasShadow = false
        let v = TextButtonsView(buttons: buttons)
        v.frame = NSRect(origin: .zero, size: size)
        v.onTap = { [weak self] b in self?.onTap?(b) }
        p.contentView = v
        p.setFrameOrigin(currentOrigin)
        p.orderFrontRegardless()

        // Fade in on (re)create only — never on glide. A pure alpha fade is used
        // deliberately: animating layer.anchorPoint to center for a scale-in shifts a
        // view-backed layer and can fight AppKit's frame-driven layout, causing the
        // buttons to drift. A clean fade with zero positional drift is preferable.
        p.alphaValue = 0
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.14
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            p.animator().alphaValue = 1
        }

        panel = p
        shownButtons = buttons
        startGlide()
    }

    /// 60fps exponential-smoothing glide of the panel origin toward `targetOrigin`.
    /// `MainActor.assumeIsolated` is sound: the timer is scheduled on the main run
    /// loop, so the closure always runs main-actor-isolated (same pattern as
    /// `EventTap`/`RadialNSView`).
    private func startGlide() {
        guard glideTimer == nil else { return }
        glideTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                guard let panel = self.panel else { return }
                let dx = self.targetOrigin.x - self.currentOrigin.x
                let dy = self.targetOrigin.y - self.currentOrigin.y
                if abs(dx) < 0.5 && abs(dy) < 0.5 {
                    self.currentOrigin = self.targetOrigin
                } else {
                    self.currentOrigin.x += dx * 0.35   // exponential smoothing; ~converges in ~10 frames
                    self.currentOrigin.y += dy * 0.35
                }
                panel.setFrameOrigin(self.currentOrigin)
            }
        }
    }

    func hide() {
        glideTimer?.invalidate(); glideTimer = nil
        panel?.orderOut(nil); panel = nil
        shownButtons = []
    }
}
