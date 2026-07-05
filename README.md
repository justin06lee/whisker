# Whisker

Mouse-only macOS control, built to run alongside [Wispr Flow](https://wisprflow.ai) (which handles voice dictation / typing). Wispr is bound to mouse button 5; Whisker uses only the left, right, middle buttons and the scroll wheel — no conflict by design.

The goal: do everything the keyboard does *except typing* without touching the keyboard.

## Gestures

| Gesture | Action |
|---|---|
| Hold right-click (~150ms) | Open **Radial 1** — release toward a button to fire it: Enter · Escape · Tab · ⌘S · ⌘F · ⌘P |
| Scroll while holding right | **Switcher HUD** — cycle Apps / Windows / Desktops / Tabs, release to commit (scroll up seeds Apps, down seeds Desktops) |
| Right-drag flick (before the hold threshold) | **Motion gesture** — left/right = Back/Forward (⌘[ / ⌘]), up/down = scroll to top/bottom (Home/End). Toggleable |
| Quick left-click while holding right | ⌘-click (multi-select) |
| Held left-click while holding right | ⇧-click (range select) |
| Double-right-click | Open **Radial 2** — click a button: ⌘T · ⌘N · ⌘W · **Menu palette** (right-click to dismiss) |
| Middle-click + drag | Region screenshot → clipboard + Desktop |
| Highlight text | Auto-copies to clipboard (toggleable); floating buttons to cut / copy / delete |
| Click in a text field | Floating buttons: delete-character / paste |
| Quick right-click (tap) | Passes through to the native context menu |

### Switcher HUD

Hold right + scroll opens a ⌘Tab-style HUD with four dimensions. Apps drives the *real* macOS ⌘Tab switcher; Windows lists every regular app's windows (frontmost app first); Desktops jumps Mission Control Spaces with a fast slide (greyed out if the private CGS API ever changes); Tabs lists browser tabs (Safari, Chrome, Edge, Brave, Arc, Vivaldi — needs the **Automation** permission: the packaged app declares `NSAppleEventsUsageDescription` in its Info.plist so macOS shows the consent prompt on first use; if you ever denied it, re-enable Whisker under Privacy & Security ▸ Automation).

### Command palette

Radial 2 ▸ **Menu** opens a Spotlight-style palette of the frontmost app's entire menu bar. Type (keyboard or Wispr) to filter, click or press Enter to run the command. Covers the app-specific long-tail without hardcoding shortcuts.

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

The menu-bar icon's menu has toggles for auto-copy-on-highlight and motion gestures, plus tunable hold/double-click thresholds (changes apply immediately).

## Packaging a `.app` / DMG

```bash
scripts/make-signing-cert.sh   # run ONCE — creates a stable self-signed signing identity
scripts/build-dmg.sh           # builds build/Whisker.app and build/Whisker.dmg
```

### Why `make-signing-cert.sh` matters (Accessibility re-prompt fix)

macOS ties an Accessibility grant to the app's code-signing **designated requirement**. An *ad-hoc* signature (`codesign -s -`) has no stable identity — its requirement is the exact binary hash, which changes on **every rebuild** — so macOS treats each new build as a different app and re-asks for Accessibility, leaving stale (still-checked-but-dead) entries behind. `make-signing-cert.sh` creates a self-signed code-signing certificate; `build-dmg.sh` then signs every build with it, producing a **constant** requirement (`identifier "dev.justin06lee.whisker" and certificate leaf = H"…"`) so the grant **persists across rebuilds**. No Apple Developer account needed. (The cert is untrusted, so first launch of a fresh install still needs right-click → Open for Gatekeeper — that's separate from Accessibility.)

### One-time cleanup when switching from old ad-hoc builds

If you previously ran ad-hoc builds, macOS has stale Accessibility entries. Reset once:

```bash
tccutil reset Accessibility dev.justin06lee.whisker
```

Then remove any leftover "Whisker" rows in **Privacy & Security ▸ Accessibility**, launch the newly signed app, and grant **once**. Future rebuilds keep the grant.

### Notarized distribution (optional, needs an Apple Developer account)

To ship builds that strangers can open without right-click → Open, sign with a Developer ID certificate and notarize:

```bash
scripts/build-dmg.sh
SIGN_ID="Developer ID Application: Your Name (TEAMID)" scripts/notarize.sh
```

See the header of `scripts/notarize.sh` for the one-time credential setup.

## Tests

```bash
swift test
```

The gesture state machine and radial hit-testing are covered by unit tests; the OS-interaction layers are verified manually on a live macOS session.

## Status

v2: everything from the v1 spec plus the phase-2 items — the switcher HUD, mouse-motion gestures, and the searchable command palette. Remaining ideas: per-window/per-desktop thumbnails (blocked on macOS not exposing other Spaces' contents without capture), palette fuzzy-ranking, more browsers.
