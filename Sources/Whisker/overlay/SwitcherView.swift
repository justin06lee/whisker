import AppKit

/// Renders the Switcher HUD: a translucent rounded panel with a category bar above
/// a centered row of item tiles. Source-agnostic — it only knows items, the active
/// category, which categories are enabled, and the highlighted index. Geometry comes
/// from SwitcherLayout. Simple fade-in via a short manual animation.
@MainActor
final class SwitcherNSView: NSView {
    var items: [SwitcherItem] = [] { didSet { needsDisplay = true } }
    var selection: Int = 0 { didSet { needsDisplay = true } }
    var activeCategory: SwitcherCategory = .apps { didSet { needsDisplay = true } }
    var enabledCategories: Set<SwitcherCategory> = Set(SwitcherCategory.allCases) { didSet { needsDisplay = true } }

    private var opacity: Double = 0
    private var timer: Timer?

    override var isFlipped: Bool { false }

    private var layout: SwitcherLayout { SwitcherLayout(panel: bounds.size, itemCount: items.count) }

    func hit(at viewPoint: CGPoint) -> SwitcherLayout.Hit { layout.hitTest(viewPoint) }

    func fadeIn() {
        opacity = 0
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1.0/60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.opacity = min(1, self.opacity + 0.18)
                self.needsDisplay = true
                if self.opacity >= 1 { self.timer?.invalidate(); self.timer = nil }
            }
        }
    }

    func stopAnimating() { timer?.invalidate(); timer = nil }

    override func draw(_ dirtyRect: NSRect) {
        let l = layout
        guard !items.isEmpty || !l.categoryRects.isEmpty else { return }

        let union = (l.itemRects + l.categoryRects).reduce(CGRect.null) { $0.union($1) }
            .insetBy(dx: -24, dy: -24)
        let bg = NSBezierPath(roundedRect: union, xRadius: 22, yRadius: 22)
        NSColor(white: 0.12, alpha: 0.92 * opacity).setFill()
        bg.fill()

        let font = NSFont.systemFont(ofSize: 13, weight: .medium)
        for (i, cat) in SwitcherCategory.allCases.enumerated() {
            let r = l.categoryRects[i]
            let enabled = enabledCategories.contains(cat)
            let isActive = (cat == activeCategory)
            if isActive {
                NSColor(white: 1, alpha: 0.18 * opacity).setFill()
                NSBezierPath(roundedRect: r, xRadius: 8, yRadius: 8).fill()
            }
            let alpha = (enabled ? (isActive ? 1.0 : 0.65) : 0.25) * opacity
            let s = NSAttributedString(string: cat.title, attributes: [
                .font: font, .foregroundColor: NSColor.white.withAlphaComponent(alpha)])
            let sz = s.size()
            s.draw(at: NSPoint(x: r.midX - sz.width/2, y: r.midY - sz.height/2))
        }

        for (i, item) in items.enumerated() {
            let r = l.itemRects[i]
            if i == selection {
                NSColor(white: 1, alpha: 0.22 * opacity).setFill()
                NSBezierPath(roundedRect: r.insetBy(dx: -6, dy: -6), xRadius: 14, yRadius: 14).fill()
            }
            if let icon = item.icon {
                icon.draw(in: r, from: .zero, operation: .sourceOver, fraction: opacity)
            } else {
                let ph = NSBezierPath(roundedRect: r, xRadius: 12, yRadius: 12)
                NSColor(white: 0.3, alpha: opacity).setFill(); ph.fill()
            }
        }

        if items.indices.contains(selection), let first = l.itemRects.first {
            let label = items[selection].label
            let s = NSAttributedString(string: label, attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: NSColor.white.withAlphaComponent(opacity)])
            let sz = s.size()
            let y = first.minY - 10 - sz.height
            s.draw(at: NSPoint(x: bounds.midX - sz.width/2, y: y))
        }
    }
}
