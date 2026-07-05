import Testing
import CoreGraphics
@testable import Whisker

private let origin = CGPoint(x: 500, y: 500)

private func flick(to end: CGPoint, settings: Settings = .defaults) -> [GestureAction] {
    var m = GestureMachine(settings: settings)
    _ = m.handle(.buttonDown(.right, at: origin, time: 0.0))
    _ = m.handle(.dragged(to: end, time: 0.05))
    return m.handle(.buttonUp(.right, at: end, time: 0.08))
}

@Test func flickLeftIsBack() {
    #expect(flick(to: CGPoint(x: 400, y: 505)) == [.motionGesture(.left)])
}

@Test func flickRightIsForward() {
    #expect(flick(to: CGPoint(x: 620, y: 495)) == [.motionGesture(.right)])
}

@Test func flickUpIsUp() {
    // CG coords: up on screen = smaller y.
    #expect(flick(to: CGPoint(x: 505, y: 380)) == [.motionGesture(.up)])
}

@Test func flickDownIsDown() {
    #expect(flick(to: CGPoint(x: 495, y: 640)) == [.motionGesture(.down)])
}

@Test func smallDragDoesNotArmMotion() {
    // Under the 40px threshold: stays rightPending; a quick release defers as a
    // potential double-click (same as an ordinary tap), emitting nothing yet.
    var m = GestureMachine(settings: .defaults)
    _ = m.handle(.buttonDown(.right, at: origin, time: 0.0))
    _ = m.handle(.dragged(to: CGPoint(x: 510, y: 505), time: 0.03))
    let up = m.handle(.buttonUp(.right, at: CGPoint(x: 510, y: 505), time: 0.06))
    #expect(up == [])
    let out = m.handle(.tick(time: 0.5))
    #expect(out == [.passThroughRightClick(at: origin)])
}

@Test func returningToOriginAbortsFlick() {
    var m = GestureMachine(settings: .defaults)
    _ = m.handle(.buttonDown(.right, at: origin, time: 0.0))
    _ = m.handle(.dragged(to: CGPoint(x: 600, y: 500), time: 0.04))    // armed
    let up = m.handle(.buttonUp(.right, at: CGPoint(x: 505, y: 502), time: 0.09))
    #expect(up == [])   // released back near the origin -> nothing fires
}

@Test func disabledMotionGesturesFallThroughToRadial() {
    var s = Settings.defaults
    s.motionGesturesEnabled = false
    var m = GestureMachine(settings: s)
    _ = m.handle(.buttonDown(.right, at: origin, time: 0.0))
    _ = m.handle(.dragged(to: CGPoint(x: 700, y: 500), time: 0.05))    // ignored
    let out = m.handle(.tick(time: 0.2))                               // hold threshold fires
    #expect(out == [.showRadial(.primary, at: origin)])
}

@Test func holdWithoutDragStillOpensRadial() {
    var m = GestureMachine(settings: .defaults)
    _ = m.handle(.buttonDown(.right, at: origin, time: 0.0))
    let out = m.handle(.tick(time: 0.2))
    #expect(out == [.showRadial(.primary, at: origin)])
}

@Test func otherButtonAbortsFlick() {
    var m = GestureMachine(settings: .defaults)
    _ = m.handle(.buttonDown(.right, at: origin, time: 0.0))
    _ = m.handle(.dragged(to: CGPoint(x: 600, y: 500), time: 0.04))
    let out = m.handle(.buttonDown(.left, at: CGPoint(x: 600, y: 500), time: 0.06))
    #expect(out == [])
    // machine is back to idle: a fresh right-hold works
    _ = m.handle(.buttonDown(.right, at: origin, time: 1.0))
    let radial = m.handle(.tick(time: 1.2))
    #expect(radial == [.showRadial(.primary, at: origin)])
}
