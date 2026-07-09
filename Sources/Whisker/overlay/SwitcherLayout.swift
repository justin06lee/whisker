import CoreGraphics

/// Pure layout + hit-testing for the Switcher HUD, in view-local coordinates
/// (bottom-left origin, matching the non-flipped overlay view).
///
/// A row of circular category buttons sits at a FIXED position above the screen
/// center (so it clears the native ⌘Tab switcher, which Apps mode shows there).
/// In our custom dimensions (windows/desktops/tabs) a translucent glass strip
/// with item tiles + label is drawn near center, below the circles.
struct SwitcherLayout: Equatable {
    enum Hit: Equatable { case category(SwitcherCategory); case item(Int); case none }

    let panel: CGSize
    let itemCount: Int

    // Item tiles. Re-measured against a real macOS 26 ⌘Tab screenshot side by
    // side with ours: 104pt icons, ~44pt gaps, ~48pt padding on all sides
    // (icons sit centered; the label overlays the bottom band, ~8pt under the
    // icon). The earlier 30/36 values made our strip visibly tighter than the
    // system switcher.
    private let itemSize: CGFloat = 104
    private let itemGap: CGFloat = 44
    private let stripPadX: CGFloat = 48
    private let stripPadTop: CGFloat = 48
    private let stripPadBottom: CGFloat = 48
    // Circular category buttons (Whisker's own control; not part of ⌘Tab).
    private let catDiameter: CGFloat = 50
    private let catGap: CGFloat = 16
    private let catAboveCenter: CGFloat = 135   // circle-row center, above screen center

    private var rowWidth: CGFloat {
        guard itemCount > 0 else { return 0 }
        return CGFloat(itemCount) * itemSize + CGFloat(itemCount - 1) * itemGap
    }

    /// Item row vertical center — just below screen center, under the circles.
    private var itemRowCenterY: CGFloat { panel.height / 2 - 12 }

    var itemRects: [CGRect] {
        guard itemCount > 0 else { return [] }
        let startX = (panel.width - rowWidth) / 2
        let y = itemRowCenterY - itemSize / 2
        return (0..<itemCount).map { i in
            CGRect(x: startX + CGFloat(i) * (itemSize + itemGap), y: y,
                   width: itemSize, height: itemSize)
        }
    }

    /// The translucent glass panel behind the item row + label (custom mode only).
    var stripRect: CGRect {
        let w = max(rowWidth, itemSize) + stripPadX * 2
        let x = (panel.width - w) / 2
        let top = itemRowCenterY + itemSize / 2 + stripPadTop
        let bottom = itemRowCenterY - itemSize / 2 - stripPadBottom
        return CGRect(x: x, y: bottom, width: w, height: top - bottom)
    }

    /// Circular category buttons, centered horizontally at a fixed height.
    var categoryRects: [CGRect] {
        let n = SwitcherCategory.allCases.count
        let rowW = CGFloat(n) * catDiameter + CGFloat(n - 1) * catGap
        let startX = (panel.width - rowW) / 2
        let y = panel.height / 2 + catAboveCenter - catDiameter / 2
        return (0..<n).map { i in
            CGRect(x: startX + CGFloat(i) * (catDiameter + catGap), y: y,
                   width: catDiameter, height: catDiameter)
        }
    }

    func hitTest(_ p: CGPoint) -> Hit {
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
