import CoreGraphics

enum RadialKind: Equatable { case primary, secondary }   // Radial 1 / Radial 2

enum GestureAction: Equatable {
    case passThroughRightClick          // let the native context menu happen
    case showRadial(RadialKind, at: CGPoint)
    case hideRadial
    case switchAppStep(forward: Bool)   // scroll while right held -> ⌘Tab step
    case commandClick(at: CGPoint)      // ⌘-click (multi-select)
    case shiftClick(at: CGPoint)        // ⇧-click (range select)
    case beginScreenshotRegion(at: CGPoint)
    case updateScreenshotRegion(to: CGPoint)
    case commitScreenshotRegion(to: CGPoint)
    case cancelScreenshotRegion
}
