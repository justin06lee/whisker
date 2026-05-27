import CoreGraphics

struct KeyCombo: Equatable {
    let keyCode: CGKeyCode
    let command: Bool
    let shift: Bool

    static let `return` = KeyCombo(keyCode: 0x24, command: false, shift: false)
    static let escape   = KeyCombo(keyCode: 0x35, command: false, shift: false)
    static let tab      = KeyCombo(keyCode: 0x30, command: false, shift: false)
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
        default:  return 0x00
        }
    }
}

struct RadialButton: Equatable {
    let label: String
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
                RadialButton(label: "Enter",  action: .key(.return)),
                RadialButton(label: "Escape", action: .key(.escape)),
                RadialButton(label: "Tab",    action: .key(.tab)),
                RadialButton(label: "⌘S",     action: .key(.cmd("s"))),
                RadialButton(label: "⌘F",     action: .key(.cmd("f"))),
                RadialButton(label: "⌘P",     action: .key(.cmd("p"))),
            ]
        case .secondary:
            return [
                RadialButton(label: "⌘T", action: .key(.cmd("t"))),
                RadialButton(label: "⌘N", action: .key(.cmd("n"))),
                RadialButton(label: "⌘W", action: .key(.cmd("w"))),
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
