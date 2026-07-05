import Foundation

struct Settings: Equatable {
    var holdThreshold: Double            // right-click hold -> command mode
    var leftClickHoldThreshold: Double   // left hold (while right held) -> ⇧-click
    var doubleClickInterval: Double      // max gap for double-right-click
    var autoCopyOnHighlight: Bool
    var motionGesturesEnabled: Bool      // right-drag flick -> back/forward/top/bottom
    var motionDistanceThreshold: Double  // px of right-drag travel that arms a motion gesture

    static let defaults = Settings(
        holdThreshold: 0.150,
        leftClickHoldThreshold: 0.150,
        doubleClickInterval: 0.300,
        autoCopyOnHighlight: true,
        motionGesturesEnabled: true,
        motionDistanceThreshold: 40
    )
}

extension Settings {
    private enum Key {
        static let hold = "holdThreshold"
        static let leftHold = "leftClickHoldThreshold"
        static let doubleClick = "doubleClickInterval"
        static let autoCopy = "autoCopyOnHighlight"
        static let motion = "motionGesturesEnabled"
    }

    /// Settings with persisted overrides applied. Out-of-range stored values
    /// (hand-edited defaults, older builds) are ignored rather than trusted.
    static var current: Settings {
        let ud = UserDefaults.standard
        var s = Settings.defaults
        if let v = ud.object(forKey: Key.hold) as? Double, (0.05...1.0).contains(v) {
            s.holdThreshold = v
        }
        if let v = ud.object(forKey: Key.leftHold) as? Double, (0.05...1.0).contains(v) {
            s.leftClickHoldThreshold = v
        }
        if let v = ud.object(forKey: Key.doubleClick) as? Double, (0.1...1.0).contains(v) {
            s.doubleClickInterval = v
        }
        if ud.object(forKey: Key.autoCopy) != nil {
            s.autoCopyOnHighlight = ud.bool(forKey: Key.autoCopy)
        }
        if ud.object(forKey: Key.motion) != nil {
            s.motionGesturesEnabled = ud.bool(forKey: Key.motion)
        }
        return s
    }

    func save() {
        let ud = UserDefaults.standard
        ud.set(holdThreshold, forKey: Key.hold)
        ud.set(leftClickHoldThreshold, forKey: Key.leftHold)
        ud.set(doubleClickInterval, forKey: Key.doubleClick)
        ud.set(autoCopyOnHighlight, forKey: Key.autoCopy)
        ud.set(motionGesturesEnabled, forKey: Key.motion)
    }
}
