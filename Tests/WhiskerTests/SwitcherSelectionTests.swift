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

@Test func supportedBrowserDetection() {
    #expect(TabsSource.supportedBrowser(bundleID: "com.apple.Safari") == .safari)
    #expect(TabsSource.supportedBrowser(bundleID: "com.google.Chrome") == .chromium(appName: "Google Chrome"))
    #expect(TabsSource.supportedBrowser(bundleID: "com.microsoft.edgemac") == .chromium(appName: "Microsoft Edge"))
    #expect(TabsSource.supportedBrowser(bundleID: "com.brave.Browser") == .chromium(appName: "Brave Browser"))
    #expect(TabsSource.supportedBrowser(bundleID: "company.thebrowser.Browser") == .chromium(appName: "Arc"))
    #expect(TabsSource.supportedBrowser(bundleID: "com.vivaldi.Vivaldi") == .chromium(appName: "Vivaldi"))
    #expect(TabsSource.supportedBrowser(bundleID: "com.foo.Bar") == nil)
    #expect(TabsSource.supportedBrowser(bundleID: nil) == nil)
}
