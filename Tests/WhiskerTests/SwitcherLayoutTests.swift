import Testing
import CoreGraphics
@testable import Whisker

@Test func layoutCentersItemsAndPlacesCategories() {
    let l = SwitcherLayout(panel: CGSize(width: 600, height: 400), itemCount: 3)
    #expect(l.itemRects.count == 3)
    #expect(l.categoryRects.count == 4)   // one per SwitcherCategory.allCases
    let leftGap = l.itemRects.first!.minX
    let rightGap = 600 - l.itemRects.last!.maxX
    #expect(abs(leftGap - rightGap) < 0.5)
    #expect(l.categoryRects[0].minY > l.itemRects[0].maxY)
}

@Test func layoutHitTestsCategoryAndItem() {
    let l = SwitcherLayout(panel: CGSize(width: 600, height: 400), itemCount: 3)
    let catCenter = CGPoint(x: l.categoryRects[1].midX, y: l.categoryRects[1].midY)
    #expect(l.hitTest(catCenter) == .category(SwitcherCategory.allCases[1]))
    let itemCenter = CGPoint(x: l.itemRects[2].midX, y: l.itemRects[2].midY)
    #expect(l.hitTest(itemCenter) == .item(2))
    #expect(l.hitTest(CGPoint(x: 1, y: 1)) == .none)
}

@Test func layoutEmptyHasNoItems() {
    let l = SwitcherLayout(panel: CGSize(width: 600, height: 400), itemCount: 0)
    #expect(l.itemRects.isEmpty)
    #expect(l.categoryRects.count == 4)
}
