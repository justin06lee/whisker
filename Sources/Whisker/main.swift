import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var eventTap: EventTap?
    private var overlay: OverlayController?
    private var switcher: SwitcherController?
    private var screenshot: ScreenshotController?
    private var textButtons: TextButtonsController?
    private var axPollTimer: Timer?
    private var onboarding: OnboardingController?
    private var lastSelectedText: String = ""
    private var settings = Settings.current
    private var autoCopyItem: NSMenuItem?
    private var motionItem: NSMenuItem?
    private var holdMenu: NSMenu?
    private var leftHoldMenu: NSMenu?
    private var doubleClickMenu: NSMenu?

    private var autoCopyOnHighlight: Bool { settings.autoCopyOnHighlight }

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

        let motion = NSMenuItem(title: "Mouse motion gestures",
                                action: #selector(toggleMotionGestures), keyEquivalent: "")
        motion.state = settings.motionGesturesEnabled ? .on : .off
        menu.addItem(motion)
        self.motionItem = motion

        menu.addItem(.separator())
        holdMenu = addThresholdSubmenu(
            to: menu, title: "Right-hold threshold",
            optionsMs: [100, 150, 200, 250], currentMs: Int(settings.holdThreshold * 1000),
            action: #selector(setHoldThreshold(_:)))
        leftHoldMenu = addThresholdSubmenu(
            to: menu, title: "Left-hold threshold (⇧-click)",
            optionsMs: [100, 150, 200, 250], currentMs: Int(settings.leftClickHoldThreshold * 1000),
            action: #selector(setLeftHoldThreshold(_:)))
        doubleClickMenu = addThresholdSubmenu(
            to: menu, title: "Double-click window",
            optionsMs: [250, 300, 400], currentMs: Int(settings.doubleClickInterval * 1000),
            action: #selector(setDoubleClickInterval(_:)))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Capture focus info (2s) → clipboard",
                                action: #selector(captureFocusInfo), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Whisker", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        if Permissions.accessibilityGranted(prompt: false) {
            startServices()
        } else {
            onboarding = OnboardingController { [weak self] in self?.startServices() }
            onboarding?.show()
        }
    }

    /// Creates and starts every Accessibility-dependent service: the overlay/screenshot
    /// controllers, the CGEventTap, the floating text-edit buttons, and the AX poll timer.
    /// Idempotent — guarded on `eventTap` so the onboarding poll (or a second call) can't
    /// spin up a second tap/timer.
    private func startServices() {
        guard eventTap == nil else { return }   // idempotent

        let overlay = OverlayController()
        let screenshot = ScreenshotController()
        self.overlay = overlay
        self.screenshot = screenshot

        let switcher = SwitcherController()
        self.switcher = switcher

        let tap = EventTap(settings: settings) { [weak self] actions in
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
                case let .openSwitcher(seed):
                    switcher.open(seed: seed, atGlobalPoint: NSEvent.mouseLocationCG())
                case let .switcherStep(forward):
                    switcher.step(forward: forward)
                case let .switcherClick(at: point):
                    switcher.click(atGlobalPoint: point)
                case .commitSwitcher:
                    switcher.commit()
                case .cancelSwitcher:
                    switcher.cancel()
                case let .motionGesture(direction):
                    switch direction {
                    case .left:  InputSynth.post(.back)
                    case .right: InputSynth.post(.forward)
                    case .up:    InputSynth.post(.home)
                    case .down:  InputSynth.post(.end)
                    }
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
        if !tap.start() {
            // Accessibility was revoked between the permission check and now (or the
            // tap failed for another reason). Stay alive and point at the fix.
            self.eventTap = nil
            let alert = NSAlert()
            alert.messageText = "Whisker couldn't start listening for mouse events"
            alert.informativeText = "Grant Accessibility access in System Settings ▸ Privacy & Security ▸ Accessibility, then relaunch Whisker."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Later")
            if alert.runModal() == .alertFirstButtonReturn {
                Permissions.openAccessibilitySettings()
            }
            return
        }

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
        // The synchronous AX read is dispatched to a background queue: AX queries are
        // cross-process IPC and can stall tens of ms each; keeping them off the main
        // thread is the primary fix for cursor-area jank. UI mutation hops back to the
        // main thread. The poll only needs the caret-bearing `Focus`; no mouse/bundle/
        // pid snapshots (those fallbacks were deleted — `captureFocusInfo` keeps its own).
        let axQueue = DispatchQueue(label: "whisker.ax", qos: .userInitiated)
        axPollTimer = Timer.scheduledTimer(withTimeInterval: 0.10, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard self != nil else { return }
                axQueue.async {
                    let focus = AXContext.current() // off-main: cross-process AX IPC
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            self?.applyFocus(focus)
                        }
                    }
                }
            }
        }
    }

    private func pointOnAnyScreen(_ p: CGPoint) -> Bool {
        NSScreen.screens.contains { $0.frame.contains(p) }
    }

    @MainActor
    private func applyFocus(_ focus: AXContext.Focus) {
        // Auto-copy a newly-appeared non-empty selection (independent of button display).
        if autoCopyOnHighlight, focus.hasSelection, focus.selectedText != lastSelectedText {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(focus.selectedText, forType: .string)
        }
        lastSelectedText = focus.selectedText

        // Show ONLY at a usable on-screen caret. A caret rect from AXBoundsForRange means
        // the element is an editable text location; absence means "not a text spot" -> hide.
        if let anchor = caretAnchor(focus.caretRect, hasSelection: focus.hasSelection) {
            let set: [TextEditButton] = focus.hasSelection
                ? [.deleteSelection, .cut, .copy]
                : [.deleteChar, .paste]
            textButtons?.show(set, atCocoaPoint: anchor)
        } else {
            textButtons?.hide()
        }
    }

    /// Bottom-left (Cocoa-global) where the buttons should sit: just ABOVE the caret line.
    /// Returns nil if there is no caret or it doesn't land on a real screen.
    private func caretAnchor(_ caret: CGRect?, hasSelection: Bool) -> CGPoint? {
        guard let r = caret else { return nil }
        let panelW = CGFloat(hasSelection ? 3 : 2) * 44
        let panelH: CGFloat = 40
        let gap: CGFloat = hasSelection ? 10 : 4   // selection sits slightly higher
        let top = Coords.cocoaGlobal(fromCG: CGPoint(x: r.minX, y: r.minY))
        guard pointOnAnyScreen(top) else { return nil }
        var y = top.y + gap
        if y + panelH > Coords.primaryHeight() {                 // would clip top of screen
            let bottom = Coords.cocoaGlobal(fromCG: CGPoint(x: r.minX, y: r.maxY))
            y = bottom.y - gap - panelH                          // place just below the line
        }
        _ = panelW
        return CGPoint(x: top.x, y: y)
    }

    // Defensive: even though Whisker has no persistent windows today, this keeps
    // the app alive if a transient window (alert, future settings sheet) is closed.
    // Cmd+Q from the Dock still terminates normally.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    @MainActor @objc private func toggleAutoCopy() {
        settings.autoCopyOnHighlight.toggle()
        settingsChanged()
        autoCopyItem?.state = settings.autoCopyOnHighlight ? .on : .off
    }

    @MainActor @objc private func toggleMotionGestures() {
        settings.motionGesturesEnabled.toggle()
        settingsChanged()
        motionItem?.state = settings.motionGesturesEnabled ? .on : .off
    }

    @MainActor @objc private func setHoldThreshold(_ sender: NSMenuItem) {
        settings.holdThreshold = Double(sender.tag) / 1000
        settingsChanged()
        refreshCheckmarks(in: holdMenu, selectedMs: sender.tag)
    }

    @MainActor @objc private func setLeftHoldThreshold(_ sender: NSMenuItem) {
        settings.leftClickHoldThreshold = Double(sender.tag) / 1000
        settingsChanged()
        refreshCheckmarks(in: leftHoldMenu, selectedMs: sender.tag)
    }

    @MainActor @objc private func setDoubleClickInterval(_ sender: NSMenuItem) {
        settings.doubleClickInterval = Double(sender.tag) / 1000
        settingsChanged()
        refreshCheckmarks(in: doubleClickMenu, selectedMs: sender.tag)
    }

    /// Persist the new settings and push them into the live gesture machine.
    private func settingsChanged() {
        settings.save()
        eventTap?.apply(settings: settings)
    }

    /// Build a "<title> ▸ 100 ms / 150 ms / …" radio submenu; returns the submenu
    /// so the checkmarks can be refreshed on selection. Values ride in `tag` (ms).
    private func addThresholdSubmenu(to menu: NSMenu, title: String, optionsMs: [Int],
                                     currentMs: Int, action: Selector) -> NSMenu {
        let sub = NSMenu()
        for ms in optionsMs {
            let item = NSMenuItem(title: "\(ms) ms", action: action, keyEquivalent: "")
            item.tag = ms
            item.state = ms == currentMs ? .on : .off
            sub.addItem(item)
        }
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        parent.submenu = sub
        menu.addItem(parent)
        return sub
    }

    private func refreshCheckmarks(in menu: NSMenu?, selectedMs: Int) {
        menu?.items.forEach { $0.state = $0.tag == selectedMs ? .on : .off }
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
        if let url = Bundle.main.url(forResource: "menubar", withExtension: "png") {
            img = NSImage(contentsOf: url)
        }
        // SwiftPM dev runs (`swift run`): the resource lives in Bundle.module.
        if img == nil, let url = Bundle.module.url(forResource: "menubar", withExtension: "png") {
            img = NSImage(contentsOf: url)
        }
        // Last-ditch dev fallback: load from the user's Pictures folder.
        if img == nil {
            img = NSImage(contentsOfFile: ("~/Pictures/pfp/whisker_taskbar.png" as NSString).expandingTildeInPath)
        }
        guard let base = img else { return nil }
        let size = NSSize(width: 18, height: 18)
        let resized = NSImage(size: size)
        resized.lockFocus()
        base.draw(in: NSRect(origin: .zero, size: size),
                  from: NSRect(origin: .zero, size: base.size),
                  operation: .sourceOver, fraction: 1.0)
        resized.unlockFocus()
        // Monochrome (white whiskers on transparent) -> template so macOS tints
        // it to match the menu bar (dark on light, light on dark). Without this
        // the white glyph is invisible on a light menu bar.
        resized.isTemplate = true
        return resized
    }
}

extension NSEvent {
    /// Current mouse location in CG-global (top-left origin) coordinates.
    @MainActor
    static func mouseLocationCG() -> CGPoint {
        let m = NSEvent.mouseLocation                  // Cocoa-global (bottom-left)
        return CGPoint(x: m.x, y: Coords.primaryHeight() - m.y)
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular) // show in Dock; status item still coexists
let delegate = AppDelegate()
app.delegate = delegate
app.run()
