import CoreGraphics

struct KeyCombo: Equatable {
    let keyCode: CGKeyCode
    let command: Bool
    let shift: Bool

    static let `return` = KeyCombo(keyCode: 0x24, command: false, shift: false)
    static let escape   = KeyCombo(keyCode: 0x35, command: false, shift: false)
    static let tab      = KeyCombo(keyCode: 0x30, command: false, shift: false)
    static let delete   = KeyCombo(keyCode: 0x33, command: false, shift: false)   // Backspace (delete backward)
    static let back     = KeyCombo(keyCode: 0x21, command: true, shift: false)    // ⌘[ (back)
    static let forward  = KeyCombo(keyCode: 0x1E, command: true, shift: false)    // ⌘] (forward)
    static let home     = KeyCombo(keyCode: 0x73, command: false, shift: false)   // scroll to top
    static let end      = KeyCombo(keyCode: 0x77, command: false, shift: false)   // scroll to bottom
    static func cmd(_ letter: Character) -> KeyCombo {
        KeyCombo(keyCode: Self.keyCode(for: letter), command: true, shift: false)
    }
    // Minimal letter -> virtual keycode map for the letters this app uses.
    static func keyCode(for letter: Character) -> CGKeyCode {
        switch letter {
        case "s": return 0x01
        case "f": return 0x03
        case "p": return 0x23
        case "t": return 0x11
        case "n": return 0x2D
        case "w": return 0x0D
        case "x": return 0x07
        case "c": return 0x08
        case "v": return 0x09
        default:  return 0x00
        }
    }
}

struct RadialButton: Equatable {
    let label: String
    let symbol: String          // SF Symbol name; rendered when available
    let action: RadialButtonAction
}

enum RadialButtonAction: Equatable {
    case key(KeyCombo)
    case palette          // open the searchable menu-command palette
}

struct RadialMenu {
    let kind: RadialKind
    let center: CGPoint
    let radius: CGFloat
    private let deadZone: CGFloat = 24
    var deadZoneRadius: CGFloat { deadZone }

    static func buttons(for kind: RadialKind) -> [RadialButton] {
        switch kind {
        case .primary:
            return [
                RadialButton(label: "Enter",  symbol: "return",                       action: .key(.return)),
                RadialButton(label: "Escape", symbol: "escape",                       action: .key(.escape)),
                RadialButton(label: "Tab",    symbol: "arrow.right.to.line.compact",  action: .key(.tab)),
                RadialButton(label: "⌘S",     symbol: "square.and.arrow.down",        action: .key(.cmd("s"))),
                RadialButton(label: "⌘F",     symbol: "magnifyingglass",              action: .key(.cmd("f"))),
                RadialButton(label: "⌘P",     symbol: "printer",                      action: .key(.cmd("p"))),
            ]
        case .secondary:
            return [
                RadialButton(label: "⌘T", symbol: "plus.rectangle",         action: .key(.cmd("t"))),
                RadialButton(label: "⌘N", symbol: "macwindow.badge.plus",   action: .key(.cmd("n"))),
                RadialButton(label: "⌘W", symbol: "xmark",                  action: .key(.cmd("w"))),
                RadialButton(label: "Menu", symbol: "filemenu.and.selection", action: .palette),
            ]
        }
    }

    var buttons: [RadialButton] { Self.buttons(for: kind) }

    /// Returns the button whose angular sector contains `point`, or nil if inside the dead zone.
    func button(at point: CGPoint) -> RadialButton? {
        let dx = point.x - center.x, dy = point.y - center.y
        let dist = (dx*dx + dy*dy).squareRoot()
        guard dist >= deadZone else { return nil }
        let n = buttons.count
        var angle = atan2(dy, dx)                 // -π...π, 0 = right
        if angle < 0 { angle += 2 * .pi }         // 0...2π
        let sector = 2 * Double.pi / Double(n)
        let index = Int((angle + sector / 2) / sector) % n  // button 0 centered on angle 0
        return buttons[index]
    }
}

// MARK: - AppKit renderer (animated)

import AppKit

@MainActor
final class RadialNSView: NSView {
    private let radialMenu: RadialMenu
    private let screenOrigin: CGPoint        // Cocoa-global origin of the screen this view fills
    var onSelect: ((RadialButton) -> Void)?

    // Per-button spring state.
    private var appear: [Double]             // 0 -> 1 (with overshoot) bloom progress
    private var appearVel: [Double]
    private var hover: [Double]              // 0 -> 1 hover/selection emphasis
    private var hoverVel: [Double]

    private var elapsed: Double = 0
    private var closing = false
    private var closeCompletion: (() -> Void)?
    private var timer: Timer?
    private var mouseViewPoint: CGPoint = .zero
    private var hoveredIndex: Int?

    // Spring constants (tuned like a snappy UI spring: stiffness 420, damping 24).
    private let stiffness = 420.0
    private let damping = 24.0
    private let stagger = 0.04               // seconds between each button's bloom
    private let frameInterval = 1.0 / 60.0

    init(menu: RadialMenu, screenOrigin: CGPoint) {
        self.radialMenu = menu
        self.screenOrigin = screenOrigin
        let n = menu.buttons.count
        appear = Array(repeating: 0, count: n)
        appearVel = Array(repeating: 0, count: n)
        hover = Array(repeating: 0, count: n)
        hoverVel = Array(repeating: 0, count: n)
        super.init(frame: .zero)
        wantsLayer = true
    }
    required init?(coder: NSCoder) { fatalError() }

    override var isFlipped: Bool { false }   // bottom-left origin, matches the coord math

    func startAnimating() {
        elapsed = 0
        closing = false
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: frameInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    func stopAnimating() {
        timer?.invalidate(); timer = nil
        closeCompletion = nil
    }

    /// Plays the collapse animation, then calls `completion` (so the controller can remove the panel).
    func beginClose(completion: @escaping () -> Void) {
        guard !closing else { return }
        closing = true
        closeCompletion = completion
    }

    func selectButton(at point: CGPoint) {
        if let b = radialMenu.button(at: point) { onSelect?(b) }
    }

    private func tick() {
        elapsed += frameInterval
        let n = radialMenu.buttons.count

        if !closing {
            let m = NSEvent.mouseLocation
            mouseViewPoint = CGPoint(x: m.x - screenOrigin.x, y: m.y - screenOrigin.y)
            hoveredIndex = indexForHover(at: mouseViewPoint)
        } else {
            hoveredIndex = nil
        }

        var allSettledClosed = true
        for i in 0..<n {
            let appearTarget: Double = closing ? 0.0 : (elapsed >= Double(i) * stagger ? 1.0 : 0.0)
            stepSpring(&appear[i], &appearVel[i], target: appearTarget)
            let hoverTarget: Double = (!closing && hoveredIndex == i) ? 1.0 : 0.0
            stepSpring(&hover[i], &hoverVel[i], target: hoverTarget)
            if closing && (appear[i] > 0.01 || abs(appearVel[i]) > 0.05) { allSettledClosed = false }
        }
        needsDisplay = true

        if closing && allSettledClosed {
            timer?.invalidate(); timer = nil
            let c = closeCompletion; closeCompletion = nil
            c?()
        }
    }

    private func stepSpring(_ x: inout Double, _ v: inout Double, target: Double) {
        let force = -stiffness * (x - target) - damping * v
        v += force * frameInterval
        x += v * frameInterval
    }

    private func indexForHover(at p: CGPoint) -> Int? {
        guard let b = radialMenu.button(at: p) else { return nil }
        return radialMenu.buttons.firstIndex(of: b)
    }

    private func blend(_ a: NSColor, _ b: NSColor, _ t: Double) -> NSColor {
        let t = max(0, min(1, t))
        let ca = a.usingColorSpace(.deviceRGB) ?? a
        let cb = b.usingColorSpace(.deviceRGB) ?? b
        return NSColor(deviceRed: ca.redComponent + (cb.redComponent - ca.redComponent) * t,
                       green: ca.greenComponent + (cb.greenComponent - ca.greenComponent) * t,
                       blue: ca.blueComponent + (cb.blueComponent - ca.blueComponent) * t,
                       alpha: ca.alphaComponent + (cb.alphaComponent - ca.alphaComponent) * t)
    }

    private func drawSymbol(_ button: RadialButton, in rect: NSRect, tint: NSColor,
                            config: NSImage.SymbolConfiguration) {
        if let raw = NSImage(systemSymbolName: button.symbol, accessibilityDescription: button.label),
           let glyph = raw.withSymbolConfiguration(config) {
            let gs = glyph.size
            let tinted = NSImage(size: gs, flipped: false) { dst in
                glyph.draw(in: dst)
                tint.set()
                dst.fill(using: .sourceAtop)
                return true
            }
            let gr = NSRect(x: rect.midX - gs.width / 2, y: rect.midY - gs.height / 2,
                            width: gs.width, height: gs.height)
            tinted.draw(in: gr)
        } else {
            let s = NSAttributedString(string: button.label,
                                       attributes: [.foregroundColor: tint,
                                                    .font: NSFont.systemFont(ofSize: 13, weight: .medium)])
            let ss = s.size()
            s.draw(at: NSPoint(x: rect.midX - ss.width / 2, y: rect.midY - ss.height / 2))
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        let center = radialMenu.center
        let n = radialMenu.buttons.count
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        let openAmount = appear.max() ?? 0

        // Dotted line from center to the live mouse position (under the buttons).
        let dx = mouseViewPoint.x - center.x, dy = mouseViewPoint.y - center.y
        if !closing, (dx * dx + dy * dy).squareRoot() > radialMenu.deadZoneRadius {
            let path = NSBezierPath()
            path.move(to: center)
            path.line(to: mouseViewPoint)
            path.lineWidth = 2
            path.lineCapStyle = .round
            path.setLineDash([2, 6], count: 2, phase: 0)
            NSColor.white.withAlphaComponent(0.7 * openAmount).setStroke()
            path.stroke()
        }

        for (i, button) in radialMenu.buttons.enumerated() {
            let a = appear[i]
            if a <= 0.001 { continue }
            let h = hover[i]
            let opacity = max(0, min(1, a))
            let angle = 2 * Double.pi * Double(i) / Double(n)
            let cx = center.x + cos(angle) * radialMenu.radius * a
            let cy = center.y + sin(angle) * radialMenu.radius * a
            let r = 26.0 * a * (1 + 0.2 * h)
            let rect = NSRect(x: cx - r, y: cy - r, width: 2 * r, height: 2 * r)

            let bg = blend(NSColor(white: 0.1, alpha: 0.85), NSColor.white, h)
                .withAlphaComponent(((0.85) + 0.15 * h) * opacity)
            bg.setFill()
            let circle = NSBezierPath(ovalIn: rect)
            circle.fill()
            if h > 0.01 {
                NSColor.black.withAlphaComponent(h * opacity).setStroke()
                circle.lineWidth = 2
                circle.stroke()
            }
            let iconTint = blend(NSColor.white, NSColor.black, h).withAlphaComponent(opacity)
            drawSymbol(button, in: rect, tint: iconTint, config: config)
        }
    }
}
