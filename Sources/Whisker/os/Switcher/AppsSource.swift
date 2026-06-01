import AppKit

/// Pure selection-index arithmetic for the Switcher (wrap + clamp).
enum SwitcherSelection {
    static func step(current: Int, forward: Bool, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return ((current + (forward ? 1 : -1)) % count + count) % count
    }
    static func clamp(_ index: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index, 0), count - 1)
    }
}

/// Running regular apps, ordered stably (by name) so the row doesn't reshuffle
/// between opens. Real app icons. Commit activates the chosen app.
@MainActor
final class AppsSource: SwitcherSource {
    let category: SwitcherCategory = .apps
    var isAvailable: Bool { true }

    private var apps: [NSRunningApplication] = []

    func items() -> [SwitcherItem] {
        apps = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
        return apps.map { SwitcherItem(icon: $0.icon, label: $0.localizedName ?? "App") }
    }

    func commit(index: Int) {
        guard apps.indices.contains(index) else { return }
        apps[index].activate(options: [.activateIgnoringOtherApps])
    }
}
