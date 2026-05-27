import CoreGraphics

struct GestureMachine {
    private enum State: Equatable {
        case idle
        case rightPending(downAt: CGPoint, downTime: Double)  // right down, threshold not crossed
        case commandMode(originAt: CGPoint)                   // Radial 1 visible
    }

    private let settings: Settings
    private var state: State = .idle

    init(settings: Settings) { self.settings = settings }

    mutating func handle(_ event: GestureEvent) -> [GestureAction] {
        switch (state, event) {
        case let (.idle, .buttonDown(.right, point, time)):
            state = .rightPending(downAt: point, downTime: time)
            return []

        case let (.rightPending(_, downTime), .tick(time)) where time - downTime >= settings.holdThreshold:
            if case let .rightPending(point, _) = state {
                state = .commandMode(originAt: point)
                return [.showRadial(.primary, at: point)]
            }
            return []

        case let (.rightPending(_, downTime), .buttonUp(.right, _, time)):
            state = .idle
            return time - downTime < settings.holdThreshold ? [.passThroughRightClick] : []

        case (.commandMode, .buttonUp(.right, _, _)):
            state = .idle
            return [.hideRadial]

        default:
            return []
        }
    }
}
