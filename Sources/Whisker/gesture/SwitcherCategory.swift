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
}
