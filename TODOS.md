# CmdIME Follow-ups

Work deferred past the v0.1.11 preview. Recorded from the review passes (deep
review, code review, /simplify, security review) and post-release review.

## Next patch (0.1.12)

### [Medium] Switch indicator "Custom color" is global, not per-slot
- `SwitcherConfig` holds a single `switchIndicatorCustomColorHex`
  (`Sources/KeyboardSwitcherCore/Models.swift`); `.custom` renders the same color
  for every input method (`Sources/CmdIME/Services/InputIndicatorController.swift`).
- The `Role` color style varies per role, so users can expect `Custom` to also be
  per-slot. The semantics do not close.
- Short term: relabel `Custom color` to `Global custom color` (or "applies to all
  slots"). Copy/UI only, no logic risk.
- Long term: per-slot custom colors (one color field per role + three pickers).

### [Low] README generic verified-install command pulls `main/script/install.sh`
- README's `CMDIME_VERSION=<version> ... main/script/install.sh` uses the `main`
  script rather than a tag; release notes already pin the tag path.
- Action: point README users to the per-release tag-pinned command, or use
  `<tag>/script/install.sh` in the example.

### [Low] "Preview" wording vs GitHub non-prerelease Latest
- v0.1.11 is marked Latest / `prerelease=false` so the bare `curl` install and the
  version badge resolve to it, while the title still says "Preview".
- Action: keep emphasizing "unnotarized preview" in public communication so it is
  not read as a stable, notarized release.

## Deferred from deep review (P2/P3, no fixed milestone)

- `ConfigStore.loadOrDefault()` is now unused (CLI + GUI use `loadOrRecover`);
  remove it or delegate to `loadOrRecover().config`.
- The event-tap confirm path uses `Thread.sleep` on the main run loop; consider
  moving confirm/retry off the run loop (async) so the tap never blocks.
- `EventTapMonitor` routing has thin unit coverage; add pure-logic test seams.
- Synthetic `sendKey` output carries no source marker, so a user remap can re-enter
  the tap; tag synthetic events and ignore them in `handleKeyDown`.
- Unify the per-keyCode one-shot modifier tables (`EventTapMonitor` /
  `ShortcutParser` / `ContentView`) behind one definition to remove the
  triplicated keyCode lists.

## Out of scope for the 0.x line

- Developer ID signing + notarization (requires the paid Apple Developer Program).
- Per-slot / `SwitchRule` model refactor; full indicator theme system.
- App Store sandboxed build; automatic in-app update install.
