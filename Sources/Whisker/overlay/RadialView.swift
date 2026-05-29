import CoreGraphics

struct KeyCombo: Equatable {
    let keyCode: CGKeyCode
    let command: Bool
    let shift: Bool

    static let `return` = KeyCombo(keyCode: 0x24, command: false, shift: false)
    static let escape   = KeyCombo(keyCode: 0x35, command: false, shift: false)
    static let tab      = KeyCombo(keyCode: 0x30, command: false, shift: false)
    static let delete   = KeyCombo(keyCode: 0x33, command: false, shift: false)   // Backspace (delete backward)
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
}

struct RadialMenu {
    let kind: RadialKind
    let center: CGPoint
    let radius: CGFloat
    private let deadZone: CGFloat = 24

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

// MARK: - AppKit renderer
//
// `@MainActor` is required here: `NSView` and its drawing surface are
// main-actor-isolated under Swift 6 strict concurrency, so the subclass and its
// `onSelect` stored property must share that isolation. The pure `RadialMenu`
// above stays non-isolated (it is used by the test target off the main actor).

import AppKit

@MainActor
final class RadialNSView: NSView {
    // Named `radialMenu` (not `menu`) to avoid colliding with the inherited
    // `NSResponder.menu` (`NSMenu?`) property, which a plain `menu` would
    // illegally try to override.
    private let radialMenu: RadialMenu
    var onSelect: ((RadialButton) -> Void)?

    init(menu: RadialMenu) {
        self.radialMenu = menu
        super.init(frame: .zero)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func draw(_ dirtyRect: NSRect) {
        let buttons = radialMenu.buttons
        let n = buttons.count
        let config = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
        for (i, button) in buttons.enumerated() {
            let angle = 2 * Double.pi * Double(i) / Double(n)
            let cx = radialMenu.center.x + cos(angle) * radialMenu.radius
            let cy = radialMenu.center.y + sin(angle) * radialMenu.radius
            let rect = NSRect(x: cx - 26, y: cy - 26, width: 52, height: 52)
            NSColor(white: 0.1, alpha: 0.85).setFill()
            NSBezierPath(ovalIn: rect).fill()

            // Draw the SF Symbol centred, tinted white via sourceAtop fill.
            // Falls back to the label string if the symbol fails to load.
            if let raw = NSImage(systemSymbolName: button.symbol,
                                 accessibilityDescription: button.label),
               let glyph = raw.withSymbolConfiguration(config) {
                let size = glyph.size
                let tinted = NSImage(size: size, flipped: false) { dstRect in
                    glyph.draw(in: dstRect)
                    NSColor.white.set()
                    dstRect.fill(using: .sourceAtop)
                    return true
                }
                let glyphRect = NSRect(x: cx - size.width / 2,
                                       y: cy - size.height / 2,
                                       width: size.width,
                                       height: size.height)
                tinted.draw(in: glyphRect)
            } else {
                let attrs: [NSAttributedString.Key: Any] = [
                    .foregroundColor: NSColor.white,
                    .font: NSFont.systemFont(ofSize: 13, weight: .medium),
                ]
                let s = NSAttributedString(string: button.label, attributes: attrs)
                let size = s.size()
                s.draw(at: NSPoint(x: cx - size.width/2, y: cy - size.height/2))
            }
        }
    }

    /// Called by the controller with a window-local point.
    func selectButton(at point: CGPoint) {
        if let b = radialMenu.button(at: point) { onSelect?(b) }
    }
}
