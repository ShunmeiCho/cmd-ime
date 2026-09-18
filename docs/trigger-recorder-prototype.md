# Trigger recorder feasibility

Validated on macOS 27 with the Xcode 27 toolchain, targeting macOS 13.
Prototype source and executables remain outside the repository in the task's
`popover-recorder-probe` scratch directory. This document records the handoff,
not a production recorder implementation.

## Decision

SwiftUI `.popover` with an AppKit local event monitor is a viable carrier for the
recorder. A managed NSPanel is not required by the observed behavior. This is a
runtime result on macOS 27, not a macOS 13 runtime certification.

## Observed behavior

The independent `.accessory` app contains a button that presents a SwiftUI
popover. Its signed scratch app bundle was launched through LaunchServices.
The automated run presents the same binding, waits for content appearance, and
injects events with `NSApp.sendEvent` into the installed local monitor.

- Fourteen recognizer assertions passed. Twenty additional runtime assertions
  passed through the real popover and local monitor.
- Physical Control 59/62, Shift 56/60, Option 58/61 and Command 55/54 codes were
  distinct. Each produced a modifier tap. Two successive Control taps produced
  a double tap; Option+A produced a chord.
- Escape, Return, Delete and Forward Delete reached the monitor and were
  consumed by returning nil. The probe reports their recognition outcomes; it
  does not edit product bindings. Sound output was not measured.
- Changing the presentation binding to false removed the monitor through
  `onDisappear`. Reopening installed a fresh monitor.
- Transferring key status to another real window dismissed the popover and
  removed its monitor. Closing the host window also ended capture. Cleanup was
  idempotent when both a window notification and `onDisappear` arrived.
- The host remained key while this text-only popover was open.

An early prototype closed itself because `begin` called cleanup that also
invoked the dismiss callback. Separating cleanup from dismissal fixed the
failure. It was not evidence of an unreliable SwiftUI popover.

## Interface guidance

Keep a main-actor recording-session owner with explicit `begin(in:)` and
`end(reason:)` operations. Obtain the host NSWindow from the anchor before
presenting; do not discover it solely from `NSApp.keyWindow` during appearance.

- Separate removing old monitors and resetting recognizer state from requesting
  dismissal. Starting a new session must not call the new session's close action.
- Publish a synchronous capture-state callback to AppModel, which controls
  `EventTapMonitor.isCapturingShortcut`. End capture on explicit close,
  `onDisappear`, host key loss, and host close; make all cleanup paths idempotent.
- Route `keyDown` and `flagsChanged` to one recognizer. Return nil for captured
  keys so menu equivalents and default responder actions do not run.
- Keep recognition as a draft. A first tap must remain eligible for a second
  tap; do not persist a single tap before deciding whether it is a double tap.
- Preserve physical left/right held-key tracking, including overlapping
  modifiers and aggregate flags. The scratch recognizer is intentionally small
  and is not a replacement for production state and conflict handling.
- Validate conflicts through the existing core APIs before committing. Handle
  cancel, commit and clear as distinct intents owned by the UI session.

## Manual acceptance still required

Test actual button activation, outside clicks, app switching, held and overlapping
modifiers, real HID delivery, audible alerts, Full Keyboard Access and VoiceOver.
Repeat on macOS 13. If the eventual popover gains focusable content, recheck
whether its own window takes key status before applying host-key-loss dismissal.
The tested content had no text editor or other focus-taking control.
