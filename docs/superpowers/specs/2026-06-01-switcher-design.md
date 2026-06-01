# Whisker Switcher — Design Spec

Date: 2026-06-01
Status: approved-for-planning

## Goal

While holding right-click, scrolling opens a **Switcher HUD** that mimics the
macOS ⌘Tab app switcher but generalizes to multiple *dimensions*: **Apps,
Windows, Desktops, Tabs**. The user cycles items by scrolling, can switch which
dimension is shown via a category bar, and commits the selection by releasing
right-click — exactly like holding ⌘Tab (scroll / click an icon / step, then
release to activate).

This replaces the current behavior where scroll-while-right-held does a live
per-notch ⌘Tab step.

## Interaction model

Entry (extends the existing hold-right gesture):
1. Hold right → primary radial blooms (unchanged).
2. **First scroll** dismisses the radial and opens the Switcher HUD, seeding the
   category by direction:
   - scroll **up** → **Apps**
   - scroll **down** → **Desktops**

While the HUD is open (right still held):
- **Scroll** steps the highlighted item within the active category (up = previous,
  down = next), wrapping around.
- **Move the mouse onto a category button** (Apps / Windows / Desktops / Tabs)
  and **left-click** it → switch the active category and reload its items.
- **Left-click an item icon** → select that item (becomes the highlight).
- **Release right-click** → **commit**: activate the highlighted item. HUD fades.
- Any non-left, non-scroll button (e.g. middle) or Escape-equivalent → cancel,
  HUD fades, nothing switches.

Commit is **always on release** (preview-before-commit), matching the radial's
release-to-select. Clicking an item only changes the highlight; release fires it.

The Tabs category is **only enabled when the frontmost app is a supported
browser** (Safari, Chrome). Otherwise the Tabs button is shown disabled/greyed.

## HUD layout

Centered on the screen containing the cursor (reuse `Coords` + screen-of-cursor
logic from the radial). Mimics the ⌘Tab HUD: rounded dark translucent panel,
icons in a row, highlighted item has a lighter rounded backdrop + label below.

```
        [ Apps ] [ Windows ] [•Desktops•] [ Tabs ]     ← category bar (active highlighted)
   ┌─────────────────────────────────────────────┐
   │   ▢     ▢     ███     ▢     ▢                 │     ← items (real icons), highlight on selection
   └─────────────────────────────────────────────┘
                    Desktop 3                          ← label of highlighted item
```

Spring fade-in/out reuses the animation approach from `RadialNSView`
(60fps manual integrator). Overlay joins all Spaces (`.canJoinAllSpaces`,
`.stationary`, `.fullScreenAuxiliary`) like existing overlays.

## Architecture

Keep the pure-state-machine pattern: the gesture machine has zero OS deps and is
unit-tested; thin glue executes its actions.

### Gesture state machine (`gesture/GestureMachine.swift`)

Replace the live `switchAppStep` path. New states under hold-right:
- `switcherActive(category: SwitcherCategory, selection: Int)` — HUD open.

New `GestureEvent`s already exist (`scrolled`, `buttonDown/Up`, `tick`); the
machine maps them to new actions:
- `.openSwitcher(seed: SwitcherCategory)` — first scroll; seed = `.apps` (up) or `.desktops` (down).
- `.switcherStep(forward: Bool)` — subsequent scrolls.
- `.switcherSetCategory(SwitcherCategory)` — left-click on a category button (the
  controller hit-tests the click to a category and feeds this back, OR the machine
  emits a generic `.switcherClick(at:)` the controller resolves — see Open question 1).
- `.switcherSelect(at: CGPoint)` — left-click on an item.
- `.commitSwitcher` — right released.
- `.cancelSwitcher` — other button / abort.

`isInterceptingLeftClicks` must return true while `switcherActive` so left-clicks
drive the HUD instead of the app underneath (and do NOT trigger ⌘-click/⇧-click
multi-select, which only applies in plain `commandMode`).

`SwitcherCategory` enum: `.apps`, `.windows`, `.desktops`, `.tabs`.

### Overlay (`overlay/SwitcherController.swift`, `overlay/SwitcherView.swift`)

Mirrors `OverlayController` / `RadialView`:
- `SwitcherController` owns the panel, positions it on the cursor screen, holds the
  current `[SwitcherItem]` + selection + active category + enabled categories,
  drives the view, and exposes hit-testing (point → category button, point → item
  index) for the controller-side resolution of clicks.
- `SwitcherView` (NSView) draws the category bar + icon row + label with the spring
  animation. Source-agnostic: it only knows `SwitcherItem { icon: NSImage?, label: String }`
  and which index is highlighted.

### Switcher sources (`os/Switcher/`)

Common protocol so the HUD is source-agnostic:
```
protocol SwitcherSource {
    var category: SwitcherCategory { get }
    var isAvailable: Bool { get }            // e.g. Tabs only for supported browsers
    func items() -> [SwitcherItem]           // ordered; index 0 = first
    func commit(index: Int)                  // perform the switch
}
struct SwitcherItem { let icon: NSImage?; let label: String }
```

- `AppsSource` — `NSWorkspace.shared.runningApplications` filtered to
  `.activationPolicy == .regular`, real `.icon`. `commit` = `app.activate()`.
  Initial selection defaults to the most-recently-used non-frontmost app (so a
  single scroll-up + release = swap to last app, like ⌘Tab).
- `WindowsSource` — AX windows of the frontmost app (`AXUIElementCreateApplication(pid)`
  → `AXWindows`), label = window title, icon = app icon. `commit` = set
  `AXMain`/`AXRaise` on the window + activate the app.
- `SpacesSource` (`os/Switcher/Spaces.swift`, **private-API isolated here**) —
  uses CoreGraphics Services private symbols (`CGSMainConnectionID`,
  `CGSCopyManagedDisplaySpaces`) to read the ordered space list for the active
  display and the current space index. Items = "Desktop N" numbered tiles
  (generic icon; no per-space thumbnail without screen-recording each space).
  `commit(index)` = synthesize `Ctrl+←/→` `abs(index - current)` times in the
  correct direction. All private-API surface lives in this one file behind a small
  `enum Spaces` API (`count`, `currentIndex`, `switchTo(index:)`) so it can be
  swapped/stubbed and the risk is contained.
- `TabsSource` — only `isAvailable` when frontmost bundle id ∈
  {`com.apple.Safari`, `com.google.Chrome`}. Uses AppleScript (`NSAppleScript`)
  to list tab titles of the front window and select one by index. Requires
  Automation (Apple Events) permission — request/inform on first use. Icon =
  browser app icon (or favicon if cheaply available; otherwise app icon).

A `SwitcherCoordinator` (in glue / `main.swift`) maps `SwitcherCategory` →
`SwitcherSource`, refreshes items when the category changes, and is called by the
controller on commit.

## Data flow

1. Tap (`EventTap`) feeds mouse/scroll events to `GestureMachine`.
2. Machine emits switcher actions.
3. Glue (`main.swift` / coordinator) translates:
   - `.openSwitcher(seed)` → pick source for seed, `items()`, show HUD with default
     selection, set enabled categories (Tabs enabled only if its source `isAvailable`).
   - `.switcherStep(forward)` → move selection (wrap), redraw.
   - `.switcherSetCategory(cat)` → swap source, reload items, reset/clamp selection, redraw.
   - `.switcherSelect(at:)` → controller hit-tests to item index, set selection.
   - `.commitSwitcher` → `source.commit(selectedIndex)`, fade HUD, state → idle.
   - `.cancelSwitcher` → fade HUD, state → idle.
4. Left-clicks while HUD open are consumed (not passed to the app); the controller
   hit-tests them to either a category button (→ setCategory) or an item (→ select).

## Error handling / edge cases

- **No items** (e.g. a source returns empty): show an empty HUD with the category
  label; commit is a no-op; never crash.
- **CGS private API missing/changed** (future macOS): `Spaces.count` returns 1 /
  `currentIndex` 0; Desktops category degrades to a single tile and commit is a
  no-op. Whisker keeps working; only the desktop dimension is inert. Log once.
- **AppleScript / Automation denied**: `TabsSource.isAvailable` stays true (it's a
  browser) but `items()` returns empty and we surface a one-time prompt to grant
  Automation; commit no-ops.
- **Selection out of range after a category swap**: clamp to `[0, count)`.
- **Feedback loop**: commit synthesizes Ctrl+arrow / clicks — tag with the existing
  synthetic-event sentinel so the tap ignores them.
- **Multi-select conflict**: left-click is repurposed inside `switcherActive`; the
  existing ⌘-click/⇧-click only fires in `commandMode`/`commandModeLeftDown`,
  which `switcherActive` is not. Verified via `isInterceptingLeftClicks`.

## Testing

- **Gesture machine** (pure, unit-tested, the bulk of new tests):
  - first scroll up → `.openSwitcher(seed: .apps)`; first scroll down → `.openSwitcher(seed: .desktops)`.
  - subsequent scrolls → `.switcherStep(forward:)` with correct direction.
  - left-click while open → `.switcherSelect(at:)` (NOT ⌘-click).
  - release right while open → `.commitSwitcher`; state returns to idle.
  - other button while open → `.cancelSwitcher`.
  - `isInterceptingLeftClicks` true while `switcherActive`.
  - radial is dismissed on the opening scroll (no `.selectRadial` on release).
- **Sources**: light unit tests where pure (selection clamping, category→source
  mapping, browser-detection for Tabs availability). OS-touching parts
  (CGS, AX, AppleScript) verified manually on a live session.
- **HUD hit-testing**: pure point→category / point→item index tests.

## Scope / phasing

v1 includes all four categories: **Apps, Windows, Desktops, Tabs (Safari+Chrome)**.
Desktops uses private CGS APIs, isolated in `os/Switcher/Spaces.swift`. Tabs is
browser-gated and degrades gracefully without Automation permission.

## Resolved decisions

1. **Click resolution (was open Q1): generic click from the machine.** The state
   machine emits a single `.switcherClick(at: CGPoint)` on left-click while open;
   the `SwitcherController` hit-tests the point to either a category button
   (→ switch category) or an item (→ set selection). Keeps the machine OS-agnostic
   and all geometry in one place. (Replaces the earlier `.switcherSetCategory` /
   `.switcherSelect` split in the actions list above.)
2. **Apps presentation: own HUD styled like ⌘Tab, NOT Apple's system switcher.**
   The literal system ⌘Tab HUD can't host our category bar, can't be hit-tested by
   our event tap, and can't be merged with release-to-commit + category switching.
   So Apps renders in the same custom `SwitcherView` as the other categories,
   visually mimicking ⌘Tab (row of app icons, highlight, label). Uniform control,
   uniform interaction across all four categories.

## Out of scope (v1)

- Per-window thumbnails for the Windows category (needs screen capture). App icon
  + title only.
- Tabs beyond Safari + Chrome.
