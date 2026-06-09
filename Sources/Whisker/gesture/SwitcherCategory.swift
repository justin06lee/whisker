/// Which dimension the Switcher HUD is currently cycling.
/// `allCases` order is the fixed left-to-right order of the category bar.
enum SwitcherCategory: String, Equatable, CaseIterable {
    case apps, windows, desktops, tabs

    var title: String {
        switch self {
        case .apps:     return "Apps"
        case .windows:  return "Windows"
        case .desktops: return "Desktops"
        case .tabs:     return "Tabs"
        }
    }

    /// SF Symbol drawn inside the circular category button.
    var symbolName: String {
        switch self {
        case .apps:     return "square.grid.2x2.fill"
        case .windows:  return "macwindow"
        case .desktops: return "squares.below.rectangle"
        case .tabs:     return "square.on.square"
        }
    }
}
