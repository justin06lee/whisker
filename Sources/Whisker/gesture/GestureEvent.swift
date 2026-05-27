import CoreGraphics

enum MouseButton: Equatable { case left, right, middle }

/// Raw mouse input fed to the state machine. Timestamp in seconds.
enum GestureEvent: Equatable {
    case buttonDown(MouseButton, at: CGPoint, time: Double)
    case buttonUp(MouseButton, at: CGPoint, time: Double)
    case dragged(to: CGPoint, time: Double)
    case scrolled(deltaY: Double, time: Double)
    /// Synthetic tick so the machine can fire hold-thresholds without a new input event.
    case tick(time: Double)
}
