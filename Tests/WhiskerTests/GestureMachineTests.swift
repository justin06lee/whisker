import Testing
import CoreGraphics
@testable import Whisker

private let p = CGPoint(x: 100, y: 100)

@Test func quickRightTapPassesThrough() {
    var m = GestureMachine(settings: .defaults)
    _ = m.handle(.buttonDown(.right, at: p, time: 0.0))
    let out = m.handle(.buttonUp(.right, at: p, time: 0.05)) // < 0.150
    #expect(out == [.passThroughRightClick])
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
