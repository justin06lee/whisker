import Foundation

struct Settings: Equatable {
    var holdThreshold: Double            // right-click hold -> command mode
    var leftClickHoldThreshold: Double   // left hold (while right held) -> ⇧-click
    var doubleClickInterval: Double      // max gap for double-right-click
    var autoCopyOnHighlight: Bool

    static let defaults = Settings(
        holdThreshold: 0.150,
        leftClickHoldThreshold: 0.150,
        doubleClickInterval: 0.300,
        autoCopyOnHighlight: true
    )
}

extension Settings {
    /// Settings with persisted overrides applied.
    static var current: Settings {
        var s = Settings.defaults
        if UserDefaults.standard.object(forKey: "autoCopyOnHighlight") != nil {
            s.autoCopyOnHighlight = UserDefaults.standard.bool(forKey: "autoCopyOnHighlight")
        }
        return s
    }

    func save() {
        UserDefaults.standard.set(autoCopyOnHighlight, forKey: "autoCopyOnHighlight")
    }
}
