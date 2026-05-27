import CoreGraphics

struct GestureMachine {
    private enum State: Equatable {
        case idle
        case rightPending(downAt: CGPoint, downTime: Double)
        case commandMode(originAt: CGPoint)
        case awaitingSecondRight(at: CGPoint, since: Double)   // first quick tap done; watching for a second
        case secondRightPending(originAt: CGPoint)             // second right is down, not yet released
        case secondaryRadial(originAt: CGPoint)                // Radial 2 visible
        case commandModeLeftDown(originAt: CGPoint, leftDownAt: CGPoint, leftDownTime: Double)
        case screenshotDragging
    }

    private let settings: Settings
    private var state: State = .idle

    init(settings: Settings) { self.settings = settings }

    mutating func handle(_ event: GestureEvent) -> [GestureAction] {
        switch (state, event) {
        case let (.idle, .buttonDown(.right, point, time)):
            state = .rightPending(downAt: point, downTime: time)
            return []

        case let (.rightPending(point, downTime), .tick(time)) where time - downTime >= settings.holdThreshold:
            state = .commandMode(originAt: point)
            return [.showRadial(.primary, at: point)]

        case let (.rightPending(point, downTime), .buttonUp(.right, _, time)):
            if time - downTime < settings.holdThreshold {
                state = .awaitingSecondRight(at: point, since: time)   // defer; could be a double-click
                return []
            }
            state = .idle
            return []

        case (.commandMode, .buttonUp(.right, _, _)):
            state = .idle
            return [.hideRadial]

        case let (.commandMode, .scrolled(deltaY, _)):
            return [.switchAppStep(forward: deltaY < 0)]

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

        case let (.commandModeLeftDown, .scrolled(deltaY, _)):
            return [.switchAppStep(forward: deltaY < 0)]

        // second right-click begins within the double-click window
        case let (.awaitingSecondRight(point, since), .buttonDown(.right, _, time))
            where time - since <= settings.doubleClickInterval:
            state = .secondRightPending(originAt: point)
            return []

        // second right-click completes -> show Radial 2
        // Radial 2 anchors at the first tap's location (second click's point is intentionally ignored).
        case let (.secondRightPending(point), .buttonUp(.right, _, _)):
            state = .secondaryRadial(originAt: point)
            return [.showRadial(.secondary, at: point)]

        // window expired with no second click -> it was a lone tap
        case let (.awaitingSecondRight(_, since), .tick(time)) where time - since > settings.doubleClickInterval:
            state = .idle
            return [.passThroughRightClick]

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
}
