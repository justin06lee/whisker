import CoreGraphics

enum MouseButton: Equatable { case left, right, middle }

/// Raw mouse input fed to the state machine. Timestamp in seconds.
enum GestureEvent: Equatable {
    case buttonDown(MouseButton, at: CGPoint, time: Double)
    case buttonUp(MouseButton, at: CGPoint, time: Double)
    case dragged(to: CGPoint, time: Double)
    case scrolled(deltaY: Double, time: Double)
    /// Synthetic clock tick. The machine relies on ticks to fire time-based transitions
    /// that have no triggering input: the hold-threshold (tap→command mode) AND the
    /// deferred right-click pass-through after the double-click window expires.
    /// The OS-glue layer MUST pump ticks continuously, or these transitions never fire.
    case tick(time: Double)
}
