import CoreGraphics

struct GestureMachine {
    private enum State: Equatable {
        case idle
        case rightPending(downAt: CGPoint, downTime: Double)
        case motionTracking(originAt: CGPoint)                 // right-drag flick in progress; classify on release
        case commandMode(originAt: CGPoint)
        case switcherActive                                    // Switcher HUD open (scroll/click cycle, release commits)

        case awaitingSecondRight(at: CGPoint, since: Double)   // first quick tap done; watching for a second
        case secondRightPending(originAt: CGPoint)             // second right is down, not yet released
        case secondaryRadial(originAt: CGPoint)                // Radial 2 visible
        case commandModeLeftDown(originAt: CGPoint, leftDownAt: CGPoint, leftDownTime: Double)
        case screenshotDragging
    }

    private let settings: Settings
    private var state: State = .idle

    init(settings: Settings) { self.settings = settings }

    /// True when a left-click should be consumed by Whisker (radial selection / multi-select)
    /// rather than passed to the app underneath.
    var isInterceptingLeftClicks: Bool {
        switch state {
        case .commandMode, .commandModeLeftDown, .secondaryRadial, .switcherActive: return true
        default: return false
        }
    }

    /// True when a scroll-wheel event belongs to Whisker — opening the switcher
    /// from the radial, or cycling the open switcher — so it must be swallowed and
    /// never reach the app underneath (otherwise the page scrolls while you pick).
    var isInterceptingScroll: Bool {
        switch state {
        case .commandMode, .commandModeLeftDown, .switcherActive: return true
        default: return false
        }
    }

    mutating func handle(_ event: GestureEvent) -> [GestureAction] {
        switch (state, event) {
        case let (.idle, .buttonDown(.right, point, time)):
            state = .rightPending(downAt: point, downTime: time)
            return []

        case let (.rightPending(point, downTime), .tick(time)) where time - downTime >= settings.holdThreshold:
            state = .commandMode(originAt: point)
            return [.showRadial(.primary, at: point)]

        // Motion gesture: the right-drag travels past the distance threshold BEFORE
        // the hold threshold fires. Overrides the radial for this press; the flick
        // direction is classified at release.
        case let (.rightPending(downAt, _), .dragged(point, _))
            where settings.motionGesturesEnabled
                && Self.distance(downAt, point) >= settings.motionDistanceThreshold:
            state = .motionTracking(originAt: downAt)
            return []

        // Release ends the flick. Releasing back near the origin aborts (fires
        // nothing); otherwise the dominant axis picks the direction.
        case let (.motionTracking(origin), .buttonUp(.right, point, _)):
            state = .idle
            guard Self.distance(origin, point) >= settings.motionDistanceThreshold else { return [] }
            return [.motionGesture(Self.motionDirection(from: origin, to: point))]

        // Any other button while flick-tracking aborts the gesture.
        case (.motionTracking, .buttonDown):
            state = .idle
            return []

        case let (.rightPending(point, downTime), .buttonUp(.right, _, time)):
            if time - downTime < settings.holdThreshold {
                state = .awaitingSecondRight(at: point, since: time)   // defer; could be a double-click
                return []
            }
            state = .idle
            return []

        case let (.commandMode, .buttonUp(.right, point, _)):
            state = .idle
            return [.selectRadial(at: point)]

        // First scroll while holding right opens the Switcher HUD. Seed category by
        // direction: scroll up -> Apps, scroll down -> Desktops. Dismiss the radial
        // so releasing right commits the switcher instead of mis-firing a radial pick.
        // Zero-delta scrolls (horizontal swipes, momentum/phase boundaries) are ignored.
        case let (.commandMode, .scrolled(deltaY, _)) where deltaY != 0:
            state = .switcherActive
            return [.hideRadial, .openSwitcher(seed: deltaY > 0 ? .apps : .desktops)]

        // Same entry from the left-held variant (user pressed left then scrolled).
        case let (.commandModeLeftDown, .scrolled(deltaY, _)) where deltaY != 0:
            state = .switcherActive
            return [.hideRadial, .openSwitcher(seed: deltaY > 0 ? .apps : .desktops)]

        // HUD open: scroll moves the highlight (reversed: scroll up = forward).
        case let (.switcherActive, .scrolled(deltaY, _)) where deltaY != 0:
            return [.switcherStep(forward: deltaY > 0)]

        // HUD open: left-click -> controller hit-tests (category button or item).
        case let (.switcherActive, .buttonDown(.left, point, _)):
            return [.switcherClick(at: point)]

        // HUD open: left-up is consumed (intercepted) but emits nothing.
        case (.switcherActive, .buttonUp(.left, _, _)):
            return []

        // HUD open: release right -> commit the highlighted item.
        case (.switcherActive, .buttonUp(.right, _, _)):
            state = .idle
            return [.commitSwitcher]

        // HUD open: any other button (e.g. middle) cancels.
        case (.switcherActive, .buttonDown(.middle, _, _)):
            state = .idle
            return [.cancelSwitcher]

        case let (.commandMode(origin), .buttonDown(.left, point, time)):
            state = .commandModeLeftDown(originAt: origin, leftDownAt: point, leftDownTime: time)
            return []

        case let (.commandModeLeftDown(origin, point, leftDownTime), .buttonUp(.left, _, time)):
            state = .commandMode(originAt: origin)
            return time - leftDownTime >= settings.leftClickHoldThreshold
                ? [.shiftClick(at: point)]
                : [.commandClick(at: point)]

        case (.commandModeLeftDown, .buttonUp(.right, _, _)):
            state = .idle
            return [.hideRadial]

        // second right-click begins within the double-click window
        case let (.awaitingSecondRight(point, since), .buttonDown(.right, _, time))
            where time - since <= settings.doubleClickInterval:
            state = .secondRightPending(originAt: point)
            return []

        // Second press landed AFTER the double-click window but BEFORE the expiry
        // tick (ticks are 16ms-granular and the run loop can lag): flush the
        // deferred first click at its original point, and treat this press as a
        // fresh first press (same as the .idle right-down case) so hold-to-radial
        // and motion gestures still work for it.
        case let (.awaitingSecondRight(oldPoint, _), .buttonDown(.right, point, time)):
            state = .rightPending(downAt: point, downTime: time)
            return [.passThroughRightClick(at: oldPoint)]

        // second right-click completes -> show Radial 2
        // Radial 2 anchors at the first tap's location (second click's point is intentionally ignored).
        case let (.secondRightPending(point), .buttonUp(.right, _, _)):
            state = .secondaryRadial(originAt: point)
            return [.showRadial(.secondary, at: point)]

        // window expired with no second click -> it was a lone tap
        case let (.awaitingSecondRight(point, since), .tick(time)) where time - since > settings.doubleClickInterval:
            state = .idle
            return [.passThroughRightClick(at: point)]

        // Radial 2: left-click selects the button at the click point
        case let (.secondaryRadial, .buttonDown(.left, point, _)):
            state = .idle
            return [.selectRadial(at: point)]

        // Radial 2: any other button (right/middle) dismisses
        case (.secondaryRadial, .buttonDown):
            state = .idle
            return [.hideRadial]

        case let (.idle, .buttonDown(.middle, point, _)):
            state = .screenshotDragging
            return [.beginScreenshotRegion(at: point)]

        case let (.screenshotDragging, .dragged(point, _)):
            return [.updateScreenshotRegion(to: point)]

        case let (.screenshotDragging, .buttonUp(.middle, point, _)):
            state = .idle
            return [.commitScreenshotRegion(to: point)]

        // any other button press aborts an in-progress region capture
        case (.screenshotDragging, .buttonDown):
            state = .idle
            return [.cancelScreenshotRegion]

        default:
            return []
        }
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> Double {
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        return (dx * dx + dy * dy).squareRoot()
    }

    /// Classify a flick by its dominant axis. CG coordinates are top-left origin,
    /// so negative dy = the cursor moved UP on screen.
    private static func motionDirection(from a: CGPoint, to b: CGPoint) -> MotionDirection {
        let dx = Double(b.x - a.x), dy = Double(b.y - a.y)
        if abs(dx) >= abs(dy) {
            return dx < 0 ? .left : .right
        }
        return dy < 0 ? .up : .down
    }
}
