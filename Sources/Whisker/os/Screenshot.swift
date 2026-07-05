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
    private var targetScreen: NSScreen?
    private var targetDisplayID: CGDirectDisplayID = CGMainDisplayID()
    private static var didPromptScreenRecording = false

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
        // CGDisplayCreateImage is gated by the Screen Recording TCC permission;
        // without it captures silently contain only the wallpaper. Gate here so
        // the user never draws a selection that would be discarded.
        guard Self.screenCaptureGranted() else { promptForScreenRecordingOnce(); return }
        origin = p
        // `p` is in CG global (top-left origin) space. Pin the drag to the
        // display that actually contains it — NSScreen.main is the key window's
        // screen, which is unrelated to where the gesture happens.
        var display: CGDirectDisplayID = 0
        var count: UInt32 = 0
        if CGGetDisplaysWithPoint(p, 1, &display, &count) == .success, count > 0 {
            targetDisplayID = display
        } else {
            targetDisplayID = CGMainDisplayID()
        }
        let screen = NSScreen.screens.first {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?
                .uint32Value == targetDisplayID
        } ?? NSScreen.main
        guard let screen else { return }
        targetScreen = screen
        let w = NSWindow(contentRect: screen.frame, styleMask: [.borderless],
                         backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.level = .statusBar
        w.ignoresMouseEvents = true
        let v = SelectionView(frame: NSRect(origin: .zero, size: screen.frame.size))
        w.contentView = v
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary]
        w.orderFrontRegardless()
        selectionWindow = w; selectionView = v
    }

    private func update(to p: CGPoint) {
        guard let origin, let screen = targetScreen else { return }
        selectionView?.rect = cocoaRect(origin, p, screen: screen)
        selectionView?.needsDisplay = true
    }

    private func commit(to p: CGPoint) {
        defer { cancel() }
        guard let origin else { return }
        let rect = cgRect(origin, p)   // CG global, top-left origin
        capture(rect)
    }

    private func cancel() {
        selectionWindow?.orderOut(nil); selectionWindow = nil; selectionView = nil
        origin = nil; targetScreen = nil
    }

    private func capture(_ rect: CGRect) {
        guard rect.width > 4, rect.height > 4 else { return }
        // CGDisplayCreateImage's rect is in the target display's *local* space;
        // translate the CG-global rect by that display's global bounds origin.
        let bounds = CGDisplayBounds(targetDisplayID)
        let local = rect.offsetBy(dx: -bounds.minX, dy: -bounds.minY)
        guard let image = CGDisplayCreateImage(targetDisplayID, rect: local) else { return }
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

    /// CG global rect -> selection-window-local Cocoa rect. Flip through the
    /// primary screen height (the shared CG<->Cocoa anchor, see Coords.swift),
    /// then subtract the target screen's Cocoa frame origin. Flipping with the
    /// target screen's own height would only be correct on the primary display.
    private func cocoaRect(_ a: CGPoint, _ b: CGPoint, screen: NSScreen) -> CGRect {
        let r = cgRect(a, b)
        return CGRect(x: r.minX - screen.frame.minX,
                      y: (Coords.primaryHeight() - r.maxY) - screen.frame.minY,
                      width: r.width, height: r.height)
    }

    // MARK: - Screen Recording permission

    private static func screenCaptureGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    /// Handle a missing Screen Recording permission, once per launch. `begin`
    /// runs synchronously inside the CGEventTap callback; running a modal loop
    /// there stalls the tap until macOS disables it (tapDisabledByTimeout), so
    /// defer everything out of this stack (mirrors TabsSource.promptForAutomationOnce).
    private func promptForScreenRecordingOnce() {
        guard !Self.didPromptScreenRecording else { return }
        Self.didPromptScreenRecording = true
        DispatchQueue.main.async {
            // Registers Whisker in the Screen Recording pane and shows the
            // system prompt on first use; a no-op if already denied.
            CGRequestScreenCaptureAccess()
            Self.presentScreenRecordingAlert()
        }
    }

    private static func presentScreenRecordingAlert() {
        let alert = NSAlert()
        alert.messageText = "Whisker needs Screen Recording access to take screenshots"
        alert.informativeText = "Allow Whisker in System Settings ▸ Privacy & Security ▸ Screen Recording, then relaunch Whisker."
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Not Now")
        if alert.runModal() == .alertFirstButtonReturn,
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
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
