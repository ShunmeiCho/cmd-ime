## CmdIME v0.2.1 Preview

CmdIME removes the menu bar status icon, makes CLI switching verifiable, adds a diagnosis command, and keeps the event tap responsive while a switch is confirmed.

### Highlights

- Switch slots are now an ordered, customizable collection. Use `keyboardctl slots`, `slot add [<number|source-id>] [--name N]`, and `slot remove <slot>`; the GUI renders configured slots. GUI management and detected first-run defaults remain follow-ups; `init` keeps the existing three defaults.
- New slots prefer a selected input source and fall back to another with the same primary language. Assignment rejects a source already used as another slot's first preference; duplicate resolutions remain usable and are reported by `diagnose` (`duplicateSlots` in JSON, alongside `slot` and `name`). Legacy matching rules are preserved.
- Slot indicator colors now follow each slot's stored tint rather than the matched source's language.
- Added slots use the first free Left Command / Right Command / Left Option / Right Option / Left Control tap, or remain unbound when none is free. Shift is never automatically assigned: many Chinese input sources use Shift to toggle English/Chinese. Right Control remains manual-only.
- Configuration upgrades to version 2 in memory. The first successful write backs up a file lacking `slots` to `~/.config/cmd-ime/config.json.v1.bak` (beside the config when using `--config`), without overwriting an existing backup, and CLI writes print an upgrade note. Read commands do not save the migration or print that note; backup failure prevents saving.
- **Downgrade warning:** quit the app and restore `config.json.v1.bak` before running an older binary. Custom slot IDs can make older versions move the config to `.corrupt.<uuid>` and reset it; even legacy-only configs lose the `slots` collection on an old binary's save and deleted slots can return. Preserve a separate version-2 copy first.
- Quit the running GUI before CLI edits and reopen afterward; it does not hot-reload configuration and can overwrite those edits.

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
