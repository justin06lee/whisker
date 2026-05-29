import AppKit
import CoreGraphics

/// Coordinate conversion between CG global space (top-left origin, used by
/// CGEvent.location and AX bounds) and Cocoa global space (bottom-left origin,
/// used by NSWindow/NSPanel/NSScreen frames).
///
/// The bridge is the PRIMARY screen height (the screen whose frame origin is
/// .zero). This is display-agnostic: points on secondary monitors convert
/// correctly because both coordinate systems are anchored to the primary display.
enum Coords {
    @MainActor
    static func primaryHeight() -> CGFloat {
        NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height
            ?? 0
    }

    /// CG global (top-left origin) -> Cocoa global (bottom-left origin).
    @MainActor
    static func cocoaGlobal(fromCG p: CGPoint) -> CGPoint {
        CGPoint(x: p.x, y: primaryHeight() - p.y)
    }
}
