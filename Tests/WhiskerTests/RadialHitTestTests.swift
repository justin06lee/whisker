import Testing
import CoreGraphics
@testable import Whisker

@Test func primaryRadialHasSpecButtons() {
    let labels = RadialMenu.buttons(for: .primary).map(\.label)
    #expect(labels == ["Enter", "Escape", "Tab", "⌘S", "⌘F", "⌘P"])
}

@Test func secondaryRadialHasSpecButtons() {
    let labels = RadialMenu.buttons(for: .secondary).map(\.label)
    #expect(labels == ["⌘T", "⌘N", "⌘W"])
}

@Test func clickAtCenterSelectsNothing() {
    let menu = RadialMenu(kind: .primary, center: .zero, radius: 80)
    #expect(menu.button(at: CGPoint(x: 2, y: 2)) == nil) // dead zone
}

@Test func clickRightOfCenterSelectsFirstButton() {
    let menu = RadialMenu(kind: .primary, center: .zero, radius: 80)
    // first button placed at angle 0 (straight right), on the ring
    let hit = menu.button(at: CGPoint(x: 80, y: 0))
    #expect(hit?.label == "Enter")
}
