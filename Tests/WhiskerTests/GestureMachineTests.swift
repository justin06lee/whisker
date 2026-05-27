import Testing
import CoreGraphics
@testable import Whisker

private let p = CGPoint(x: 100, y: 100)

@Test func quickRightTapDefersThenPassesThrough() {
    var m = GestureMachine(settings: .defaults)
    _ = m.handle(.buttonDown(.right, at: p, time: 0.0))
    let up = m.handle(.buttonUp(.right, at: p, time: 0.05))
    #expect(up == [])  // deferred: might be the first of a double-click
    let out = m.handle(.tick(time: 0.4))  // double-click window elapsed
    #expect(out == [.passThroughRightClick])
}

@Test func doubleRightClickShowsSecondaryRadial() {
    var m = GestureMachine(settings: .defaults)
    _ = m.handle(.buttonDown(.right, at: p, time: 0.0))
    let first = m.handle(.buttonUp(.right, at: p, time: 0.04))
    #expect(first == [])  // first tap of a potential double is held back
    _ = m.handle(.buttonDown(.right, at: p, time: 0.10))
    let out = m.handle(.buttonUp(.right, at: p, time: 0.14))
    #expect(out == [.showRadial(.secondary, at: p)])
}

@Test func loneTapEmitsPassThroughAfterDoubleClickWindow() {
    var m = GestureMachine(settings: .defaults)
    _ = m.handle(.buttonDown(.right, at: p, time: 0.0))
    _ = m.handle(.buttonUp(.right, at: p, time: 0.04))
    let out = m.handle(.tick(time: 0.35)) // window (0.300) elapsed, no second click
    #expect(out == [.passThroughRightClick])
}

@Test func secondaryRadialHidesOnNextLeftClick() {
    var m = GestureMachine(settings: .defaults)
    _ = m.handle(.buttonDown(.right, at: p, time: 0.0))
    _ = m.handle(.buttonUp(.right, at: p, time: 0.04))
    _ = m.handle(.buttonDown(.right, at: p, time: 0.10))
    _ = m.handle(.buttonUp(.right, at: p, time: 0.14)) // radial 2 up
    let out = m.handle(.buttonDown(.left, at: p, time: 0.5))
    #expect(out == [.hideRadial])
}

@Test func heldRightShowsPrimaryRadial() {
    var m = GestureMachine(settings: .defaults)
    _ = m.handle(.buttonDown(.right, at: p, time: 0.0))
    let out = m.handle(.tick(time: 0.151))        // crosses threshold
    #expect(out == [.showRadial(.primary, at: p)])
}

@Test func releasingAfterHoldHidesRadial() {
    var m = GestureMachine(settings: .defaults)
    _ = m.handle(.buttonDown(.right, at: p, time: 0.0))
    _ = m.handle(.tick(time: 0.151))
    let out = m.handle(.buttonUp(.right, at: p, time: 0.4))
    #expect(out == [.hideRadial])
}

@Test func scrollInCommandModeSwitchesApp() {
    var m = GestureMachine(settings: .defaults)
    _ = m.handle(.buttonDown(.right, at: p, time: 0.0))
    _ = m.handle(.tick(time: 0.151))
    let down = m.handle(.scrolled(deltaY: -3, time: 0.2))
    let up   = m.handle(.scrolled(deltaY: 5, time: 0.3))
    #expect(down == [.switchAppStep(forward: true)])
    #expect(up == [.switchAppStep(forward: false)])
}

@Test func quickLeftClickInCommandModeIsCommandClick() {
    var m = GestureMachine(settings: .defaults)
    _ = m.handle(.buttonDown(.right, at: p, time: 0.0))
    _ = m.handle(.tick(time: 0.151))
    let q = CGPoint(x: 200, y: 200)
    _ = m.handle(.buttonDown(.left, at: q, time: 0.2))
    let out = m.handle(.buttonUp(.left, at: q, time: 0.25)) // < 0.150 held
    #expect(out == [.commandClick(at: q)])
}

@Test func heldLeftClickInCommandModeIsShiftClick() {
    var m = GestureMachine(settings: .defaults)
    _ = m.handle(.buttonDown(.right, at: p, time: 0.0))
    _ = m.handle(.tick(time: 0.151))
    let q = CGPoint(x: 200, y: 200)
    _ = m.handle(.buttonDown(.left, at: q, time: 0.2))
    let out = m.handle(.buttonUp(.left, at: q, time: 0.40)) // 0.20 held >= 0.150
    #expect(out == [.shiftClick(at: q)])
}

@Test func middleDragRunsScreenshotRegion() {
    var m = GestureMachine(settings: .defaults)
    let a = CGPoint(x: 10, y: 10), b = CGPoint(x: 50, y: 60), c = CGPoint(x: 120, y: 140)
    let begin = m.handle(.buttonDown(.middle, at: a, time: 0.0))
    let mid   = m.handle(.dragged(to: b, time: 0.1))
    let end   = m.handle(.buttonUp(.middle, at: c, time: 0.2))
    #expect(begin == [.beginScreenshotRegion(at: a)])
    #expect(mid == [.updateScreenshotRegion(to: b)])
    #expect(end == [.commitScreenshotRegion(to: c)])
}
