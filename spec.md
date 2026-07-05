# Whisker — Design Spec

Mouse-only computer control, used alongside Wispr Flow (which handles raw text dictation). Goal: do everything keyboard does *except typing* without touching the keyboard.

**Target:** macOS for v1 (build on Accessibility API + CGEventTap). Cross-platform abstraction deferred to later.

## Keyboard capability ranking (highest → lowest impact)

Impact = frequency of use × pain when lost. Wispr already covers raw text entry.

1. **Text editing & navigation** — cursor move, word/line jump, selection, delete, copy/cut/paste/undo. Constant; Wispr's blind spot.
2. **Confirm / dismiss** — Enter, Escape, Tab between fields, Space toggle/scroll. Hit on every dialog and form.
3. **App & window control** — switch app/window/tab, new/close tab, tiling, mission control.
4. **Universal shortcuts** — save, find, new, open, refresh, address bar.
5. **Modifier-held mouse actions** — shift-click range select, cmd-click multi/new-tab, opt-drag duplicate.
6. **App-specific long-tail** — per-app shortcuts (IDE, Figma, Slack). Infinite; needs search, not hardcoding.
7. **System controls** — volume, brightness, screenshot, lock, spotlight.

## Solutions

<!-- filled in iteratively, highest impact first -->

### #1 — Text editing & navigation

**Mechanism:** floating contextual buttons ("circles") that appear above the mouse / selection. Button set depends on state.

**State A — cursor in input box, nothing selected:**
- Trash can → deletes one character (backspace).
- Paste button → pastes clipboard at cursor.

**State B — text highlighted (selection exists):**
- Trash can → deletes the whole selection.
- Cut button → cut selection to clipboard.
- Copy button → copy selection to clipboard.

**Default mouse selection behavior (rely on native gestures):**
- Single click → place cursor.
- Double click → select word.
- Triple click → select line.
- Click-drag → free highlight.

**Auto-copy on highlight:** default **ON** — highlighting any text immediately copies it to clipboard. User-toggleable off in settings. Cut/copy buttons still available in State B for explicit control.

### Core mechanism — Hold-Right-Click command mode

The spine for #2+ . Right mouse button becomes dual-purpose:
- **Tap** (release before threshold) → native context menu, unchanged.
- **Hold past threshold** (~150ms, tunable) → enters *command mode*; native context menu suppressed for that press.
- In command mode: Radial 1 buttons appear; scroll = switch app; left-click sub-timer = multi/range select (see #5).
- **Mouse motions/gestures while held** → command shortcuts. Deferred to **phase 2** (discoverability + false-positive risk). Radial buttons are the primary interface.

Full gesture vocabulary consolidated at bottom.

### #2 — Confirm / dismiss

While in command mode, a radial/quick menu shows discrete buttons:
- **Enter** → submit / confirm focused control.
- **Escape** → cancel / close.
- **Tab** → next field; **Shift-Tab** variant → previous field.

**Decision: do NOT merge Enter and Tab.** Tab is benign navigation; Enter is committing (send, submit, confirm destructive). A silent tab→submit fallback causes invisible accidental commits. Three separate buttons; zero added risk.

### #3 — App & window control

- **Switch app** (⌘Tab) → hold right-click + scroll through apps; release on target. Or click the target directly.
- **Switch tab** → just click the tab itself (native).
- **New tab / window** (⌘T/⌘N) → **dropped from v1.** Browser-native convenience; not worth the surface.
- **Window tiling / snap, Mission Control, spaces** → defer to OS native (drag-to-edge, hot corners).

### #4 — Universal shortcuts (scoped down)

Dropped: ⌘T, ⌘N, ⌘L, ⌘O, refresh (browser-native or low-value). Kept set split across two radials (see master vocabulary at bottom).

### #5 — Modifier-held mouse clicks

Only multi-select / range-select kept. Opt-drag, opt-click, etc. dropped from v1 (rarely used).

While right-click is held past threshold (command mode), left-click gets a sub-timer:
- **Quick left-click** → ⌘-click (multi-select, add one item).
- **Held left-click** (past ~150ms, tunable) → ⇧-click (range select from anchor).

Threshold ~150ms not 50ms: human click jitter is 50-100ms; too-tight threshold misfires ⇧ for ⌘, and a wrong-anchor range-select grabs a huge unintended span. Reliable > fast.

Reuses the existing hold-escalates grammar — no new gesture introduced.

### #6 — App-specific long-tail

**Deferred to phase 2.** Needs a searchable command palette (click opens, Wispr filters, click to fire) — its own subsystem. v1 proves the gesture grammar first.

### #7 — System controls

Mostly dropped (volume/brightness/lock/spotlight all have native clickable paths). One kept:
- **Region screenshot** → **middle-mouse-button click + drag** selects a region and captures. Fast, dedicated, no menu.

---

## Radial selection model

- **Radial 1** (held open while right-click is down) → **release-to-select (pie menu)**: move toward a button, release right-click to fire the sector under the cursor. The right-release event carries the cursor point, so no separate cursor tracking is needed. Releasing in the centre dead zone fires nothing. Left-click while right is held remains ⌘/⇧-click multi-select — no conflict.
- **Radial 2** (opened by double-right-click; nothing held afterward) → **click-to-select**: left-click a button to fire it; left-click outside a button (or right/middle-click) dismisses it.

## Master gesture vocabulary (v1)

| Gesture | Action |
|---|---|
| Tap right-click | Native context menu (unchanged) |
| Hold right-click (~150ms) | Enter command mode → **Radial 1** |
| — Radial 1 buttons | Enter · Escape · Tab · ⌘S · ⌘F · ⌘P |
| — Scroll while right held | Open **Switcher HUD** (Apps / Windows / Desktops / Tabs); scroll up seeds Apps, down seeds Desktops |
| — Motion flick while right held | Command shortcut (shipped in v2; was phase 2) |
| — Quick left-click while right held | ⌘-click (multi-select, add one) |
| — Held left-click (~150ms) while right held | ⇧-click (range select) |
| Double-right-click | **Radial 2** (visually distinct): ⌘T · ⌘N · ⌘W · **Menu** |
| — Radial 2 **Menu** button | Open command palette (app-specific long-tail; shipped in v2) |
| Middle-click + drag | Region screenshot |
| Click in input box (no selection) | Floating buttons: 🗑 delete char · paste |
| Highlight text | Floating buttons: 🗑 delete selection · cut · copy |
| Single / double / triple click | Place cursor / select word / select line (native) |

## v1 scope summary

**In:** floating text-edit buttons (#1), command-mode radials for Enter/Esc/Tab + ⌘S/F/P (#2, #4), Switcher HUD via scroll (#3), multi/range select (#5), region screenshot (#7).
**Phase 2 — now shipped (v2):** mouse-motion gestures, command palette for app-specific long-tail (#6, via Radial 2's Menu button).
**Dropped:** ⌘T/N/L/O as shortcuts (Radial 2 keeps T/N/W plus Menu), refresh, window tiling, volume/brightness/lock/spotlight.

## Open questions
1. **Technical spike:** how to intercept mouse events globally + draw radials over every app on macOS. Path: `CGEventTap` for capture/synthesis, transparent always-on-top overlay window (NSPanel) for radials, Accessibility API (AXUIElement) to read focused-element/selection state. Must confirm event-tap can suppress/reshape native right-click. Wispr Flow is bound to mouse button 5 — Whisker only uses left/right/middle/scroll, so no input conflict by design.

Resolved: auto-copy default ON (toggleable); v1 target = macOS.
