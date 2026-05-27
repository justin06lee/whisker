import CoreGraphics

enum RadialKind: Equatable { case primary, secondary }   // Radial 1 / Radial 2

enum GestureAction: Equatable {
    case passThroughRightClick(at: CGPoint)   // re-synthesize a native right-click (context menu)
    case showRadial(RadialKind, at: CGPoint)
    case hideRadial
    case selectRadial(at: CGPoint)      // hit-test the radial at this point, fire the hit button, then hide
    case switchAppStep(forward: Bool)   // scroll while right held -> ⌘Tab step
    case commandClick(at: CGPoint)      // ⌘-click (multi-select)
    case shiftClick(at: CGPoint)        // ⇧-click (range select)
    case beginScreenshotRegion(at: CGPoint)
    case updateScreenshotRegion(to: CGPoint)
    case commitScreenshotRegion(to: CGPoint)
    case cancelScreenshotRegion
}
