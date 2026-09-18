## Unreleased

A first-run setup guide walks new users through permissions, the detected slots and a first switch, inside the settings window.

### Highlights

- New installs open with a three-step **Setup guide** card at the top of Settings: allow keyboard access, check what was detected, try it. The other sections stay folded behind one-line bars until the guide is finished or skipped; every bar can be opened by hand, so Quit and the slot board are never out of reach.
- Step 1 explains what Accessibility and Input Monitoring are each used for, opens the exact System Settings pane, and flips to Ready while System Settings is still in front where macOS reports the change to a running app. When macOS only applies a grant to a fresh process, or the listener cannot start although both permissions are ready, the guide offers **Relaunch CmdIME** (the app is reopened only after the old process has exited).
- Step 2 lists every slot as a sentence built from the real bindings, for example "Tap Left Command alone -> English (ABC)", covering taps, double taps and chords. **Change** opens the slot board. It also covers a Mac with a single input source, more slots than automatic keys, and a lone Shift trigger that may clash with an input method's own Shift toggle.
- Step 3 is a practice field: each confirmed switch ticks its sentence and names the next trigger to try. It ends with where CmdIME went: it keeps running without a menu bar icon, reopening the app shows Settings, and Runtime > Quit agent stops it.
- Privacy wording in the guide states what the event tap does: key events are checked in memory, by key code and modifier state, only to spot triggers; what you type is never stored or sent.
- The guide appears only for configs created by a first GUI launch (`hasCompletedSetup: false`). Existing config files, and configs written by `keyboardctl`, never show it. **Runtime > Setup guide > Show** replays it at any time without folding anything.
- Steps are labelled groups, status changes are announced to VoiceOver, every action is a button, and motion follows Reduce Motion.

## CmdIME v0.3.0 Preview

Switch slots become a customizable, ordered collection: CmdIME detects them from the installed input sources on first run, migrates existing config files with a backup, and fixes the shortcut recorder.

### Highlights

- Switch slots are now an ordered, customizable collection. Use `keyboardctl slots`, `slot add [<number|source-id>] [--name N]`, and `slot remove <slot>`; the GUI renders configured slots.
- Fresh GUI setup and `keyboardctl init` now detect one slot per primary language in system source order. The first five slots use Left Command / Right Command / Left Option / Right Option / Left Control; later slots have no trigger. If no selectable source has a usable primary language, the legacy English/Chinese/Japanese defaults remain the fallback (including Option+J for Japanese). Existing configs and triggers are unchanged.
- GUI **Reset to Detected** requires confirmation, replaces all slots and triggers, and preserves unrelated settings such as general indicator preferences. It backs up the original config to `config.json.before-reset.bak`, using unique names on subsequent resets; backup or save failure prevents applying the reset. CLI `init --force` instead replaces the entire config with detected defaults using the existing save/migration path, without this additional reset backup.
- New slots prefer a selected input source and fall back to another with the same primary language. Assignment rejects a source already used as another slot's first preference; duplicate resolutions remain usable and are reported by `diagnose` (`duplicateSlots` in JSON, alongside `slot` and `name`). Legacy matching rules are preserved.
- Slot indicator colors now follow each slot's stored tint rather than the matched source's language.
- Added slots use the first free Left Command / Right Command / Left Option / Right Option / Left Control tap, or remain unbound when none is free. Shift is never automatically assigned: many Chinese input sources use Shift to toggle English/Chinese. Right Control remains manual-only.
- Configuration upgrades to version 2 in memory. Every successful write backs up a file lacking `slots` to `~/.config/cmd-ime/config.json.v1.bak` (beside the config when using `--config`), using a fresh `config.json.v1.bak.<uuid>` if the canonical backup exists (never reusing or overwriting earlier backups), and CLI writes print an upgrade note with the new backup path. Read commands do not save the migration or print that note; backup failure prevents saving.
- **Downgrade warning:** quit the app and restore the backup named in the latest migration note before running an older binary (it may have a UUID suffix after repeated upgrades). Custom slot IDs can make older versions move the config to `.corrupt.<uuid>` and reset it; even legacy-only configs lose the `slots` collection on an old binary's save and deleted slots can return. Preserve a separate version-2 copy first.
- Choosing an input source that another slot already uses now swaps the two slots; for a slot with no source yet, used sources are shown as "used by <slot>" instead of failing silently.
- The shortcut recorder no longer traps the keyboard (Tab and Shift+Tab leave it), shows "Press shortcut" while recording, and lets you record a chord that is already bound: it explains which slot or remap owns it instead of switching the input source. Rejected triggers, failed tests and rejected source assignments are explained on the slot card.
- Input sources are labelled by their primary language, so layouts such as German or French are no longer shown as English.
- The live keys strip is drawn from the real bindings: each bound modifier key takes its slot's color (left and right Shift are now shown), chord triggers appear as their own keycaps, and nothing is colored by default assumptions any more.
- Quit the running GUI before CLI edits and reopen afterward; it does not hot-reload configuration and can overwrite those edits.

## CmdIME v0.2.1 Preview

CmdIME removes the menu bar status icon, makes CLI switching verifiable, adds a diagnosis command, and keeps the event tap responsive while a switch is confirmed.

### Highlights

- Fixed a dead end for users without a Chinese or Japanese input source: a slot that shows "Not matched" now offers the input source menu, so any slot can be pointed at any installed input source (for example Korean or German). Previously the only control was "Fix", which rescans by language and could not help.
- Removed the menu bar status icon, its menu, and the `showMenuBarIcon` setting. Settings is opened by launching `CmdIME.app` again; quit via Settings > "Quit agent" or `keyboardctl quit`.
- `keyboardctl switch` now confirms that the switch took effect and exits non-zero with an error message on `stderr` if macOS did not apply the change.
- Added `keyboardctl diagnose [--json]` to inspect each slot's configured preferences (`preferredIDs`, `languagePrefixes`, `nameContains`), the matched input source, and the match reason (`preferredID`, `fallbackLanguage`, `languagePrefix`, `nameContains`, or `none`).
- The event tap no longer blocks the run loop while confirming an input-source switch; confirmation retries are scheduled asynchronously on the main queue, and newer switches supersede older pending switches.
- Left and right modifier keys are now tracked by physical keycode (`pressedModifierKeyCodes`), ensuring accurate side-specific modifier transitions even when aggregate modifier flags remain active.

## CmdIME v0.1.13 Preview

CmdIME v0.1.13 fixes stale one-shot modifier state after unbound modifier shortcuts.

This is an unnotarized preview release.

### Fixes

- Fixed an issue where pressing `Option+J` to switch to Japanese could make the
  next left/right Command one-shot switch require two presses.
- All recognized modifier keys now complete the one-shot modifier release
  lifecycle, while actions are still performed only for modifiers that actually
  have one-shot bindings.
- Added regression coverage for left and right Option shortcut flows.
- Added coverage ensuring Command chords still cancel one-shot switching.

### Install

Recommended install command with version and SHA-256 verification:

```sh
CMDIME_VERSION=0.1.13 CMDIME_SHA256=86fb954cb15ef56ad6b9ef53347ca8a50f89cb7a72069c9251b1ad09e3331bc0 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ShunmeiCho/cmd-ime/v0.1.13/script/install.sh)"
```

Direct download SHA-256:

```text
86fb954cb15ef56ad6b9ef53347ca8a50f89cb7a72069c9251b1ad09e3331bc0  CmdIME-0.1.13.zip
```

Manual verification:

```sh
shasum -a 256 CmdIME-0.1.13.zip
```

### Preview Notice

This build is not notarized and is not signed with a Developer ID certificate. Browser downloads may show Gatekeeper warnings. The installer verifies the downloaded zip with SHA-256; the installer script is fetched over HTTPS from this repository tag.

### After Installing

CmdIME needs both macOS permissions:

- Accessibility
- Input Monitoring

Open CmdIME, grant both permissions in System Settings, then click Resume.
