import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var eventTap: EventTap?
    private var overlay: OverlayController?
    private var screenshot: ScreenshotController?
    private var textButtons: TextButtonsController?
    private var axPollTimer: Timer?
    private var followTimer: Timer?
    private var lastMouse: CGPoint = .zero
    private var lastSelectedText: String = ""
    private var autoCopyOnHighlight = Settings.current.autoCopyOnHighlight
    private var autoCopyItem: NSMenuItem?

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "🐱"

        let menu = NSMenu()
        let copyItem = NSMenuItem(title: "Auto-copy on highlight",
                                  action: #selector(toggleAutoCopy), keyEquivalent: "")
        copyItem.state = autoCopyOnHighlight ? .on : .off
        menu.addItem(copyItem)
        self.autoCopyItem = copyItem
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
        axPollTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard self != nil else { return }
                let mouse = NSEvent.mouseLocation   // main-thread snapshot
                axQueue.async {
                    let focus = AXContext.current() // off-main: cross-process AX IPC
                    DispatchQueue.main.async {
                        MainActor.assumeIsolated {
                            self?.applyFocus(focus, mouseLocation: mouse)
                        }
                    }
                }
            }
        }

        // Smoothly follow the cursor at ~60fps while it moves fast; freeze when it slows
        // so the offset buttons stay clickable (following during a click-approach would
        // push them away). Only reads NSEvent.mouseLocation — no AX IPC — so it's cheap.
        followTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 60.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, let buttons = self.textButtons, buttons.isVisible else {
                    self?.lastMouse = NSEvent.mouseLocation
                    return
                }
                let mouse = NSEvent.mouseLocation
                let dx = mouse.x - self.lastMouse.x
                let dy = mouse.y - self.lastMouse.y
                self.lastMouse = mouse
                let dist = (dx * dx + dy * dy).squareRoot()
                if dist > 6 {   // ~360 px/s at 60fps; fast move = glide, slow/aim = freeze. Tunable.
                    buttons.reposition(toCocoaPoint: mouse)
                }
            }
        }
    }

    @MainActor
    private func applyFocus(_ focus: AXContext.Focus, mouseLocation mouse: CGPoint) {
        // Auto-copy on a newly-appeared non-empty selection.
        if autoCopyOnHighlight, focus.hasSelection, focus.selectedText != lastSelectedText {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.setString(focus.selectedText, forType: .string)
        }
        lastSelectedText = focus.selectedText

        // Show/hide the floating buttons.
        if focus.isTextField {
            let set: [TextEditButton] = focus.hasSelection
                ? [.deleteSelection, .cut, .copy]
                : [.deleteChar, .paste]
            textButtons?.show(set, atCocoaPoint: mouse)
        } else {
            textButtons?.hide()
        }
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

    @MainActor @objc private func quit() { NSApp.terminate(nil) }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular) // show in Dock; status item still coexists
let delegate = AppDelegate()
app.delegate = delegate
app.run()
