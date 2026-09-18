<div align="center">
  <img src="Assets/AppIcon.png" alt="CmdIME app icon" width="112">
  <h1>CmdIME</h1>
  <p><strong>Deterministic macOS input-source switching for multilingual typing.</strong></p>

  <p>
    <a href="https://github.com/ShunmeiCho/cmd-ime/actions/workflows/swift.yml"><img alt="Swift" src="https://github.com/ShunmeiCho/cmd-ime/actions/workflows/swift.yml/badge.svg"></a>
    <a href="https://github.com/ShunmeiCho/cmd-ime/releases"><img alt="Release" src="https://img.shields.io/github/v/release/ShunmeiCho/cmd-ime"></a>
    <a href="LICENSE"><img alt="License: MIT" src="https://img.shields.io/badge/License-MIT-blue.svg"></a>
  </p>
</div>

CmdIME is a macOS input-source switcher built around configurable switch slots
and direct target switching. Instead of cycling through input sources, press the
slot you want and CmdIME selects the matching macOS input source.

Why not just use the built-in `Control+Space`? It cycles, so with three or more
input sources you have to look at where you landed, and many users find that a
press is occasionally delayed or seems to do nothing. CmdIME gives every input
source its own key, confirms that macOS really made the switch (retrying when it
did not), and shows a small indicator near the caret so you know where you are
without looking at the menu bar.

## What It Does

CmdIME scans the input sources already installed in macOS instead of hardcoding
one keyboard layout. On a fresh setup, it creates one slot per primary language,
using the first selectable source for that language in system order. Sources
without a primary language are skipped. Each slot can be pointed at any installed
input source from its card, including a slot that shows "Not matched".

Settings is a slot board. Installed input sources are listed on the left, your
slots on the right:

- Drag a source into the slot list, or use **Add Slot**, to create a slot. Drag a
  slot's handle to reorder it; Esc cancels a drag. The "..." menu has Move Up,
  Move Down, Rename, Color and Remove Slot, and the same actions work from the
  keyboard and VoiceOver. A removed slot can be restored with **Undo** until the
  next slot change.
- Click a slot's badge to give it one color. The source list, Live keys and the
  switch indicator follow that color.
- The source list follows System Settings: adding or removing an input source
  updates it without a relaunch, and a Refresh button is always there.
- "Current" marks the input source macOS has selected, however it was selected.
  **Switch** selects a slot's source directly; it does not test the trigger.
- Live keys, below the board, is a small keyboard that lights up the keys bound
  to the current slot.

| Detected slot | Default trigger |
| --- | --- |
| First | Left Command |
| Second | Right Command |
| Third | Left Option |
| Fourth | Right Option |
| Fifth | Left Control |
| Sixth and later | No trigger (assign manually) |

Existing configurations and their triggers are unchanged. If no selectable
source has a usable primary language, initialization uses the legacy defaults:
English on Left Command, Chinese on Right Command, Japanese on **Option+J**.

The demo below shows an example legacy English/Chinese/Japanese mapping, not
the source-detected defaults for every Mac.

[![CmdIME example switching demo](demo-videos/renders/preview-default-switching.gif)](demo-videos/renders/cmdime-default-switching-demo.mp4)

[Open the full example switching demo](demo-videos/renders/cmdime-default-switching-demo.mp4)

## Distribution Status

CmdIME is currently distributed as an **unnotarized preview build**.

It is not distributed through the Mac App Store, and current preview builds are
not signed with a Developer ID certificate unless a release explicitly says so.
macOS may block the app on first launch or ask you to approve it manually in
System Settings.

After you approve CmdIME and grant the required permissions, it runs normally.
This preview distribution path is intended for technical users and early
adopters.

Apple's Gatekeeper documentation explains that apps downloaded from outside the
App Store are checked for identified developer signing, notarization, and
modification status. Developer ID signing and notarization are the smoother path
for broader public distribution:

- [Gatekeeper and runtime protection in macOS](https://support.apple.com/guide/security/gatekeeper-and-runtime-protection-sec5599b66df/web)
- [Signing Mac Software with Developer ID](https://developer.apple.com/developer-id/)

## Install

### Recommended Preview Install

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ShunmeiCho/cmd-ime/main/script/install.sh)"
```

The installer resolves the latest release, downloads the zip, verifies it against
the `.sha256` file published with the release, installs `CmdIME.app` to
`/Applications`, links `keyboardctl`, and opens the app so macOS can request
permissions.

To pin an exact version and checksum yourself (copy both from the release notes):

```sh
CMDIME_VERSION=0.4.1 CMDIME_SHA256=038a480649bc8110abcae4903f03def32dc7e259a9fcf6aef44fc26a77afc101 \
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ShunmeiCho/cmd-ime/main/script/install.sh)"
```

After installation, open CmdIME and grant both **Accessibility** and
**Input Monitoring** permissions in System Settings > Privacy & Security.

[![CmdIME install and permissions demo](demo-videos/renders/preview-install-permissions.gif)](demo-videos/renders/cmdime-install-permissions-demo.mp4)

[Open the full install and permissions demo](demo-videos/renders/cmdime-install-permissions-demo.mp4)

### Homebrew Custom Tap

Recent Homebrew versions require casks to come from a tap. To install CmdIME
with Homebrew, tap this repository first:

```sh
brew tap ShunmeiCho/cmd-ime https://github.com/ShunmeiCho/cmd-ime
brew install --cask ShunmeiCho/cmd-ime/cmd-ime
```

### Build From Source

```sh
git clone https://github.com/ShunmeiCho/cmd-ime.git
cd cmd-ime
swift test
./script/build_and_run.sh
```

The local app still needs Accessibility and Input Monitoring permissions before
global keyboard listening can work.

## First Launch And Permissions

A new install opens with a three-step **Setup guide** at the top of Settings:
allow keyboard access, check the detected slots, then try a switch. It can be
skipped, and **General > Show Setup Guide** brings it back. Users updating from
an earlier version see a one-line "New in 0.4" notice instead.

CmdIME needs both macOS permissions:

- Accessibility
- Input Monitoring

Use one stable app location when granting permissions. macOS stores approval
against the app's code identity, so approving one rebuilt `CmdIME.app` and then
running another copy from `dist/`, `dist/release/`, or `/Applications` can make
macOS ask again.

Recommended permission reset flow:

1. Quit CmdIME.
2. Remove old `CmdIME.app` entries from System Settings > Privacy & Security >
   Accessibility and Input Monitoring.
3. Install or copy the app to the location you actually use, such as
   `/Applications/CmdIME.app`.
4. Open that exact app and grant both permissions.
5. Quit and reopen CmdIME.

## Gatekeeper Troubleshooting

Because current preview builds are not notarized, macOS may show a warning such
as "CmdIME is damaged" or "Apple cannot check it for malicious software" when
you open a browser-downloaded zip.

If you trust the release you downloaded, try opening CmdIME once, then go to
System Settings > Privacy & Security and choose **Open Anyway**.

If needed, you can also remove the browser quarantine attribute:

```sh
xattr -dr com.apple.quarantine /Applications/CmdIME.app
```

Prefer the pinned installer path when possible. That path avoids the browser
quarantine flow.

## App Behavior

CmdIME is a background input-source agent. The settings window is only a control
panel: closing the window does not stop keyboard listening. Release builds are
packaged with `LSUIElement`, so the app does not appear in the Dock or app
switcher.

Open `CmdIME.app` again whenever you need Settings. To stop the background
agent, use **General > Quit CmdIME** in the status bar at the top of Settings, or run:

```sh
keyboardctl quit
```

If the CLI is not linked yet, use:

```sh
pkill -x CmdIME
```

## Bindings

Each slot has three optional triggers. Any one you set switches to that slot,
and they can be combined (for example a single tap for daily use plus a shortcut
as a fallback). Leave the rest empty.

- `Single tap`: choose one of the eight physical modifier keys (left or right
  Command, Option, Control, Shift) from the menu.
- `Double tap`: the same menu, for a double tap.
- `Shortcut`: click **Record…**, press a modifier together with a key such as
  `option+j`, then Save. Esc cancels; tap triggers are paused while recording.

A key already used for the same gesture by another slot, or by a key remap, is
shown as used and cannot be picked. The same key can be a single tap for one
slot and a double tap for another. Many Chinese input methods use Shift to
toggle Chinese and English, so CmdIME never assigns Shift automatically.

Single-key modifier bindings and keyboard shortcuts are intentionally separate
so common shortcuts such as `Command+C`, `Command+V`, `Command+Tab`, and
multi-modifier chords are not treated as one-shot Command taps. Single-tap
modifier bindings switch immediately; CmdIME waits briefly only when the same
modifier also has a CmdIME double-tap binding.

The settings UI rejects macOS input-source shortcuts such as `control+space`
and `control+option+space` so CmdIME does not steal the system input-source
chooser by accident.

CmdIME switches input sources programmatically, so it does not invoke the
private macOS input-source chooser. Enable `Show switch indicator` to show
CmdIME's own lightweight confirmation bubble after a switch. The indicator can
be disabled, resized with presets and a scale slider, switched between
icon/text display modes, or recolored with slot colors, the system accent color,
monochrome, or a custom color in Settings.

If Japanese opens a kana palette instead of switching to Hiragana, refresh input
sources or update to CmdIME 0.1.10 or later. macOS exposes
`com.apple.50onPaletteIM` as a selectable Japanese source, but it is an
auxiliary kana palette, not the normal Hiragana input method.

## CLI

Slot IDs depend on your detected sources. These examples assume slots named
`english`, `chinese`, and `japanese`; run `keyboardctl slots` for your actual IDs.

```sh
swift run keyboardctl scan
swift run keyboardctl init
swift run keyboardctl slots
swift run keyboardctl slot add
swift run keyboardctl slot add 1 --name Korean
swift run keyboardctl slot remove japanese
swift run keyboardctl switch english
swift run keyboardctl diagnose
swift run keyboardctl diagnose --json
swift run keyboardctl bind left-command english
swift run keyboardctl bind right-command chinese
swift run keyboardctl bind option+j japanese
swift run keyboardctl bind double-left-command english
swift run keyboardctl remap right-control escape
swift run keyboardctl quit
swift run keyboardctl listen
```

- `keyboardctl init`: creates source-detected defaults using the same detection
  as the GUI's first launch. An existing config is left untouched unless you
  pass `--force`, which replaces the entire configuration with detected defaults.
  Back up custom settings before forcing a reset; it does not create the GUI's
  before-reset backup (the legacy migration backup below still applies).
- `keyboardctl switch <slot>`: selects the matched input source for a slot and
  confirms that macOS applied the switch. If macOS does not apply the selection,
  it prints an error message to `stderr` and exits non-zero.
- `keyboardctl diagnose [--json]`: prints each slot's configured preferences
  (`preferredIDs`, `languagePrefixes`, `nameContains`), the matched input source,
  and the match reason (`preferredID`, `fallbackLanguage`, `languagePrefix`, `nameContains`, or `none`).
  Pass `--json` for structured JSON output: `slots` entries retain `slot` IDs,
  and include `name` and `duplicateSlots` (an empty array when there are none).
- `keyboardctl slots`: lists ordered slot IDs, names, triggers, and matches,
  marking fallback matches.
- `keyboardctl slot add [<number|source-id>] [--name N]`: without a source,
  lists numbered unassigned input sources; with one, adds a slot and assigns
  the first free trigger from Left Command, Right Command, Left Option,
  Right Option, Left Control. When all are occupied, the slot has no trigger;
  use `bind` to assign one. Shift is never assigned automatically because many
  Chinese input sources use a Shift tap to toggle English/Chinese. Right Control
  is also manual-only because laptop keyboards lack it.
- `keyboardctl slot remove <slot>`: removes its bindings, preferences and custom
  color. The last slot cannot be removed.
- Slot queries accept an exact ID first, then a unique case-insensitive ID or
  name. Deleted or unknown slots fail with exit code 1; they are never redirected.
  `bind <trigger> <slot>` retains trigger-stealing behavior and reports when the
  previous slot is left without a trigger.

New slots prefer the chosen source and fall back by its **primary** language.
An input source cannot be assigned as two slots' first preferred source, but
fallbacks and legacy rules may resolve multiple slots to it: both still work,
and `diagnose` reports `duplicate with: <ids>`. Existing matching rules remain
unchanged. First launch detects slots only when the config is missing; refreshing
sources does not replace existing slots or triggers.

In Settings, **Reset to Detected** asks for confirmation before
replacing all slots and triggers with detected defaults. Unrelated settings,
including general indicator preferences, are preserved. Before saving, the GUI
backs up the original file to `config.json.before-reset.bak` beside the config;
subsequent resets use unique backup names rather than overwriting earlier ones.
If backup or save fails, the reset is not applied.

Quit the GUI before editing configuration with the CLI, then reopen it: the
running GUI does not watch the file and could overwrite CLI changes.

Config lives at:

```text
~/.config/cmd-ime/config.json
```

### Configuration upgrade and downgrade

Version 2 stores an ordered `slots` collection with stable IDs, names and tints.
Old configurations migrate in memory on load. `show`, `slots`, `diagnose`,
`switch` and `listen` do not save the migration or print an upgrade notice.
Each successful write (`bind`, `remap`, `slot add`, `slot remove`, or
`init --force`) backs up a file lacking `slots` to `config.json.v1.bak` alongside
it, then prints a note to stderr. This also covers version-2 files whose `slots`
key was dropped by an older binary. If the backup already exists, a fresh
`config.json.v1.bak.<uuid>` is created; earlier backups are never reused or
overwritten. The note reports the new backup path. Backup failure prevents saving.
Legacy IDs and bindings are preserved on migration.

Before downgrading, quit CmdIME and restore the backup named in the latest
migration note to `config.json` (keep a separate copy of your version-2 settings).
After repeated upgrades, that backup may have a UUID suffix; the original
`config.json.v1.bak` still holds the first migration's settings. Old binaries cannot decode custom
slot IDs and may move that config to `.corrupt.<uuid>` and reset it. Even with
only legacy IDs, an old binary drops `slots` on save, losing names/tints and
potentially restoring removed legacy slots on the next upgrade.

## Build

```sh
swift test
./script/build_and_run.sh
```

For local development, `script/build_and_run.sh` signs the generated app bundle
after staging it. It uses the first local Apple Development or Developer ID
signing identity it can find, then falls back to ad-hoc signing. You can set
`CODESIGN_IDENTITY` to choose a specific identity:

```sh
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./script/build_and_run.sh
```

The shipped app stays native SwiftUI/AppKit. React is useful for web prototypes
or a future optional settings surface, but it does not replace the macOS APIs
CmdIME depends on for global keyboard listening, Accessibility/Input Monitoring
permissions, login items, or input-source switching.

Mac App Store distribution needs a separate sandboxed App Store build. See
[docs/app-store.md](docs/app-store.md).

## Package And Release

```sh
CMDIME_ALLOW_UNNOTARIZED=1 ./script/package_app.sh 0.4.1
shasum -a 256 dist/CmdIME-0.4.1.zip
```

Notarized release packaging requires a `Developer ID Application` signing
identity. For an explicitly labelled unnotarized preview, set
`CMDIME_ALLOW_UNNOTARIZED=1`.

One-time notarization setup:

```sh
security find-identity -p codesigning -v
xcrun notarytool store-credentials "cmd-ime-notary" \
  --apple-id "YOUR_APPLE_ID" \
  --team-id "YOUR_TEAM_ID" \
  --password "APP_SPECIFIC_PASSWORD"
```

The package script signs with Developer ID, submits the zip to Apple notary
service, staples the ticket to `CmdIME.app`, rebuilds the distributable zip, and
prints the SHA-256. Use `CMDIME_NOTARY_PROFILE` if your keychain profile is not
named `cmd-ime-notary`.

Update `Casks/cmd-ime.rb` with the release zip SHA-256 before publishing a
Homebrew cask. The cask links `keyboardctl` through `Contents/Resources`, which
is a compatibility symlink to the signed helper in `Contents/MacOS`.

CmdIME can check recent GitHub Releases from **General > Check for Updates** in
Settings, including explicitly labelled preview releases. When a new
version is available, open the release page and reinstall with the one-line
installer or update through Homebrew. Fully automatic in-app replacement is left
to a future Sparkle-based updater so signing and macOS permission behavior stay
predictable.

## Homebrew

Recent Homebrew versions require casks to be installed from a tap and reject
direct raw GitHub or local cask file paths. Use this repository as a custom tap:

```sh
brew tap ShunmeiCho/cmd-ime https://github.com/ShunmeiCho/cmd-ime
brew install --cask ShunmeiCho/cmd-ime/cmd-ime
```

The cask includes Homebrew's `unsigned_accessibility` caveat because preview
builds are not Developer ID signed. Homebrew documents that this caveat tells
users they may need to re-enable Accessibility after updates.

If a dedicated `homebrew-cmd-ime` tap repository is added later, this cask can
be copied there for the shorter `brew tap ShunmeiCho/cmd-ime` flow.

## Project Shape

- `Sources/KeyboardSwitcherCore`: config, shortcut parsing, input-source scan,
  matching, switching, and global event tap logic
- `Sources/CmdIME`: AppKit background app with a SwiftUI settings window
- `Sources/keyboardctl`: CLI for scan, config, switching, and listener mode
- `script`: local run and release package scripts
- `Casks`: Homebrew cask template

## Support

If CmdIME saves you a little keyboard friction, you can support the project at
[buymeacoffee.com/shunmeicor7](https://buymeacoffee.com/shunmeicor7).

You can also star the repository:
[github.com/ShunmeiCho/cmd-ime](https://github.com/ShunmeiCho/cmd-ime).
