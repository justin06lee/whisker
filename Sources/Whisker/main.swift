import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var eventTap: EventTap?
    private var overlay: OverlayController?
    private var screenshot: ScreenshotController?
    private var textButtons: TextButtonsController?
    private var axPollTimer: Timer?
    private var lastSelectedText: String = ""
    private var autoCopyOnHighlight = Settings.current.autoCopyOnHighlight
    private var autoCopyItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let icon = Self.menuBarIcon() {
            statusItem.button?.image = icon
        } else {
            statusItem.button?.title = "🐱"   // fallback
        }

        let menu = NSMenu()
        let copyItem = NSMenuItem(title: "Auto-copy on highlight",
                                  action: #selector(toggleAutoCopy), keyEquivalent: "")
        copyItem.state = autoCopyOnHighlight ? .on : .off
        menu.addItem(copyItem)
        self.autoCopyItem = copyItem
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Capture focus info (2s) → clipboard",
                                action: #selector(captureFocusInfo), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Whisker", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        if !Permissions.accessibilityGranted(prompt: true) {
            let alert = NSAlert()
            alert.messageText = "Whisker needs Accessibility access"
            alert.informativeText = "Enable Whisker under Privacy & Security ▸ Accessibility, then relaunch."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Quit")
            if alert.runModal() == .alertFirstButtonReturn {
                Permissions.openAccessibilitySettings()
            }
            NSApp.terminate(nil)
            return
        }

        let overlay = OverlayController()
        let screenshot = ScreenshotController()
        self.overlay = overlay
        self.screenshot = screenshot

        let tap = EventTap(settings: .current) { [weak self] actions in
            guard self != nil else { return }
            for action in actions {
                switch action {
                case let .passThroughRightClick(at: point):
                    InputSynth.rightClick(at: point)
                case let .showRadial(kind, at: point):
                    overlay.showRadial(kind, atGlobalPoint: point)
                case .hideRadial:
                    overlay.hide()
                case let .selectRadial(at: point):
                    overlay.selectAndHide(atGlobalPoint: point)
                case let .switchAppStep(forward):
                    InputSynth.switchApp(forward: forward)
                case let .commandClick(at: point):
                    InputSynth.modifiedClick(at: point, command: true, shift: false)
                case let .shiftClick(at: point):
                    InputSynth.modifiedClick(at: point, command: false, shift: true)
                case .beginScreenshotRegion, .updateScreenshotRegion,
                     .commitScreenshotRegion, .cancelScreenshotRegion:
                    screenshot.handle(action)
                }
            }
        }
        self.eventTap = tap
        tap.start()

        let textButtons = TextButtonsController()
        self.textButtons = textButtons
        textButtons.onTap = { button in
            switch button {
            case .deleteChar, .deleteSelection:
                InputSynth.post(.delete)
            case .cut:   InputSynth.post(.cmd("x"))
            case .copy:  InputSynth.post(.cmd("c"))
            case .paste: InputSynth.post(.cmd("v"))
            }
        }

        // The scheduled timer fires on the main run loop, but its closure is not
        // statically main-actor-isolated under Swift 6. `MainActor.assumeIsolated`
        // recovers that isolation; it is sound here because the timer is scheduled
        // on the main run loop (same technique used in EventTap's C trampoline).
        //
        // We snapshot `NSEvent.mouseLocation` on the main thread (AppKit state is
        // main-actor-isolated under Swift 6; reading it here pairs the mouse coord
        // with a consistent baseline anyway) and then dispatch the synchronous AX
        // read to a background queue. AX queries are cross-process IPC and can
        // stall tens of ms each; keeping them off the main thread is the primary
        // fix for cursor-area jank. UI mutation hops back to the main thread.
        let axQueue = DispatchQueue(label: "whisker.ax", qos: .userInitiated)
        axPollTimer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard self != nil else { return }
                let mouse = NSEvent.mouseLocation   // main-thread snapshot
                let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                axQueue.async {
                    let focus = AXContext.current() // off-main: cross-process AX IPC
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            self?.applyFocus(focus, mouseLocation: mouse, frontmostBundleID: bundleID)
                        }
                    }
                }
            }
        }
    }

    // Frontmost-app bundle-id substrings that indicate a terminal emulator.
    private static let terminalHints = ["term", "iterm", "warp", "ghostty",
                                        "alacritty", "kitty", "wezterm", "hyper", "tabby"]
    private func isTerminal(_ bundleID: String?) -> Bool {
        guard let b = bundleID?.lowercased() else { return false }
        return Self.terminalHints.contains { b.contains($0) }
    }

    @MainActor
    private func applyFocus(_ focus: AXContext.Focus,
                            mouseLocation mouse: CGPoint,
                            frontmostBundleID bundleID: String?) {
        if autoCopyOnHighlight, focus.hasSelection, focus.selectedText != lastSelectedText {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(focus.selectedText, forType: .string)
        }
        lastSelectedText = focus.selectedText

        let terminal = isTerminal(bundleID)
        if focus.isTextField || terminal {
            let set: [TextEditButton] = focus.hasSelection
                ? [.deleteSelection, .cut, .copy]
                : [.deleteChar, .paste]
            textButtons?.show(set, atCocoaPoint: anchorPoint(caret: focus.caretRect, fallbackMouse: mouse))
        } else {
            textButtons?.hide()
        }
    }

    /// Where the floating buttons' bottom-left should sit (Cocoa-global coords).
    /// Anchored just above the caret line; flips to just below if it would run off
    /// the top of the screen. Falls back to just above the mouse pointer.
    private func anchorPoint(caret: CGRect?, fallbackMouse mouse: CGPoint) -> CGPoint {
        let gap: CGFloat = 4
        let panelHeight: CGFloat = 40
        if let r = caret, !(r.origin == .zero && r.size == .zero) {
            // r is CG-global (top-left origin). Caret line top -> Cocoa global.
            let lineTop = Coords.cocoaGlobal(fromCG: CGPoint(x: r.minX, y: r.minY))
            var y = lineTop.y + gap                       // panel bottom sits just above the line
            if y + panelHeight > Coords.primaryHeight() { // would clip the top of the screen
                let lineBottom = Coords.cocoaGlobal(fromCG: CGPoint(x: r.minX, y: r.maxY))
                y = lineBottom.y - gap - panelHeight       // place just below the line instead
            }
            return CGPoint(x: lineTop.x, y: y)
        }
        return CGPoint(x: mouse.x, y: mouse.y + 28)        // fallback near the pointer
    }

    // Defensive: even though Whisker has no persistent windows today, this keeps
    // the app alive if a transient window (alert, future settings sheet) is closed.
    // Cmd+Q from the Dock still terminates normally.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    @MainActor @objc private func toggleAutoCopy() {
        autoCopyOnHighlight.toggle()
        var s = Settings.current
        s.autoCopyOnHighlight = autoCopyOnHighlight
        s.save()
        autoCopyItem?.state = autoCopyOnHighlight ? .on : .off
    }

    @MainActor @objc private func captureFocusInfo() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            MainActor.assumeIsolated {
                let info = AXContext.debugSnapshot(
                    frontmostBundleID: NSWorkspace.shared.frontmostApplication?.bundleIdentifier)
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(info, forType: .string)
                NSSound.beep()   // audible cue that the snapshot was captured + copied
            }
        }
    }

    @MainActor @objc private func quit() { NSApp.terminate(nil) }

    private static func menuBarIcon() -> NSImage? {
        var img: NSImage?
        // Packaged .app: the raw PNG is copied into Contents/Resources by build-dmg.sh,
        // so Bundle.main finds it directly (and the .app stays code-signable). This is
        // the path that resolves in the signed, drag-installed build.
        if let url = Bundle.main.url(forResource: "whisker", withExtension: "png") {
            img = NSImage(contentsOf: url)
        }
        // SwiftPM dev runs (`swift run`): the resource lives in Bundle.module.
        if img == nil, let url = Bundle.module.url(forResource: "whisker", withExtension: "png") {
            img = NSImage(contentsOf: url)
        }
        // Last-ditch dev fallback: load from the user's Pictures folder.
        if img == nil {
            img = NSImage(contentsOfFile: ("~/Pictures/pfp/whisker.png" as NSString).expandingTildeInPath)
        }
        guard let base = img else { return nil }
        let size = NSSize(width: 18, height: 18)
        let resized = NSImage(size: size)
        resized.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: size),
                  from: NSRect(origin: .zero, size: base.size),
                  operation: .sourceOver, fraction: 1.0)
        resized.unlockFocus()
        resized.isTemplate = false   // keep the pfp in color
        return resized
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular) // show in Dock; status item still coexists
let delegate = AppDelegate()
app.delegate = delegate
app.run()
