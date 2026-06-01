import AppKit
@preconcurrency import CoreGraphics

// Private CoreGraphics Services symbols. Undocumented; isolated here so the risk
// is contained and the rest of the app stays on public API. If a future macOS
// drops or changes these, `Spaces` degrades to a single desktop (see callers).
private typealias CGSConnectionID = UInt32
@_silgen_name("CGSMainConnectionID")
private func CGSMainConnectionID() -> CGSConnectionID
@_silgen_name("CGSCopyManagedDisplaySpaces")
private func CGSCopyManagedDisplaySpaces(_ cid: CGSConnectionID) -> CFArray?

/// Read-only view of Mission Control Spaces for the primary display, via private
/// CGS APIs. Returns conservative defaults (1 space, index 0) if the private call
/// fails or its shape changed.
enum Spaces {
    /// (count, currentIndex) for the first managed display.
    static func snapshot() -> (count: Int, currentIndex: Int) {
        let cid = CGSMainConnectionID()
        guard let displays = CGSCopyManagedDisplaySpaces(cid) as? [[String: Any]],
              let first = displays.first,
              let spaceList = first["Spaces"] as? [[String: Any]] else {
            return (1, 0)
        }
        let count = max(spaceList.count, 1)

        // Current space id lives under "Current Space" -> "ManagedSpaceID".
        var currentID: Int?
        if let cur = first["Current Space"] as? [String: Any] {
            currentID = (cur["ManagedSpaceID"] as? Int) ?? (cur["id64"] as? Int)
        }
        let ids: [Int] = spaceList.map { ($0["ManagedSpaceID"] as? Int) ?? ($0["id64"] as? Int) ?? -1 }
        let idx = currentID.flatMap { ids.firstIndex(of: $0) } ?? 0
        return (count, idx)
    }
}

/// Numbered desktop tiles. Commit steps Ctrl+Left/Right to the target index.
@MainActor
final class SpacesSource: SwitcherSource {
    let category: SwitcherCategory = .desktops
    var isAvailable: Bool { true }

    private var count = 1
    private var current = 0

    func items() -> [SwitcherItem] {
        let snap = Spaces.snapshot()
        count = snap.count
        current = snap.currentIndex
        let symbol = NSImage(systemSymbolName: "macwindow", accessibilityDescription: "Desktop")
        return (0..<count).map { i in
            SwitcherItem(icon: symbol, label: "Desktop \(i + 1)")
        }
    }

    func commit(index: Int) {
        let target = SwitcherSelection.clamp(index, count: count)
        let delta = target - current
        guard delta != 0 else { return }
        InputSynth.switchSpace(left: delta < 0, times: abs(delta))
    }
}
