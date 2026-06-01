/// Pure selection-index arithmetic for the custom Switcher dimensions (wrap + clamp).
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
