import Testing
@testable import Whisker

@Test func stepWrapsForwardAndBackward() {
    #expect(SwitcherSelection.step(current: 0, forward: true, count: 3) == 1)
    #expect(SwitcherSelection.step(current: 2, forward: true, count: 3) == 0)   // wrap
    #expect(SwitcherSelection.step(current: 0, forward: false, count: 3) == 2)  // wrap back
    #expect(SwitcherSelection.step(current: 1, forward: false, count: 3) == 0)
}

@Test func stepClampsEmpty() {
    #expect(SwitcherSelection.step(current: 0, forward: true, count: 0) == 0)
}

@Test func clampKeepsInRange() {
    #expect(SwitcherSelection.clamp(5, count: 3) == 2)
    #expect(SwitcherSelection.clamp(-1, count: 3) == 0)
    #expect(SwitcherSelection.clamp(0, count: 0) == 0)
}
