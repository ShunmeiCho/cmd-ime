# CmdIME UI Redesign Direction

Status: Approved direction

CmdIME UI v3 is the visual source of truth.

Use v3 as a design direction, not as literal HTML-to-SwiftUI translation. SwiftUI
implementation should preserve v3's visual language and product information
architecture while keeping native macOS behavior.

## Preserve

- Dark premium keyboard-console surface.
- Tactile keycaps.
- Active slot glow.
- Compact live keys strip.
- Rich switch slot cards.
- Material switch indicator.
- Permission state machine.
- Exception states.
- No Input Sources state.
- Native NSMenu menu bar strategy.
- Codebase-aligned role colors: English blue, Chinese green, Japanese red.
- Near-caret indicator behavior.
- Icon plus text status labels for accessibility.
- Full usability without a menu bar icon.

## Do Not Copy

- Fake macOS titlebar.
- Bundled web fonts.
- Hardcoded release version strings.
- Web-style custom controls where native SwiftUI or AppKit controls are required.

## Implementation Contract

Keep the current native `NSWindow` titlebar. Do not self-draw traffic-light
window controls.

Use system fonts. Keycaps and command-like labels should use SwiftUI system
monospaced styling, such as:

```swift
.font(.system(.body, design: .monospaced))
```

or:

```swift
.monospaced()
```

Bind version and update copy to existing runtime state, such as bundle version
and `UpdateStatus`. Do not copy mock version strings from the HTML design.

Keep live keys as a compact strip with press feedback and slot-switching
explanation. First implementation may be display-only and driven by the most
recent successful switch or test action. Do not connect it to new event-tap UI
state in the first redesign pass, and do not turn it into a large keyboard
surface.

Permission flows must not imply that CmdIME can directly grant macOS privacy
permissions. Use state-aware actions such as:

- Open System Settings
- Request Permissions
- Start Listening

Show `Start Listening` only when required permissions are ready.

## Menu Bar Policy

The menu bar surface is not part of the primary UI for this redesign.

The menu bar icon is locked off on affected macOS versions because it can
trigger a status-item layout issue that freezes Settings and drives CPU usage
very high. CmdIME must remain fully usable without a menu bar icon.

Current policy:

- On affected macOS versions, show Menu Bar Icon as `Locked Off`.
- Settings remains reachable by reopening `CmdIME.app`.
- The primary runtime interaction is the configured keyboard shortcuts.
- The primary runtime feedback is the near-caret switch indicator.
- The primary stop or escape paths are Settings > Quit CmdIME and
  `keyboardctl quit`.

## Binding Correctness

Each physical one-shot modifier key may be assigned to only one switch slot. For
example, `Right Command` cannot be bound to Chinese on single tap and English on
double tap at the same time. The UI must warn about existing conflicts and block
new conflicting assignments.

Implementation red lines:

- Do not implement a custom menu bar popover in this phase.
- Do not introduce SwiftUI `MenuBarExtra`.
- Do not animate or frequently mutate `NSStatusItem`.
- Do not update menu bar state on every input-source switch.
- Do not depend on the menu bar icon for any core flow.
- Keep the existing simple `NSMenu` strategy only on supported systems.

## Frozen Direction

Do not rework these without an explicit redesign decision:

- Visual positioning.
- Dark flagship direction.
- Keycap language.
- Live keys strip.
- Slot card architecture.
- Indicator style.
- Permission onboarding architecture.
- NSMenu menu bar strategy.
- Menu bar locked-off state on affected macOS versions.

Small implementation adjustments are allowed:

- Reduce glow intensity by 10-20% where needed.
- Tune spacing and font sizes.
- Share structure between dark and light variants.
- Replace mock copy with real app copy.
- Improve accessibility and contrast.

## Implementation Phases

1. Create design tokens and primitive components.
2. Refactor `ContentView` into components without changing behavior.
3. Implement the dark flagship Settings surface.
4. Add permission onboarding and exception states.
5. Add compact live keys strip.
6. Polish indicator preview and runtime cards.

## Decision record — 2026-09-18: Slot board PR1

The owner explicitly approves replacing the frozen single-row slot card
architecture with a two-column board: installed input sources on the left and
ordered, two-row slot cards on the right. The source column is 196 points, the
gap is 14, and cards stay flexible at the existing 720-point window minimum.
There is only page scrolling, not a nested list scroller or collapse breakpoint.

Keep the dark keyboard-console surfaces, tactile keycaps, existing tokens,
slot-specific tints and icon-plus-text status labels. Source usage distinguishes
preferred ownership from fallback resolution; fallback-only rows cannot add a
slot. Unmatched cards keep Choose and trigger editing; Test is disabled. The old
Fix action is removed. Card overflow/context menus provide Rename, Move Up/Down
and Remove; the board notice below the cards provides Undo and Dismiss.

PR1 adds only non-pointer management and its feedback. The future drag handle's
14-point seat is reserved but exposes no inert control. Drag interaction is PR2.
The existing segmented trigger picker, modifier menu and recorder stay in row two;
bubble recording belongs to a separate delivery. LiveKeys is unchanged.

Structural edits reuse expandCollapse. Added/reordered/restored cards receive a
seat pulse bounded by the frozen active stroke 0.74 and shadow 0.26. Reduce Motion
uses instant layout changes, opacity fades and a stroke-only pulse; invalid rename
uses warning colour rather than shake. No indicator-style or activation-motion
redesign is authorized by this increment.

A standard SwiftUI TextField supports inline rename, Return/Escape and guarded
outside-click commit. Editing-menu shortcuts depend on the separate hidden main
menu work. Full Keyboard Access and VoiceOver have explicit menus and actions;
real-device focus, announcements, IME and 720-point layout checks remain required.

## Decision record — 2026-09-18: First-run setup guide

The setup guide card is an addition on top of the frozen layout, not a rework of
it. The permission onboarding architecture, slot card architecture, live keys
strip and indicator style are unchanged; the guide explains them and steps aside.

The card sits between the header and the Keyboard control section and is built
only from existing parts: `CompactSection`, keycaps, `RoleBadge`, `StatusPill`,
`ConsoleButtonStyle` and the existing colour, radius and motion tokens. It shows
three steps (allow keyboard access, check what was detected, try it). The current
step is derived in `KeyboardSwitcherCore` (`SetupGuideState`); the only stored
fact is `hasCompletedSetup`.

While the stored flag is false, the sections below the card fold into one-line
bars with the section label and a Show button. Bars are buttons, so every section,
Quit included, stays reachable. Change in step 2 unfolds the slot board and
scrolls to it. Finish or Skip stores the flag, unfolds everything and lets the
card shrink toward the header status pill. Returning users never see folded
sections: Runtime > Setup guide replays the card for the session only.

Permission copy keeps the existing rule: CmdIME never implies it can grant a
privacy permission. Actions are Open Settings, Request Permissions, Try Again and
Relaunch CmdIME (Quit CmdIME when the process has no app bundle to reopen).
The privacy sentence describes the event tap as implemented: key down, key up
and modifier events are inspected in memory by key code and modifier state.

Step and fold changes reuse `expandCollapse`; tried marks reuse `stateChange`.
Reduce Motion gets instant layout changes and a plain fade instead of the shrink.
Real-device checks of focus order, announcements, the relaunch path, trigger
firing while Settings is key, and the 720-point layout remain required. So does
the revoke-then-grant path: the guide rebuilds the listener when a permission
returns, on the unverified assumption that the old event tap does not recover.

## Verification

- `swift test`
- `git diff --check`
- Manual app launch
