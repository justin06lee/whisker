# Whisker

Mouse-only macOS control, built to run alongside [Wispr Flow](https://wisprflow.ai) (which handles voice dictation / typing). Wispr is bound to mouse button 5; Whisker uses only the left, right, middle buttons and the scroll wheel — no conflict by design.

The goal: do everything the keyboard does *except typing* without touching the keyboard.

## Gestures

| Gesture | Action |
|---|---|
| Hold right-click (~150ms) | Open **Radial 1** — release toward a button to fire it: Enter · Escape · Tab · ⌘S · ⌘F · ⌘P |
| Scroll while holding right | Switch app (⌘Tab) |
| Quick left-click while holding right | ⌘-click (multi-select) |
| Held left-click while holding right | ⇧-click (range select) |
| Double-right-click | Open **Radial 2** — click a button: ⌘T · ⌘N · ⌘W (right-click to dismiss) |
| Middle-click + drag | Region screenshot → clipboard + Desktop |
| Highlight text | Auto-copies to clipboard (toggleable); floating buttons to cut / copy / delete |
| Click in a text field | Floating buttons: delete-character / paste |
| Quick right-click (tap) | Passes through to the native context menu |

## Architecture

A pure, timestamp-driven gesture **state machine** (`Sources/Whisker/gesture/`) has zero OS dependencies and is fully unit-tested. Thin macOS glue feeds it events and executes its output:

- `os/EventTap.swift` — `CGEventTap` intercepts mouse events, suppresses the ones Whisker consumes, and tags its own synthetic events to avoid feedback loops.
- `os/InputSynth.swift` — synthesizes keystrokes and modified clicks.
- `os/AXContext.swift` — reads focused-element / selection state via the Accessibility API.
- `os/Screenshot.swift` — region capture.
- `overlay/` — transparent `NSPanel` overlays render the radial menus and floating text buttons.

## Build & Run

```bash
swift build
swift run Whisker
```

Whisker shows in the Dock and the menu bar. On first launch, grant **Accessibility** access (Privacy & Security ▸ Accessibility) and relaunch. Region screenshots additionally require **Screen Recording** permission.

Toggle auto-copy-on-highlight from the menu-bar icon's menu.

## Packaging a `.app` / DMG

```bash
scripts/make-signing-cert.sh   # run ONCE — creates a stable self-signed signing identity
scripts/build-dmg.sh           # builds build/Whisker.app and build/Whisker.dmg
```

### Why `make-signing-cert.sh` matters (Accessibility re-prompt fix)

macOS ties an Accessibility grant to the app's code-signing **designated requirement**. An *ad-hoc* signature (`codesign -s -`) has no stable identity — its requirement is the exact binary hash, which changes on **every rebuild** — so macOS treats each new build as a different app and re-asks for Accessibility, leaving stale (still-checked-but-dead) entries behind. `make-signing-cert.sh` creates a self-signed code-signing certificate; `build-dmg.sh` then signs every build with it, producing a **constant** requirement (`identifier "sh.tenet.whisker" and certificate leaf = H"…"`) so the grant **persists across rebuilds**. No Apple Developer account needed. (The cert is untrusted, so first launch of a fresh install still needs right-click → Open for Gatekeeper — that's separate from Accessibility.)

### One-time cleanup when switching from old ad-hoc builds

If you previously ran ad-hoc builds, macOS has stale Accessibility entries. Reset once:

```bash
tccutil reset Accessibility sh.tenet.whisker
```

Then remove any leftover "Whisker" rows in **Privacy & Security ▸ Accessibility**, launch the newly signed app, and grant **once**. Future rebuilds keep the grant.

## Tests

```bash
swift test
```

The gesture state machine and radial hit-testing are covered by unit tests; the OS-interaction layers are verified manually on a live macOS session.

## Status

v1. Deferred to a later phase: mouse-motion gestures and a searchable command palette for app-specific shortcuts.
