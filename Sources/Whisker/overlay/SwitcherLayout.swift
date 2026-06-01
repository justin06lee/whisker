import CoreGraphics

/// Pure layout + hit-testing for the Switcher HUD, in view-local coordinates
/// (bottom-left origin, matching the non-flipped overlay view).
///
/// Visual structure (top to bottom): a row of circular category buttons floats
/// ABOVE a translucent "glass" strip. The strip holds a centered row of item
/// tiles with the highlighted item's label beneath them.
struct SwitcherLayout: Equatable {
    enum Hit: Equatable { case category(SwitcherCategory); case item(Int); case none }

    let panel: CGSize
    let itemCount: Int

    // Item tiles (app/window/desktop/tab icons). Sized + spaced to match ⌘Tab.
    private let itemSize: CGFloat = 84
    private let itemGap: CGFloat = 22
    // Glass strip padding around the item row.
    private let stripPadX: CGFloat = 28
    private let stripPadTop: CGFloat = 24
    private let stripPadBottom: CGFloat = 48   // room for the label under the row
    // Circular category buttons.
    private let catDiameter: CGFloat = 50
    private let catGap: CGFloat = 16
    private let catStripGap: CGFloat = 18      // gap between category row and strip

    private var rowWidth: CGFloat {
        guard itemCount > 0 else { return 0 }
        return CGFloat(itemCount) * itemSize + CGFloat(itemCount - 1) * itemGap
    }

    /// Vertical center of the item row. The whole cluster (categories + strip) is
    /// centered in the panel; the item row sits a little below panel center to
    /// leave headroom for the category buttons above the strip.
    private var itemRowCenterY: CGFloat {
        let clusterHeight = catDiameter + catStripGap + stripPadTop + itemSize + stripPadBottom
        let clusterTop = panel.height / 2 + clusterHeight / 2
        // item row center, measured down from the cluster top.
        return clusterTop - catDiameter - catStripGap - stripPadTop - itemSize / 2
    }

    var itemRects: [CGRect] {
        guard itemCount > 0 else { return [] }
        let startX = (panel.width - rowWidth) / 2
        let y = itemRowCenterY - itemSize / 2
        return (0..<itemCount).map { i in
            CGRect(x: startX + CGFloat(i) * (itemSize + itemGap), y: y,
                   width: itemSize, height: itemSize)
        }
    }

    /// The translucent glass panel behind the item row + label.
    var stripRect: CGRect {
        let w = max(rowWidth, itemSize) + stripPadX * 2
        let x = (panel.width - w) / 2
        let top = itemRowCenterY + itemSize / 2 + stripPadTop
        let bottom = itemRowCenterY - itemSize / 2 - stripPadBottom
        return CGRect(x: x, y: bottom, width: w, height: top - bottom)
    }

    /// Square frames for the circular category buttons, centered above the strip.
    var categoryRects: [CGRect] {
        let n = SwitcherCategory.allCases.count
        let rowW = CGFloat(n) * catDiameter + CGFloat(n - 1) * catGap
        let startX = (panel.width - rowW) / 2
        let y = stripRect.maxY + catStripGap
        return (0..<n).map { i in
            CGRect(x: startX + CGFloat(i) * (catDiameter + catGap), y: y,
                   width: catDiameter, height: catDiameter)
        }
    }

    func hitTest(_ p: CGPoint) -> Hit {
        // Circular hit-test for the category buttons.
        for (i, r) in categoryRects.enumerated() {
            let dx = p.x - r.midX, dy = p.y - r.midY
            if (dx * dx + dy * dy).squareRoot() <= r.width / 2 {
                return .category(SwitcherCategory.allCases[i])
            }
        }
        for (i, r) in itemRects.enumerated() where r.contains(p) {
            return .item(i)
        }
        return .none
    }
}
