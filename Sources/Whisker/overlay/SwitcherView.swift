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
    private let tintLayer = CALayer()
    private let foreground = SwitcherForeground()
    private let shadowLayer = CALayer()
    private var timer: Timer?

    // Panel chrome (from the ⌘Tab design spec). Rounded rect, radius ≈ 0.47 ×
    // half-height (not a full stadium) — measured from the macOS 26 switcher.
    static let cornerRadius: CGFloat = 41

    override var isFlipped: Bool { false }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true

        // The system ⌘Tab switcher renders as a LIGHT frost regardless of the
        // user's appearance. NSVisualEffectView materials follow the effective
        // appearance, so in dark mode .popover would go dark/muddy — pin the
        // whole HUD to aqua so it matches the real switcher in both modes.
        appearance = NSAppearance(named: .aqua)

        // Soft dark drop shadow behind the strip. Lives on its own layer (the glass
        // clips to its bounds for the blur/corners, so it can't cast a shadow itself).
        shadowLayer.shadowColor = NSColor.black.cgColor
        shadowLayer.shadowOpacity = 0.2
        shadowLayer.shadowRadius = 16
        shadowLayer.shadowOffset = CGSize(width: 0, height: -2)
        layer?.addSublayer(shadowLayer)

        // Light frosted "liquid glass" like the macOS 26 ⌘Tab switcher: a bright
        // vibrancy material (.popover) that the wallpaper tints through, modeled as
        // ~white 42% over the backdrop. (.hudWindow darkens instead — wrong era.)
        glass.material = .popover
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.wantsLayer = true
        glass.layer?.cornerRadius = Self.cornerRadius
        glass.layer?.masksToBounds = true
        glass.layer?.borderWidth = 1
        glass.layer?.borderColor = NSColor(white: 1, alpha: 0.35).cgColor   // faint rim, like the system strip
        addSubview(glass)

        // White vibrancy tint riding on top of the blur. .popover alone lets too
        // much wallpaper saturate through (reads purple); the real switcher is a
        // whiter frost. ~white 26% pushes it toward that without killing the blur.
        tintLayer.backgroundColor = NSColor(white: 1, alpha: 0.26).cgColor
        tintLayer.cornerRadius = Self.cornerRadius
        glass.layer?.addSublayer(tintLayer)

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
        let strip = layout.stripRect
        glass.frame = strip
        glass.isHidden = items.isEmpty
        // Shadow follows the strip; its path is the same rounded rect.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tintLayer.frame = CGRect(origin: .zero, size: strip.size)
        shadowLayer.frame = strip
        shadowLayer.shadowPath = CGPath(roundedRect: CGRect(origin: .zero, size: strip.size),
                                        cornerWidth: Self.cornerRadius,
                                        cornerHeight: Self.cornerRadius, transform: nil)
        shadowLayer.isHidden = items.isEmpty
        CATransaction.commit()
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
                // Subtle lighter wash clearly larger than the icon (outset 14 →
                // 132, radius 30), matching the real switcher's selection: a
                // gentle tint on the light glass, not a solid white slab.
                let hl = r.insetBy(dx: -14, dy: -14)
                let path = NSBezierPath(roundedRect: hl, xRadius: 30, yRadius: 30)
                NSColor(white: 1, alpha: 0.5).setFill()
                path.fill()
            }
            // Faint drop shadow so icons lift off the frosted glass like the real
            // switcher — kept soft; a hard shadow reads as boxy tiles.
            NSGraphicsContext.saveGraphicsState()
            let sh = NSShadow()
            sh.shadowColor = NSColor(white: 0, alpha: 0.15)
            sh.shadowBlurRadius = 6
            sh.shadowOffset = NSSize(width: 0, height: -2)
            sh.set()
            if let icon = item.icon {
                icon.draw(in: r, from: .zero, operation: .sourceOver, fraction: 1)
            } else {
                NSColor(white: 0.35, alpha: 1).setFill()
                NSBezierPath(roundedRect: r, xRadius: 14, yRadius: 14).fill()
            }
            NSGraphicsContext.restoreGraphicsState()
        }

        // Highlighted item label, centered UNDER the selected icon (like ⌘Tab),
        // clamped to stay inside the strip when the icon is near an edge.
        if items.indices.contains(selection) {
            let iconRect = l.itemRects[selection]
            let label = items[selection].label
            let para = NSMutableParagraphStyle(); para.alignment = .center; para.lineBreakMode = .byTruncatingTail
            let s = NSAttributedString(string: label, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                .foregroundColor: NSColor(white: 0, alpha: 0.8),
                .paragraphStyle: para])
            let sz = s.size()
            let y = iconRect.minY - 8 - sz.height   // ~8pt gap, like the system label
            let maxW = l.stripRect.width - 24
            let w = min(sz.width, maxW)
            let lo = l.stripRect.minX + 12
            let hi = l.stripRect.maxX - 12 - w
            let x = min(max(iconRect.midX - w / 2, lo), hi)
            s.draw(in: NSRect(x: x, y: y, width: w, height: sz.height))
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
