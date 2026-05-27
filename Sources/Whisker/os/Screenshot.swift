import AppKit
import CoreGraphics

// `@MainActor`: this controller owns AppKit objects (`NSWindow`, `SelectionView`,
// `NSScreen`, `NSPasteboard`, `NSImage`) which are main-actor-isolated under Swift 6
// strict concurrency. Annotating the whole class keeps all access on the main actor;
// the main-actor action dispatcher (main.swift) reaches it without hops. Mirrors
// `OverlayController`.
@MainActor
final class ScreenshotController {
    private var origin: CGPoint?
    private var selectionWindow: NSWindow?
    private var selectionView: SelectionView?

    func handle(_ action: GestureAction) {
        switch action {
        case let .beginScreenshotRegion(at: p): begin(at: p)
        case let .updateScreenshotRegion(to: p): update(to: p)
        case let .commitScreenshotRegion(to: p): commit(to: p)
        case .cancelScreenshotRegion: cancel()
        default: break
        }
    }

    private func begin(at p: CGPoint) {
        origin = p
        guard let screen = NSScreen.main else { return }
        let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless],
                         backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.level = .statusBar
        w.ignoresMouseEvents = true
        let v = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        w.contentView = v
        w.orderFrontRegardless()
        selectionWindow = w; selectionView = v
    }

    private func update(to p: CGPoint) {
        guard let origin, let screen = NSScreen.main else { return }
        selectionView?.rect = cocoaRect(origin, p, screen: screen)
        selectionView?.needsDisplay = true
    }

    private func commit(to p: CGPoint) {
        defer { cancel() }
        guard let origin else { return }
        let rect = cgRect(origin, p)   // top-left origin, what CGDisplay capture wants
        capture(rect)
    }

    private func cancel() {
        selectionWindow?.orderOut(nil); selectionWindow = nil; selectionView = nil; origin = nil
    }

    private func capture(_ rect: CGRect) {
        guard rect.width > 4, rect.height > 4 else { return }
        guard let image = CGDisplayCreateImage(CGMainDisplayID(), rect: rect) else { return }
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { return }
        // Clipboard
        let pb = NSPasteboard.general; pb.clearContents()
        pb.writeObjects([NSImage(cgImage: image, size: .zero)])
        // Desktop file
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Desktop/Whisker-\(Int(Date().timeIntervalSince1970)).png")
        try? png.write(to: url)
    }

    private func cgRect(_ a: CGPoint, _ b: CGPoint) -> CGRect {
        CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
    }

    private func cocoaRect(_ a: CGPoint, _ b: CGPoint, screen: NSScreen) -> CGRect {
        let r = cgRect(a, b)
        return CGRect(x: r.minX, y: screen.frame.height - r.maxY, width: r.width, height: r.height)
    }
}

@MainActor
final class SelectionView: NSView {
    var rect: CGRect = .zero

    override func draw(_ dirtyRect: NSRect) {
        NSColor.systemBlue.withAlphaComponent(0.2).setFill()
        NSColor.systemBlue.setStroke()
        let path = NSBezierPath(rect: rect); path.fill(); path.lineWidth = 2; path.stroke()
    }
}
