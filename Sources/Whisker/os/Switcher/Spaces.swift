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

/// Read-only view of Mission Control Spaces for a SPECIFIC display, via private
/// CGS APIs. Returns conservative defaults (1 space, index 0) if the private call
/// fails or its shape changed.
///
/// `CGSCopyManagedDisplaySpaces` returns one dict per display, each with a
/// "Display Identifier" (the display's UUID string, or "Main"), a "Spaces" array
/// and a "Current Space" dict. We pick the dict matching the requested display so
/// a multi-monitor setup shows only the focused monitor's desktops.
@MainActor
enum Spaces {
    private static var didDump = false

    /// (count, currentIndex) of user desktops on `displayID`.
    static func snapshot(displayID: CGDirectDisplayID) -> (count: Int, currentIndex: Int) {
        let cid = CGSMainConnectionID()
        guard let raw = CGSCopyManagedDisplaySpaces(cid) as? [Any] else {
            dumpOnce("CGSCopyManagedDisplaySpaces returned nil/non-array")
            return (1, 0)
        }

        let wantUUID = displayUUIDString(displayID)
        let isMain = (displayID == CGMainDisplayID())

        // Find the display dict for the requested monitor.
        var chosen: [String: Any]?
        for case let disp as [String: Any] in raw {
            let ident = disp["Display Identifier"] as? String
            if let ident, ident == wantUUID || (isMain && ident == "Main") {
                chosen = disp; break
            }
        }
        // Fallbacks: single display → use it; else the "Main" dict; else first.
        if chosen == nil {
            if raw.count == 1 { chosen = raw.first as? [String: Any] }
            else {
                for case let disp as [String: Any] in raw
                    where (disp["Display Identifier"] as? String) == "Main" { chosen = disp; break }
                chosen = chosen ?? (raw.first as? [String: Any])
            }
        }

        guard let disp = chosen, let spaceList = disp["Spaces"] as? [Any] else {
            dumpOnce("no display dict / Spaces for displayID \(displayID) uuid \(wantUUID ?? "nil")")
            return (1, 0)
        }

        // User (non-fullscreen) spaces only — "type" 0 — so numbering matches the
        // desktops in Mission Control and the Ctrl+←/→ stepping order.
        var ids: [Int] = []
        for case let s as [String: Any] in spaceList {
            if let type = s["type"] as? Int, type != 0 { continue }
            if let id = (s["ManagedSpaceID"] as? Int) ?? (s["id64"] as? Int) { ids.append(id) }
        }
        var currentID: Int?
        if let cur = disp["Current Space"] as? [String: Any] {
            currentID = (cur["ManagedSpaceID"] as? Int) ?? (cur["id64"] as? Int)
        }

        if ids.count <= 1 { dumpOnce("parsed \(ids.count) user space(s) for displayID \(displayID)") }

        let count = max(ids.count, 1)
        let idx = currentID.flatMap { ids.firstIndex(of: $0) } ?? 0
        return (count, idx)
    }

    /// CGS "Display Identifier" UUID string for a CoreGraphics display id.
    private static func displayUUIDString(_ id: CGDirectDisplayID) -> String? {
        guard let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() else { return nil }
        return CFUUIDCreateString(nil, uuid) as String?
    }

    /// One-time diagnostic dump to stderr (visible via `swift run Whisker`).
    private static func dumpOnce(_ note: String) {
        guard !didDump else { return }
        didDump = true
        let raw = CGSCopyManagedDisplaySpaces(CGSMainConnectionID())
        FileHandle.standardError.write(Data(
            "whisker Spaces: \(note). raw=\(String(describing: raw))\n".utf8))
    }
}

/// Numbered desktop tiles for the monitor under the mouse. Commit steps
/// Ctrl+←/→ to the target desktop on that monitor.
@MainActor
final class SpacesSource: SwitcherSource {
    let category: SwitcherCategory = .desktops
    var isAvailable: Bool { true }

    private var count = 1
    private var current = 0

    func items() -> [SwitcherItem] {
        let snap = Spaces.snapshot(displayID: Self.displayUnderMouse())
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

    /// CGDirectDisplayID of the screen the mouse is currently on.
    private static func displayUnderMouse() -> CGDirectDisplayID {
        let m = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(m, $0.frame, false) }) ?? NSScreen.main
        if let num = screen?.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber {
            return num.uint32Value
        }
        return CGMainDisplayID()
    }
}
