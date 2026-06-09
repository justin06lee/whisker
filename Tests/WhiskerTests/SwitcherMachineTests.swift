import Testing
import CoreGraphics
@testable import Whisker

@Test func switcherCategoryTitlesAndOrder() {
    #expect(SwitcherCategory.allCases == [.apps, .windows, .desktops, .tabs])
    #expect(SwitcherCategory.apps.title == "Apps")
    #expect(SwitcherCategory.desktops.title == "Desktops")
}

private let p = CGPoint(x: 100, y: 100)

private func intoSwitcher(scrollUp: Bool) -> GestureMachine {
    var m = GestureMachine(settings: .defaults)
    _ = m.handle(.buttonDown(.right, at: p, time: 0.0))
    _ = m.handle(.tick(time: 0.2))                              // -> commandMode (radial)
    _ = m.handle(.scrolled(deltaY: scrollUp ? 3 : -3, time: 0.3)) // -> switcherActive
    return m
}

@Test func scrollUpOpensAppsSwitcher() {
    var m = GestureMachine(settings: .defaults)
    _ = m.handle(.buttonDown(.right, at: p, time: 0.0))
    _ = m.handle(.tick(time: 0.2))
    let out = m.handle(.scrolled(deltaY: 3, time: 0.3))
    #expect(out == [.hideRadial, .openSwitcher(seed: .apps)])
}

@Test func scrollDownOpensDesktopsSwitcher() {
    var m = GestureMachine(settings: .defaults)
    _ = m.handle(.buttonDown(.right, at: p, time: 0.0))
    _ = m.handle(.tick(time: 0.2))
    let out = m.handle(.scrolled(deltaY: -3, time: 0.3))
    #expect(out == [.hideRadial, .openSwitcher(seed: .desktops)])
}

@Test func furtherScrollStepsSwitcher() {
    var m = intoSwitcher(scrollUp: true)
    #expect(m.handle(.scrolled(deltaY: -2, time: 0.4)) == [.switcherStep(forward: false)])
    #expect(m.handle(.scrolled(deltaY: 5, time: 0.5)) == [.switcherStep(forward: true)])
}

@Test func leftClickWhileSwitcherEmitsSwitcherClick() {
    var m = intoSwitcher(scrollUp: true)
    let q = CGPoint(x: 140, y: 220)
    #expect(m.handle(.buttonDown(.left, at: q, time: 0.4)) == [.switcherClick(at: q)])
    #expect(m.handle(.buttonUp(.left, at: q, time: 0.45)) == [])
}

@Test func releaseRightCommitsSwitcher() {
    var m = intoSwitcher(scrollUp: true)
    #expect(m.handle(.buttonUp(.right, at: p, time: 0.6)) == [.commitSwitcher])
}

@Test func middleClickCancelsSwitcher() {
    var m = intoSwitcher(scrollUp: true)
    #expect(m.handle(.buttonDown(.middle, at: p, time: 0.6)) == [.cancelSwitcher])
}

@Test func switcherInterceptsLeftClicks() {
    let m = intoSwitcher(scrollUp: true)
    #expect(m.isInterceptingLeftClicks == true)
}
