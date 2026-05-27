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
