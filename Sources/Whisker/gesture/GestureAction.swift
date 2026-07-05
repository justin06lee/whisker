import CoreGraphics

enum RadialKind: Equatable { case primary, secondary }   // Radial 1 / Radial 2

/// Direction of a right-drag flick, in screen terms (up = toward the top of the
/// screen, i.e. negative CG y).
enum MotionDirection: Equatable { case left, right, up, down }

enum GestureAction: Equatable {
    case passThroughRightClick(at: CGPoint)   // re-synthesize a native right-click (context menu)
    case showRadial(RadialKind, at: CGPoint)
    case hideRadial
    case selectRadial(at: CGPoint)      // hit-test the radial at this point, fire the hit button, then hide
    // Switcher HUD (hold-right + scroll). See docs/superpowers/specs/2026-06-01-switcher-design.md
    case openSwitcher(seed: SwitcherCategory)   // first scroll opens the HUD, seeded by direction
    case switcherStep(forward: Bool)            // subsequent scroll moves the highlight
    case switcherClick(at: CGPoint)             // left-click while open; controller hit-tests it
    case commitSwitcher                         // right released -> activate the highlighted item
    case cancelSwitcher                         // aborted -> hide, switch nothing
    // Mouse-motion gesture: a right-drag flick released before the hold threshold.
    // left/right -> Back/Forward (⌘[ / ⌘]), up/down -> Home/End.
    case motionGesture(MotionDirection)
    case commandClick(at: CGPoint)      // ⌘-click (multi-select)
    case shiftClick(at: CGPoint)        // ⇧-click (range select)
    case beginScreenshotRegion(at: CGPoint)
    case updateScreenshotRegion(to: CGPoint)
    case commitScreenshotRegion(to: CGPoint)
    case cancelScreenshotRegion
}
