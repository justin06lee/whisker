import Testing
import CoreGraphics
@testable import Whisker

@Test func primaryRadialHasSpecButtons() {
    let labels = RadialMenu.buttons(for: .primary).map(\.label)
    #expect(labels == ["Enter", "Escape", "Tab", "⌘S", "⌘F", "⌘P"])
}

@Test func secondaryRadialHasSpecButtons() {
    let labels = RadialMenu.buttons(for: .secondary).map(\.label)
    #expect(labels == ["⌘T", "⌘N", "⌘W", "Menu"])
}

@Test func paletteQueryMatching() {
    #expect(MenuScanner.matches(path: "File ▸ Export ▸ PDF…", query: "pdf"))
    #expect(MenuScanner.matches(path: "File ▸ Export ▸ PDF…", query: "  Export "))
    #expect(MenuScanner.matches(path: "Edit ▸ Undo", query: ""))
    #expect(!MenuScanner.matches(path: "Edit ▸ Undo", query: "redo"))
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
