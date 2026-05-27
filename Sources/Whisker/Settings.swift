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
