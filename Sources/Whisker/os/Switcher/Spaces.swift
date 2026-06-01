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

/// Read-only view of Mission Control Spaces, via private CGS APIs. Returns
/// conservative defaults (1 space, index 0) if the private call fails or its
/// shape changed.
///
/// `CGSCopyManagedDisplaySpaces` returns one dict per display; each has a
/// "Spaces" array and a "Current Space" dict. We flatten the user (non-fullscreen)
/// spaces across all displays in order, matching how Ctrl+←/→ steps between them,
/// and locate the current one by ManagedSpaceID.
@MainActor
enum Spaces {
    private static var didDump = false

    static func snapshot() -> (count: Int, currentIndex: Int) {
        let cid = CGSMainConnectionID()
        guard let raw = CGSCopyManagedDisplaySpaces(cid) as? [Any] else {
            dumpOnce("CGSCopyManagedDisplaySpaces returned nil/non-array")
            return (1, 0)
        }

        // Flatten user spaces across displays, in order. A space's "type" == 0 is a
        // standard desktop; fullscreen-app spaces (type 4) are excluded so the
        // numbering matches the Desktops shown in Mission Control + Ctrl+arrow order.
        var spaceIDs: [Int] = []
        var currentID: Int?
        for case let display as [String: Any] in raw {
            if let spaces = display["Spaces"] as? [Any] {
                for case let s as [String: Any] in spaces {
                    if let type = s["type"] as? Int, type != 0 { continue }   // skip fullscreen
                    if let id = (s["ManagedSpaceID"] as? Int) ?? (s["id64"] as? Int) {
                        spaceIDs.append(id)
                    }
                }
            }
            if currentID == nil, let cur = display["Current Space"] as? [String: Any] {
                currentID = (cur["ManagedSpaceID"] as? Int) ?? (cur["id64"] as? Int)
            }
        }

        if spaceIDs.count <= 1 { dumpOnce("parsed \(spaceIDs.count) user space(s)") }

        let count = max(spaceIDs.count, 1)
        let idx = currentID.flatMap { spaceIDs.firstIndex(of: $0) } ?? 0
        return (count, idx)
    }

    /// One-time diagnostic dump of the raw CGS structure to stderr, so a
    /// `swift run Whisker` from a terminal reveals the shape when detection is off.
    private static func dumpOnce(_ note: String) {
        guard !didDump else { return }
        didDump = true
        let cid = CGSMainConnectionID()
        let raw = CGSCopyManagedDisplaySpaces(cid)
        FileHandle.standardError.write(Data(
            "whisker Spaces: \(note). raw=\(String(describing: raw))\n".utf8))
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
