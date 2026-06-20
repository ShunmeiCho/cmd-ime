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

## Verification

- `swift test`
- `git diff --check`
- Manual app launch
