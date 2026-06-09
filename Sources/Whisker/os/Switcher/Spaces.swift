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
@_silgen_name("CGSManagedDisplaySetCurrentSpace")
private func CGSManagedDisplaySetCurrentSpace(_ cid: CGSConnectionID, _ display: CFString, _ space: UInt64)

// Private CGS screen-transition API. Used to wrap the (instant) space-set in a
// WindowServer-driven slide, so jumping any distance is a single b-line sweep —
// just like Mission Control, but skipping the desktops in between.
//
// `CGSNewTransition` snapshots the current screen; we then change the active
// space; `CGSInvokeTransition` animates from the snapshot to the now-current
// screen; `CGSReleaseTransition` tears it down once the slide finishes.
private struct CGSTransitionSpec {
    var unknown1: UInt32 = 0
    var type: UInt32 = 0        // kCGSTransitionSlide = 4
    var option: UInt32 = 0      // direction (see below)
    var wid: UInt32 = 0         // 0 = entire workspace/screen
    var backColour: UnsafeMutablePointer<Float>? = nil
}
@_silgen_name("CGSNewTransition")
private func CGSNewTransition(_ cid: CGSConnectionID, _ spec: UnsafePointer<CGSTransitionSpec>, _ handle: UnsafeMutablePointer<Int32>) -> Int32
@_silgen_name("CGSInvokeTransition")
private func CGSInvokeTransition(_ cid: CGSConnectionID, _ handle: Int32, _ duration: Float) -> Int32
@_silgen_name("CGSReleaseTransition")
private func CGSReleaseTransition(_ cid: CGSConnectionID, _ handle: Int32) -> Int32

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

    /// User desktops on `displayID`: count, current index, the CGS ManagedSpaceIDs
    /// (in Mission Control order) and the CGS "Display Identifier" for that monitor.
    /// `spaceIDs`/`displayIdentifier` are what `setCurrentSpace` needs to jump directly.
    struct Snapshot {
        let count: Int
        let currentIndex: Int
        let spaceIDs: [UInt64]
        let displayIdentifier: String?
    }

    static func snapshot(displayID: CGDirectDisplayID) -> Snapshot {
        let cid = CGSMainConnectionID()
        guard let raw = CGSCopyManagedDisplaySpaces(cid) as? [Any] else {
            dumpOnce("CGSCopyManagedDisplaySpaces returned nil/non-array")
            return Snapshot(count: 1, currentIndex: 0, spaceIDs: [], displayIdentifier: nil)
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
            return Snapshot(count: 1, currentIndex: 0, spaceIDs: [], displayIdentifier: nil)
        }
        let identifier = disp["Display Identifier"] as? String

        // User (non-fullscreen) spaces only — "type" 0 — so numbering matches the
        // desktops in Mission Control and the left→right stepping order.
        var ids: [UInt64] = []
        for case let s as [String: Any] in spaceList {
            if let type = s["type"] as? Int, type != 0 { continue }
            if let id = (s["ManagedSpaceID"] as? Int) ?? (s["id64"] as? Int) { ids.append(UInt64(id)) }
        }
        var currentID: UInt64?
        if let cur = disp["Current Space"] as? [String: Any] {
            currentID = ((cur["ManagedSpaceID"] as? Int) ?? (cur["id64"] as? Int)).map(UInt64.init)
        }

        if ids.count <= 1 { dumpOnce("parsed \(ids.count) user space(s) for displayID \(displayID)") }

        let count = max(ids.count, 1)
        let idx = currentID.flatMap { ids.firstIndex(of: $0) } ?? 0
        return Snapshot(count: count, currentIndex: idx, spaceIDs: ids, displayIdentifier: identifier)
    }

    // kCGSTransitionSlide; direction lives in `option`. These private values are
    // stable across recent macOS but are the most OS-sensitive part — if the
    // slide ever looks wrong (direction/type), tune here.
    private static let transitionSlide: UInt32 = 4
    private static let directionLeft: UInt32 = 1    // content slides left (target is to the RIGHT)
    private static let directionRight: UInt32 = 2   // content slides right (target is to the LEFT)

    /// Animate to the target desktop by stepping through EVERY desktop in between,
    /// fast — so going 1→5 visibly flies past 2,3,4 (a real traverse) instead of a
    /// single slide that makes 1 and 5 look adjacent. `path` is the ordered list of
    /// ManagedSpaceIDs to land on, from the first neighbour up to and including the
    /// target. Each hop is a quick WindowServer slide; the whole fly-through is
    /// capped so long jumps stay snappy. Falls back to instant hops if transitions
    /// are unavailable.
    static func setCurrentSpaceTraverse(displayIdentifier: String, path: [UInt64], slideLeft: Bool) {
        guard !path.isEmpty else { return }
        let option = slideLeft ? directionLeft : directionRight
        // Short slices, back-to-back, so multiple hops blend into one fast sweep
        // rather than reading as separate hops. Whole traverse ≲ 0.22s.
        let step = Float(min(0.055, 0.22 / Double(path.count)))
        hop(displayIdentifier: displayIdentifier, path: path, option: option, step: step, i: 0)
    }

    /// One slide hop, then schedules the next once it finishes. A static helper
    /// (not a captured closure) so the dispatch block captures only Sendable values.
    private static func hop(displayIdentifier: String, path: [UInt64],
                            option: UInt32, step: Float, i: Int) {
        guard i < path.count else { return }
        let cid = CGSMainConnectionID()
        let display = displayIdentifier as CFString
        var spec = CGSTransitionSpec()
        spec.type = transitionSlide
        spec.option = option
        var handle: Int32 = 0
        let err = withUnsafePointer(to: &spec) { CGSNewTransition(cid, $0, &handle) }
        guard err == 0, handle != 0 else {
            // No transition available — set the rest instantly, landing on target.
            for id in path[i...] { CGSManagedDisplaySetCurrentSpace(cid, display, id) }
            return
        }
        CGSManagedDisplaySetCurrentSpace(cid, display, path[i])
        _ = CGSInvokeTransition(cid, handle, step)
        DispatchQueue.main.asyncAfter(deadline: .now() + Double(step)) {
            MainActor.assumeIsolated {
                _ = CGSReleaseTransition(cid, handle)
                hop(displayIdentifier: displayIdentifier, path: path, option: option, step: step, i: i + 1)
            }
        }
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
    private var spaceIDs: [UInt64] = []
    private var displayIdentifier: String?

    func items() -> [SwitcherItem] {
        let snap = Spaces.snapshot(displayID: Self.displayUnderMouse())
        count = snap.count
        current = snap.currentIndex
        spaceIDs = snap.spaceIDs
        displayIdentifier = snap.displayIdentifier
        let symbol = NSImage(systemSymbolName: "macwindow", accessibilityDescription: "Desktop")
        return (0..<count).map { i in
            SwitcherItem(icon: symbol, label: "Desktop \(i + 1)")
        }
    }

    func commit(index: Int) {
        let target = SwitcherSelection.clamp(index, count: count)
        guard target != current, spaceIDs.indices.contains(target),
              current < spaceIDs.count, let display = displayIdentifier else { return }
        // Walk every desktop from current to target so the slide flies past the
        // ones in between. Higher index = to the right → content slides left.
        let slideLeft = target > current
        let path: [UInt64] = slideLeft
            ? Array(spaceIDs[(current + 1)...target])
            : Array(spaceIDs[target..<current].reversed())
        Spaces.setCurrentSpaceTraverse(displayIdentifier: display, path: path, slideLeft: slideLeft)
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
