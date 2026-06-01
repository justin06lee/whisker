import AppKit

/// Renders the Switcher HUD to look like the macOS ⌘Tab switcher: a liquid-glass
/// (blurred) rounded strip holding a centered row of item tiles with the
/// highlighted item's name beneath it, plus a row of circular category buttons
/// floating above the strip (styled like the radial menu's buttons).
///
/// Structure: a transparent container holds an `NSVisualEffectView` (the glass
/// strip, bottom) and a transparent `SwitcherForeground` (top) that paints the
/// icons, label, selection highlight, and category buttons. The whole container
/// fades in via `alphaValue`.
@MainActor
final class SwitcherNSView: NSView {
    var items: [SwitcherItem] = [] { didSet { sync() } }
    var selection: Int = 0 { didSet { foreground.needsDisplay = true } }
    var activeCategory: SwitcherCategory = .apps { didSet { foreground.needsDisplay = true } }
    var enabledCategories: Set<SwitcherCategory> = Set(SwitcherCategory.allCases) { didSet { foreground.needsDisplay = true } }

    private let glass = NSVisualEffectView()
    private let foreground = SwitcherForeground()
    private var timer: Timer?

    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        // Light frosted glass like the macOS ⌘Tab switcher (not the dark HUD material).
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = 30
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 1
        glass.layer?.borderColor = NSColor(white: 1, alpha: 0.22).cgColor
        addSubview(glass)

        foreground.owner = self
        foreground.frame = bounds
        foreground.autoresizingMask = [.width, .height]
        addSubview(foreground, positioned: .above, relativeTo: glass)
    }
    required init?(coder: NSCoder) { fatalError() }

    var layout: SwitcherLayout { SwitcherLayout(panel: bounds.size, itemCount: items.count) }

    func hit(at viewPoint: CGPoint) -> SwitcherLayout.Hit { layout.hitTest(viewPoint) }

    /// Reposition the glass strip and repaint when content changes. The glass
    /// strip is only shown in our custom dimensions (when there are item tiles);
    /// Apps mode shows the native ⌘Tab switcher instead, with just the circles.
    private func sync() {
        glass.frame = layout.stripRect
        glass.isHidden = items.isEmpty
        foreground.needsDisplay = true
    }

    func fadeIn() {
        alphaValue = 0
        sync()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.alphaValue = min(1, self.alphaValue + 0.2)
                if self.alphaValue >= 1 { self.timer?.invalidate(); self.timer = nil }
            }
        }
    }

    func stopAnimating() { timer?.invalidate(); timer = nil }
}

/// Transparent foreground that paints item icons, the selection highlight, the
/// highlighted item's label, and the circular category buttons.
@MainActor
final class SwitcherForeground: NSView {
    weak var owner: SwitcherNSView?
    override var isFlipped: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }   // never intercept; panel ignores mouse anyway

    override func draw(_ dirtyRect: NSRect) {
        guard let owner else { return }
        let l = owner.layout
        let items = owner.items
        let selection = owner.selection

        // Item tiles (real icons). Selected one gets a white rounded highlight,
        // like the macOS ⌘Tab switcher.
        for (i, item) in items.enumerated() {
            let r = l.itemRects[i]
            if i == selection {
                let hl = r.insetBy(dx: -9, dy: -9)
                NSColor(white: 1, alpha: 0.5).setFill()
                NSBezierPath(roundedRect: hl, xRadius: 18, yRadius: 18).fill()
            }
            if let icon = item.icon {
                icon.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
            } else {
                NSColor(white: 0.35, alpha: 1).setFill()
                NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14).fill()
            }
        }

        // Highlighted item label, centered under the row inside the strip.
        if items.indices.contains(selection), let first = l.itemRects.first {
            let label = items[selection].label
            let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineBreakMode = .byTruncatingTail
            let s = NSAttributedString(string: label, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.labelColor,
                .paragraphStyle: para])
            let sz = s.size()
            let y = first.minY - 8 - sz.height
            let maxW = l.stripRect.width - 24
            let w = min(sz.width, maxW)
            s.draw(in: NSRect(x: owner.bounds.midX - w / 2, y: y, width: w, height: sz.height))
        }

        // Circular category buttons above the strip (radial-menu styling).
        let config = NSImage.SymbolConfiguration(pointSize: 20, weight: .medium)
        for (i, cat) in SwitcherCategory.allCases.enumerated() {
            let r = l.categoryRects[i]
            let enabled = owner.enabledCategories.contains(cat)
            let isActive = (cat == owner.activeCategory)
            let circle = NSBezierPath(ovalIn: r)

            // Selected = white fill (like a selected radial button); else dark disc.
            let baseAlpha: CGFloat = enabled ? 1 : 0.4
            if isActive {
                NSColor.white.withAlphaComponent(baseAlpha).setFill()
            } else {
                NSColor(white: 0.12, alpha: 0.85 * baseAlpha).setFill()
            }
            circle.fill()

            let tint: NSColor = isActive ? NSColor.black : NSColor.white.withAlphaComponent(baseAlpha)
            drawSymbol(cat.symbolName, fallback: cat.title, in: r, tint: tint, config: config)
        }
    }

    private func drawSymbol(_ name: String, fallback: String, in rect: NSRect,
                            tint: NSColor, config: NSImage.SymbolConfiguration) {
        if let raw = NSImage(systemSymbolName: name, accessibilityDescription: fallback),
           let glyph = raw.withSymbolConfiguration(config) {
            let gs = glyph.size
            let tinted = NSImage(size: gs, flipped: false) { dst in
                glyph.draw(in: dst)
                tint.set()
                dst.fill(using: .sourceAtop)
                return true
            }
            tinted.draw(in: NSRect(x: rect.midX - gs.width / 2, y: rect.midY - gs.height / 2,
                                   width: gs.width, height: gs.height))
        } else {
            let s = NSAttributedString(string: fallback, attributes: [
                .foregroundColor: tint, .font: NSFont.systemFont(ofSize: 11, weight: .medium)])
            let ss = s.size()
            s.draw(at: NSPoint(x: rect.midX - ss.width / 2, y: rect.midY - ss.height / 2))
        }
    }
}
