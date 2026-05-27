// `@preconcurrency` downgrades CoreGraphics' missing-`Sendable` annotations to
// warnings. `CGEvent` is a non-Sendable CF class, so passing it across the
// `MainActor.assumeIsolated` closure boundary in the C trampoline is flagged as an
// error under strict concurrency. The crossing is benign: `assumeIsolated` runs its
// body synchronously on the *same* (main) thread the trampoline is already on — no
// value actually escapes to another isolation domain. This is the pragmatic, sound
// resolution (mirrors how the Permissions task handled a similar Swift-6 wall).
@preconcurrency import CoreGraphics
import Foundation

/// Owns the CGEventTap, converts OS mouse events into `GestureEvent`s, runs the
/// pure `GestureMachine`, forwards the resulting actions to a callback, and
/// suppresses the right/middle events the machine consumes.
///
/// ## Concurrency (Swift 6 strict concurrency)
/// The C event-tap callback (`eventTapCallback`) must be a top-level function with
/// C calling convention — it cannot capture Swift context, so the `EventTap`
/// instance is threaded through `refcon` via `Unmanaged`.
///
/// `EventTap` is `@MainActor` because every entry point runs on the main run loop:
///   - `start()` is called from `applicationDidFinishLaunching` (main actor).
///   - We register the tap's run-loop source on `CFRunLoopGetCurrent()` while on
///     the main thread, so the `.cgSessionEventTap` callback is delivered on the
///     main run loop.
///   - The 60Hz `Timer` is scheduled on the main run loop.
/// Because the C trampoline therefore *always* runs on the main actor, it is sound
/// to recover that isolation with `MainActor.assumeIsolated` before touching the
/// instance. This avoids `nonisolated(unsafe)` escape hatches entirely: all mutable
/// state (`machine`, stored ports) stays fully actor-isolated.
@MainActor
final class EventTap {
    private var machine: GestureMachine
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tickTimer: Timer?
    private let onActions: ([GestureAction]) -> Void

    init(settings: Settings, onActions: @escaping ([GestureAction]) -> Void) {
        self.machine = GestureMachine(settings: settings)
        self.onActions = onActions
    }

    func start() {
        let mask: CGEventMask =
            (1 << CGEventType.rightMouseDown.rawValue) |
            (1 << CGEventType.rightMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDown.rawValue) |
            (1 << CGEventType.leftMouseUp.rawValue) |
            (1 << CGEventType.otherMouseDown.rawValue) |
            (1 << CGEventType.otherMouseUp.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue) |
            (1 << CGEventType.scrollWheel.rawValue)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: eventTapCallback,
            userInfo: refcon
        ) else {
            fatalError("Failed to create event tap — is Accessibility granted?")
        }
        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        tickTimer = Timer.scheduledTimer(withTimeInterval: 0.016, repeats: true) { [weak self] _ in
            // Timer fires on the main run loop; hop to the main actor explicitly so
            // the Swift 6 checker is satisfied (the timer closure is nonisolated).
            MainActor.assumeIsolated {
                guard let self else { return }
                let now = ProcessInfo.processInfo.systemUptime
                let actions = self.machine.handle(.tick(time: now))
                if !actions.isEmpty { self.onActions(actions) }
            }
        }
    }

    /// Re-enable the tap after macOS disables it (it disables taps whose callback
    /// runs too long, or on certain user input). Called from the C trampoline.
    func reEnable() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
    }

    /// Called by the C callback. Returns true if the event should be suppressed.
    func process(_ type: CGEventType, _ event: CGEvent) -> Bool {
        // Ignore our own synthetic events (tagged by InputSynth) so they never
        // re-enter the machine or get suppressed — prevents feedback loops.
        if event.getIntegerValueField(.eventSourceUserData) == InputSynth.syntheticMarker {
            return false
        }
        let now = ProcessInfo.processInfo.systemUptime
        let loc = event.location
        guard let gesture = Self.translate(type, at: loc, event: event, time: now) else { return false }

        // Capture the intercept flag BEFORE `handle` mutates state: the state when
        // the event ARRIVES decides ownership. A left-down in commandMode returns an
        // empty action list yet must still be suppressed.
        let wasInterceptingLeft = machine.isInterceptingLeftClicks
        let actions = machine.handle(gesture)
        if !actions.isEmpty { onActions(actions) }

        switch gesture {
        case .buttonDown(.right, _, _), .buttonUp(.right, _, _):
            return true   // always consumed; pass-through is re-synthesized on .passThroughRightClick
        case .buttonDown(.middle, _, _), .buttonUp(.middle, _, _):
            return true
        case .buttonDown(.left, _, _), .buttonUp(.left, _, _):
            return wasInterceptingLeft || !actions.isEmpty
        default:
            return false
        }
    }

    private static func translate(_ type: CGEventType, at loc: CGPoint, event: CGEvent, time: Double) -> GestureEvent? {
        switch type {
        case .rightMouseDown:  return .buttonDown(.right, at: loc, time: time)
        case .rightMouseUp:    return .buttonUp(.right, at: loc, time: time)
        case .leftMouseDown:   return .buttonDown(.left, at: loc, time: time)
        case .leftMouseUp:     return .buttonUp(.left, at: loc, time: time)
        case .otherMouseDown where event.getIntegerValueField(.mouseEventButtonNumber) == 2:
            return .buttonDown(.middle, at: loc, time: time)
        case .otherMouseUp where event.getIntegerValueField(.mouseEventButtonNumber) == 2:
            return .buttonUp(.middle, at: loc, time: time)
        case .leftMouseDragged, .otherMouseDragged:
            return .dragged(to: loc, time: time)
        case .scrollWheel:
            return .scrolled(deltaY: Double(event.getIntegerValueField(.scrollWheelEventDeltaAxis1)), time: time)
        default:
            return nil
        }
    }
}

/// Top-level C-convention trampoline. Cannot capture context; the `EventTap`
/// instance arrives via `refcon`. Runs on the main run loop (see EventTap doc
/// comment), so `MainActor.assumeIsolated` is sound here.
private func eventTapCallback(
    proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?
) -> Unmanaged<CGEvent>? {
    guard let refcon else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<EventTap>.fromOpaque(refcon).takeUnretainedValue()
    return MainActor.assumeIsolated {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            // macOS disabled the tap (callback too slow / user input). Re-enable it
            // so we keep receiving events, then pass the event through untouched.
            tap.reEnable()
            return Unmanaged.passUnretained(event)
        }
        let suppress = tap.process(type, event)
        return suppress ? nil : Unmanaged.passUnretained(event)
    }
}
