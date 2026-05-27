import Testing
@testable import Whisker

@Test func defaultSettingsMatchSpec() {
    let s = Settings.defaults
    #expect(s.holdThreshold == 0.150)
    #expect(s.leftClickHoldThreshold == 0.150)
    #expect(s.doubleClickInterval == 0.300)
    #expect(s.autoCopyOnHighlight == true)
}
