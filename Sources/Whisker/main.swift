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
                let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier
                axQueue.async {
                    let focus = AXContext.current() // off-main: cross-process AX IPC
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            self?.applyFocus(focus, mouseLocation: mouse, frontmostBundleID: bundleID, frontmostPID: pid)
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

    private func pointOnAnyScreen(_ p: CGPoint) -> Bool {
        NSScreen.screens.contains { $0.frame.contains(p) }
    }

    @MainActor
    private func applyFocus(_ focus: AXContext.Focus,
                            mouseLocation mouse: CGPoint,
                            frontmostBundleID bundleID: String?,
                            frontmostPID pid: pid_t?) {
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
            let anchor = anchorPoint(focus: focus, terminal: terminal, pid: pid, mouse: mouse)
            textButtons?.show(set, atCocoaPoint: anchor)
        } else {
            textButtons?.hide()
        }
    }

    /// Top-right corner of the frontmost on-screen window for `pid`, converted to the
    /// Cocoa-global bottom-left point where a panel of the given size should sit (inset inside).
    /// Uses CGWindowList (works even for GPU-rendered apps with no AX). Returns nil if unavailable.
    private func windowAnchor(pid: pid_t?, panelWidth: CGFloat, panelHeight: CGFloat) -> CGPoint? {
        guard let pid else { return nil }
        let opts: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(opts, kCGNullWindowID) as? [[String: Any]] else { return nil }
        var best: CGRect?
        var bestArea: CGFloat = 0
        for info in list {
            guard let owner = info[kCGWindowOwnerPID as String] as? pid_t, owner == pid else { continue }
            let layer = (info[kCGWindowLayer as String] as? Int) ?? 0
            guard layer == 0 else { continue }
            guard let boundsDict = info[kCGWindowBounds as String],
                  let rect = CGRect(dictionaryRepresentation: boundsDict as! CFDictionary) else { continue }
            let area = rect.width * rect.height
            if area > bestArea { bestArea = area; best = rect }
        }
        guard let f = best else { return nil }
        let topRight = Coords.cocoaGlobal(fromCG: CGPoint(x: f.maxX, y: f.minY))
        let pt = CGPoint(x: topRight.x - panelWidth - 12, y: topRight.y - panelHeight - 12)
        return pointOnAnyScreen(pt) ? pt : nil
    }

    /// Where the floating buttons' bottom-left should sit (Cocoa-global).
    /// Chain: (non-terminal) sane on-screen caret → element/window frame top-right →
    /// frontmost-window top-right (CGWindowList) → mouse. Terminals skip the caret.
    private func anchorPoint(focus: AXContext.Focus, terminal: Bool, pid: pid_t?, mouse: CGPoint) -> CGPoint {
        let panelW = CGFloat(focus.hasSelection ? 3 : 2) * 44
        let panelH: CGFloat = 40
        let gap: CGFloat = focus.hasSelection ? 10 : 4   // selection sits slightly higher

        // 1) Caret (non-terminal only), if it maps onto a real screen.
        if !terminal, let r = focus.caretRect {
            let top = Coords.cocoaGlobal(fromCG: CGPoint(x: r.minX, y: r.minY))
            var y = top.y + gap
            if y + panelH > Coords.primaryHeight() {
                let bottom = Coords.cocoaGlobal(fromCG: CGPoint(x: r.minX, y: r.maxY))
                y = bottom.y - gap - panelH
            }
            let pt = CGPoint(x: top.x, y: y)
            if pointOnAnyScreen(pt) { return pt }
        }
        // 2) Focused element / window frame top-right (stable).
        if let f = focus.elementFrame {
            let topRight = Coords.cocoaGlobal(fromCG: CGPoint(x: f.maxX, y: f.minY))
            let pt = CGPoint(x: topRight.x - panelW - 12, y: topRight.y - panelH - 12)
            if pointOnAnyScreen(pt) { return pt }
        }
        // 3) Frontmost window via CGWindowList (works for GPU terminals).
        if let pt = windowAnchor(pid: pid, panelWidth: panelW, panelHeight: panelH) {
            return pt
        }
        // 4) Last resort: near the mouse.
        return CGPoint(x: mouse.x, y: mouse.y + 28)
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
                let bundle = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
                let ax = AXContext.debugSnapshot(frontmostBundleID: bundle)
                let focus = AXContext.current()
                let mouse = NSEvent.mouseLocation
                let screens = NSScreen.screens.map { s in
                    "\(NSStringFromRect(s.frame))\(s.frame.origin == .zero ? " [primary]" : "")"
                }.joined(separator: "  |  ")
                let caretLine: String
                if let r = focus.caretRect {
                    let cocoa = Coords.cocoaGlobal(fromCG: CGPoint(x: r.minX, y: r.minY))
                    caretLine = "caretCG=\(NSStringFromRect(r))  caretCocoa=\(NSStringFromPoint(cocoa))  onScreen=\(NSScreen.screens.contains { $0.frame.contains(cocoa) })"
                } else {
                    caretLine = "caretCG=nil"
                }
                let extra = """

                primaryHeight=\(Coords.primaryHeight())
                mouseCocoa=\(NSStringFromPoint(mouse))
                screens=\(screens)
                \(caretLine)
                """
                let pb = NSPasteboard.general
                pb.clearContents()
                pb.setString(ax + extra, forType: .string)
                NSSound.beep()
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
