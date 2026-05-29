import AppKit

@MainActor
final class OnboardingController {
    private var window: NSWindow?
    private var pollTimer: Timer?
    private var statusLabel: NSTextField?
    private let onGranted: () -> Void

    init(onGranted: @escaping () -> Void) { self.onGranted = onGranted }

    func show() {
        let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
                         styleMask: [.titled, .closable],
                         backing: .buffered, defer: false)
        w.title = "Whisker"
        w.isReleasedWhenClosed = false
        w.center()

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let icon = Self.appIcon() {
            let iv = NSImageView(image: icon)
            iv.translatesAutoresizingMaskIntoConstraints = false
            iv.widthAnchor.constraint(equalToConstant: 96).isActive = true
            iv.heightAnchor.constraint(equalToConstant: 96).isActive = true
            stack.addArrangedSubview(iv)
        }

        let title = NSTextField(labelWithString: "Welcome to Whisker")
        title.font = .systemFont(ofSize: 22, weight: .bold)
        stack.addArrangedSubview(title)

        let body = NSTextField(wrappingLabelWithString:
            "Whisker lets you drive your Mac with mouse gestures — a radial menu, floating text-edit buttons, and drag-to-screenshot — so you can do everything but typing without the keyboard.\n\nTo work, Whisker needs Accessibility access: it reads which text field is focused and synthesizes clicks and keystrokes. Grant access below — Whisker continues automatically once you do.")
        body.font = .systemFont(ofSize: 13)
        body.alignment = .center
        body.translatesAutoresizingMaskIntoConstraints = false
        body.widthAnchor.constraint(equalToConstant: 440).isActive = true
        stack.addArrangedSubview(body)

        let grant = NSButton(title: "Open Accessibility Settings", target: self, action: #selector(openSettings))
        grant.bezelStyle = .rounded
        grant.controlSize = .large
        grant.keyEquivalent = "\r"
        stack.addArrangedSubview(grant)

        let status = NSTextField(labelWithString: "Waiting for permission…")
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        stack.addArrangedSubview(status)
        statusLabel = status

        let quit = NSButton(title: "Quit", target: self, action: #selector(quitApp))
        quit.isBordered = false
        stack.addArrangedSubview(quit)

        let host = NSView()
        host.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: host.centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: host.leadingAnchor, constant: 40),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: host.trailingAnchor, constant: -40),
        ])
        w.contentView = host
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        window = w

        pollTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if Permissions.accessibilityGranted(prompt: false) { self.finish() }
            }
        }
    }

    @objc private func openSettings() {
        _ = Permissions.accessibilityGranted(prompt: true)   // adds Whisker to the list + system prompt
        Permissions.openAccessibilitySettings()
        statusLabel?.stringValue = "Enable Whisker in the list, then return here — it continues automatically."
    }

    @objc private func quitApp() { NSApp.terminate(nil) }

    private func finish() {
        pollTimer?.invalidate(); pollTimer = nil
        window?.close(); window = nil
        onGranted()
    }

    private static func appIcon() -> NSImage? {
        if let u = Bundle.main.url(forResource: "appicon", withExtension: "png"),
           let i = NSImage(contentsOf: u) { return i }
        if let u = Bundle.module.url(forResource: "appicon", withExtension: "png"),
           let i = NSImage(contentsOf: u) { return i }
        return NSImage(contentsOfFile: ("~/Pictures/pfp/whiskericon_bg.png" as NSString).expandingTildeInPath)
    }
}
