import CoreGraphics

/// Pure layout + hit-testing for the Switcher HUD, in view-local coordinates
/// (bottom-left origin, matching the non-flipped overlay view). The HUD is a
/// centered band: a category bar above a horizontally-centered row of item tiles.
struct SwitcherLayout: Equatable {
    enum Hit: Equatable { case category(SwitcherCategory); case item(Int); case none }

    let panel: CGSize
    let itemCount: Int

    private let itemSize: CGFloat = 72
    private let itemGap: CGFloat = 16
    private let catWidth: CGFloat = 104
    private let catHeight: CGFloat = 30
    private let catGap: CGFloat = 10
    private let bandGap: CGFloat = 18

    var itemRects: [CGRect] {
        guard itemCount > 0 else { return [] }
        let rowW = CGFloat(itemCount) * itemSize + CGFloat(itemCount - 1) * itemGap
        let startX = (panel.width - rowW) / 2
        let y = panel.height / 2 - itemSize / 2
        return (0..<itemCount).map { i in
            CGRect(x: startX + CGFloat(i) * (itemSize + itemGap), y: y,
                   width: itemSize, height: itemSize)
        }
    }

    var categoryRects: [CGRect] {
        let n = SwitcherCategory.allCases.count
        let rowW = CGFloat(n) * catWidth + CGFloat(n - 1) * catGap
        let startX = (panel.width - rowW) / 2
        let itemTop = (itemCount > 0) ? (panel.height / 2 + itemSize / 2) : panel.height / 2
        let y = itemTop + bandGap
        return (0..<n).map { i in
            CGRect(x: startX + CGFloat(i) * (catWidth + catGap), y: y,
                   width: catWidth, height: catHeight)
        }
    }

    func hitTest(_ p: CGPoint) -> Hit {
        for (i, r) in categoryRects.enumerated() where r.contains(p) {
            return .category(SwitcherCategory.allCases[i])
        }
        for (i, r) in itemRects.enumerated() where r.contains(p) {
            return .item(i)
        }
        return .none
    }
}
