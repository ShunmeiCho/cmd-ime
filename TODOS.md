# CmdIME Follow-ups

Work deferred after the v0.1.12 preview. Recorded from the review passes (deep
review, code review, /simplify, security review), release prep, and post-release
checks.

## Next patch (0.1.13)

### [High] Ship unbound-modifier lifecycle fix
- Root cause: `EventTapMonitor.handleFlagsChanged` let unbound side-specific
  modifiers enter `OneShotModifierState` on key down, but skipped `modifierUp`
  on release when the modifier had no one-shot binding.
- Symptom: `option+j` could switch to Japanese and leave `left/right-option`
  state behind, so the next left/right Command tap only cleared stale state and
  had to be pressed a second time.
- Release criteria: keep the event-level regression covering
  `option+j -> left-command` and verify the full `swift test` suite.

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
- v0.1.12 is marked Latest / `prerelease=false` so the bare `curl` install and the
  version badge resolve to it, while the title still says "Preview".
- Action: keep emphasizing "unnotarized preview" in public communication so it is
  not read as a stable, notarized release.

## Deferred from deep review (P2/P3, no fixed milestone)

- `ConfigStore.loadOrDefault()` is now unused (CLI + GUI use `loadOrRecover`);
  remove it or delegate to `loadOrRecover().config`.
- Extract a pure keyboard-event reducer from `EventTapMonitor`. Keep CGEvent tap
  setup, event conversion, and system posting in the monitor; move one-shot state,
  keyPress matching, consume/pass-through decisions, and action decisions into a
  plain Swift reducer with sequence tests.
- Have `ShortcutRecorderField` commit a `KeyTrigger` directly instead of
  serializing `NSEvent -> String -> ShortcutParser -> KeyTrigger`; keep string
  parsing for CLI and hand-written config.
- Synthetic `sendKey` output carries no source marker, so a user remap can re-enter
  the tap; tag synthetic events and ignore them in `handleKeyDown`.
- Unify the per-keyCode one-shot modifier tables (`EventTapMonitor` /
  `ShortcutParser` / `ContentView`) behind one definition to remove the
  triplicated keyCode lists.

## Dynamic slots follow-ups

- PR1 implements the dynamic slot collection, migration/backup, CLI management,
  same-primary-language fallback and duplicate diagnostics; GUI renders the
  configured collection. This is no longer out of scope.
- PR2: GUI Add/Remove, drag-to-add, reordering and renaming, fallback notices,
  trigger-conflict rejection, data-driven LiveKeys, adaptive custom-color grid,
  No trigger labels, and the one-time migration banner. Unmatched slots already
  expose Choose source; source-assignment conflicts are rejected in PR1.
- PR3: source-detected first-run defaults and `keyboardctl init`; decide the
  third default trigger separately. Until then preserve legacy defaults.
- Collect real Korean/German/Russian scan fixtures for primary-language fallback.
- Configuration file watching/hot reload remains deferred; the running GUI can
  overwrite CLI edits.

## Out of scope for the 0.x line

- Developer ID signing + notarization (requires the paid Apple Developer Program).
- `SwitchRule` model refactor and a full indicator theme system (not the dynamic
  slot collection, which is implemented in PR1).
- Stable/preview update channels and a stronger install trust chain, including
  notarized stable builds and tag-pinned checksum verification by default.
- App Store sandboxed build; automatic in-app update install.
