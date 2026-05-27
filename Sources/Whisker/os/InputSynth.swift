// `@preconcurrency` downgrades CoreGraphics' missing-`Sendable` annotations to
// warnings. `CGEventSource`/`CGEvent` are non-Sendable CF types; under Swift 6
// strict concurrency, constructing and posting them here is otherwise flagged.
// The crossing is benign: these are stateless synchronous statics with no shared
// mutable state and no cross-actor hops — each call creates and posts its events
// entirely on the calling thread. (Matches the EventTap task's approach.)
@preconcurrency import CoreGraphics

enum InputSynth {
    static func post(_ combo: KeyCombo) {
        let src = CGEventSource(stateID: .combinedSessionState)
        var flags: CGEventFlags = []
        if combo.command { flags.insert(.maskCommand) }
        if combo.shift { flags.insert(.maskShift) }
        let down = CGEvent(keyboardEventSource: src, virtualKey: combo.keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: combo.keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    static func modifiedClick(at point: CGPoint, command: Bool, shift: Bool) {
        let src = CGEventSource(stateID: .combinedSessionState)
        var flags: CGEventFlags = []
        if command { flags.insert(.maskCommand) }
        if shift { flags.insert(.maskShift) }
        let down = CGEvent(mouseEventSource: src, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left)
        let up = CGEvent(mouseEventSource: src, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    /// ⌘Tab step. v1 posts a full ⌘-press+Tab each step (good enough for adjacent switching).
    static func switchApp(forward: Bool) {
        let combo = KeyCombo(keyCode: 0x30, command: true, shift: !forward) // Tab, +Shift to go back
        post(combo)
    }
}
