// `@preconcurrency` downgrades CoreGraphics' missing-`Sendable` annotations to
// warnings. `CGEventSource`/`CGEvent` are non-Sendable CF types; under Swift 6
// strict concurrency, constructing and posting them here is otherwise flagged.
// The crossing is benign: these are stateless synchronous statics with no shared
// mutable state and no cross-actor hops — each call creates and posts its events
// entirely on the calling thread. (Matches the EventTap task's approach.)
@preconcurrency import CoreGraphics
import Foundation

enum InputSynth {
    /// Marker stamped on every synthetic event so our own event tap ignores them (prevents feedback loops).
    static let syntheticMarker: Int64 = 0x5748_4B52 // "WHKR"

    static func post(_ combo: KeyCombo) {
        let src = CGEventSource(stateID: .combinedSessionState)
        var flags: CGEventFlags = []
        if combo.command { flags.insert(.maskCommand) }
        if combo.shift { flags.insert(.maskShift) }
        let down = CGEvent(keyboardEventSource: src, virtualKey: combo.keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: combo.keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        up?.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
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
        down?.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        up?.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    static func rightClick(at point: CGPoint) {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(mouseEventSource: src, mouseType: .rightMouseDown, mouseCursorPosition: point, mouseButton: .right)
        let up = CGEvent(mouseEventSource: src, mouseType: .rightMouseUp, mouseCursorPosition: point, mouseButton: .right)
        down?.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        up?.setIntegerValueField(.eventSourceUserData, value: syntheticMarker)
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    // MARK: - Native ⌘Tab app switcher driving
    //
    // We show the REAL macOS app switcher (pixel-perfect) by holding ⌘ down and
    // tapping Tab. ⌘ stays logically held (no keyUp) until commit/cancel, so the
    // switcher stays on screen and we can step through it. All events are tagged
    // so our own tap ignores them.

    private static let commandKey: CGKeyCode = 0x37
    private static let tabKey: CGKeyCode = 0x30
    private static let escapeKey: CGKeyCode = 0x35

    private static func tag(_ e: CGEvent?) { e?.setIntegerValueField(.eventSourceUserData, value: syntheticMarker) }

    /// Press and HOLD ⌘ (no release). Begins an app-switcher session.
    static func commandDown() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let e = CGEvent(keyboardEventSource: src, virtualKey: commandKey, keyDown: true)
        e?.flags = .maskCommand
        tag(e)
        e?.post(tap: .cgSessionEventTap)
    }

    /// Release ⌘ — commits the highlighted app in the switcher.
    static func commandUp() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let e = CGEvent(keyboardEventSource: src, virtualKey: commandKey, keyDown: false)
        e?.flags = []
        tag(e)
        e?.post(tap: .cgSessionEventTap)
    }

    /// Tab (forward) / ⇧Tab (back) with ⌘ held — steps the switcher highlight.
    static func tabStep(forward: Bool) {
        let src = CGEventSource(stateID: .combinedSessionState)
        var flags: CGEventFlags = .maskCommand
        if !forward { flags.insert(.maskShift) }
        let down = CGEvent(keyboardEventSource: src, virtualKey: tabKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: tabKey, keyDown: false)
        down?.flags = flags; up?.flags = flags
        tag(down); tag(up)
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }

    /// Escape with ⌘ held — dismisses the switcher WITHOUT switching apps.
    static func pressEscape() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: src, virtualKey: escapeKey, keyDown: true)
        let up = CGEvent(keyboardEventSource: src, virtualKey: escapeKey, keyDown: false)
        down?.flags = .maskCommand; up?.flags = .maskCommand
        tag(down); tag(up)
        down?.post(tap: .cgSessionEventTap)
        up?.post(tap: .cgSessionEventTap)
    }
}
