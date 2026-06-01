import Testing
import CoreGraphics
@testable import Whisker

@Test func switcherCategoryTitlesAndOrder() {
    #expect(SwitcherCategory.allCases == [.apps, .windows, .desktops, .tabs])
    #expect(SwitcherCategory.apps.title == "Apps")
    #expect(SwitcherCategory.desktops.title == "Desktops")
}
