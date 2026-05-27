# Whisker — Design Spec

Mouse-only computer control, used alongside Wispr Flow (which handles raw text dictation). Goal: do everything keyboard does *except typing* without touching the keyboard.

**Target:** Cross-platform (build core on one OS first, abstract later).

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

**Open question:** auto-copy on highlight? (User floated both "highlight auto-copies" and "explicit copy button." Current default = explicit buttons, with auto-copy as optional toggle.)

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

## Master gesture vocabulary (v1)

| Gesture | Action |
|---|---|
| Tap right-click | Native context menu (unchanged) |
| Hold right-click (~150ms) | Enter command mode → **Radial 1** |
| — Radial 1 buttons | Enter · Escape · Tab/Shift-Tab · ⌘S · ⌘F · ⌘P |
| — Scroll while right held | Switch app (⌘Tab) |
| — Quick left-click while right held | ⌘-click (multi-select, add one) |
| — Held left-click (~150ms) while right held | ⇧-click (range select) |
| Double-right-click | **Radial 2** (visually distinct): ⌘T · ⌘N · ⌘W |
| Middle-click + drag | Region screenshot |
| Click in input box (no selection) | Floating buttons: 🗑 delete char · paste |
| Highlight text | Floating buttons: 🗑 delete selection · cut · copy |
| Single / double / triple click | Place cursor / select word / select line (native) |

## v1 scope summary

**In:** floating text-edit buttons (#1), command-mode radials for Enter/Esc/Tab + ⌘S/F/P (#2, #4), switch-app via scroll (#3), multi/range select (#5), region screenshot (#7).
**Deferred to phase 2:** mouse-motion gestures, command palette for app-specific long-tail (#6).
**Dropped:** ⌘T/N/L/O as shortcuts (Radial 2 keeps T/N/W only), refresh, window tiling, volume/brightness/lock/spotlight.

## Open questions
1. Auto-copy on highlight — default off, optional toggle?
2. Cross-platform: which OS is the v1 build target before abstracting?
3. How are radials rendered + input intercepted globally? (OS accessibility/event-tap layer — needs a technical spike.)
