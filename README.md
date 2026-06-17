# CmdIME

[![Swift](https://github.com/ShunmeiCho/cmd-ime/actions/workflows/swift.yml/badge.svg)](https://github.com/ShunmeiCho/cmd-ime/actions/workflows/swift.yml)
[![Release](https://img.shields.io/github/v/release/ShunmeiCho/cmd-ime)](https://github.com/ShunmeiCho/cmd-ime/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

CmdIME is a macOS input-source switcher inspired by `cmd-eikana`, but built for
configurable switch slots. The default setup targets English, Chinese, and
Japanese.

Default bindings:

- left Command switches to English
- right Command switches to Chinese
- Option+J switches to Japanese

The bindings are configurable, and CmdIME scans the input sources already
installed in macOS instead of hardcoding one keyboard layout.

## Support

If CmdIME saves you a little keyboard friction, you can support the project at
[buymeacoffee.com/shunmeicor7](https://buymeacoffee.com/shunmeicor7).

You can also star the repository:
[github.com/ShunmeiCho/cmd-ime](https://github.com/ShunmeiCho/cmd-ime).

## App Behavior

CmdIME is a background input-source agent. The settings window is only a control
panel: closing the window does not stop keyboard listening. Release builds are
packaged with `LSUIElement`, so the app does not appear in the Dock or app
switcher.

If `Show menu bar icon` is turned off, CmdIME keeps running in the background.
Open `CmdIME.app` again to bring the settings window back.

On macOS 26 and later, CmdIME disables the menu bar icon automatically to avoid
a system status-item layout issue that can freeze the settings window and drive
CPU usage very high. Open `CmdIME.app` again whenever you need Settings.

If you need to stop a hidden background instance, use:

```sh
keyboardctl quit
```

If the CLI is not linked yet, use:

```sh
pkill -x CmdIME
```

## Bindings

Each switch slot can use one of three trigger types:

- `Shortcut`: click the recorder field, then press a real keyboard shortcut
  such as `option+j`.
- `Single tap`: choose a side-specific modifier from the list.
- `Double tap`: choose a side-specific modifier from the list.

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

## Build

```sh
swift test
./script/build_and_run.sh
```

The app needs Accessibility and Input Monitoring permissions before global
keyboard listening can work.

## Permissions Troubleshooting

macOS stores Accessibility and Input Monitoring approval against the app's code
identity. If you approve one rebuilt `CmdIME.app` and then run another copy from
`dist/`, `dist/release/`, or `/Applications`, macOS can treat it as a different
app and show the prompt again.

Use one stable app location when granting permissions:

1. Quit CmdIME.
2. Remove old `CmdIME.app` entries from System Settings > Privacy & Security >
   Accessibility and Input Monitoring.
3. Install or copy the app to the location you actually use, such as
   `/Applications/CmdIME.app`.
4. Open that exact app and grant both permissions.
5. Quit and reopen CmdIME.

If Japanese opens a kana palette instead of switching to Hiragana, refresh input
sources or update to CmdIME 0.1.10 or later. macOS exposes
`com.apple.50onPaletteIM` as a selectable Japanese source, but it is an
auxiliary kana palette, not the normal Hiragana input method.

For local development, `script/build_and_run.sh` signs the generated app bundle
after staging it. It uses the first local Apple Development or Developer ID
signing identity it can find, then falls back to ad-hoc signing. You can set
`CODESIGN_IDENTITY` to choose a specific identity:

```sh
CODESIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./script/build_and_run.sh
```

## Install

One-line install for users:

```sh
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ShunmeiCho/cmd-ime/main/script/install.sh)"
```

The installer downloads the public release zip, installs `CmdIME.app`, links
`keyboardctl`, and opens the app so macOS can request Accessibility and Input
Monitoring permissions.

### Verify the download (recommended)

The installer prints the downloaded archive's SHA-256. To make it abort on a
tampered or corrupted download, pin the version and pass the expected hash. Both
values are published in each release's notes, which also carry the exact,
copy-pasteable command:

```sh
CMDIME_VERSION=<version> CMDIME_SHA256=<sha256> /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ShunmeiCho/cmd-ime/main/script/install.sh)"
```

Pinning `CMDIME_VERSION` keeps the checksum and the downloaded zip in sync even
after a newer release becomes the latest. Without `CMDIME_SHA256` the installer
still prints the hash so you can compare it with the release notes manually.

### First launch and allowing access

The `curl | bash` installer and Homebrew do not quarantine the app, so it opens
directly and prompts for **Accessibility** and **Input Monitoring** the first
time. Grant both in System Settings > Privacy & Security.

The current public release is signed with an Apple Development certificate and is
not yet notarized. If you instead download the `.zip` from the GitHub Releases
page in a browser, macOS quarantines it and Gatekeeper may block it as
"CmdIME is damaged" or "cannot be opened because Apple cannot check it for
malicious software." To allow it:

- Open System Settings > Privacy & Security, scroll to the CmdIME message, and
  click **Open Anyway** (on macOS 15+, the old right-click > Open shortcut is
  gone); or
- Remove the quarantine attribute from a terminal:

  ```sh
  xattr -dr com.apple.quarantine /Applications/CmdIME.app
  ```

Prefer the one-line installer or Homebrew, which avoid the quarantine path
entirely.

CmdIME 0.1.11 and later can check recent GitHub Releases from Settings >
Runtime > Updates, including explicitly labelled preview releases. When a new
version is available, open the release page and reinstall with the one-line
installer or update through Homebrew. Fully automatic in-app replacement is left
to a future Sparkle-based updater so signing and macOS permission behavior stay
predictable.

Current preview releases may be unnotarized while Developer ID distribution is
not ready. Browser-downloaded preview zips can be blocked by Gatekeeper; the
one-line installer and Homebrew path avoid browser quarantine. For broader
distribution, sign the release with a Developer ID Application certificate and
notarize it.

## UI Technology

The shipped app stays native SwiftUI/AppKit. React is useful for web prototypes
or a future optional settings surface, but it does not replace the macOS APIs
CmdIME depends on for global keyboard listening, Accessibility/Input Monitoring
permissions, login items, or input-source switching.

Mac App Store distribution needs a separate sandboxed App Store build. See
[docs/app-store.md](docs/app-store.md).

## CLI

```sh
swift run keyboardctl scan
swift run keyboardctl init
swift run keyboardctl switch english
swift run keyboardctl bind left-command english
swift run keyboardctl bind right-command chinese
swift run keyboardctl bind option+j japanese
swift run keyboardctl bind double-left-command english
swift run keyboardctl remap right-control escape
swift run keyboardctl quit
swift run keyboardctl listen
```

Config lives at:

```text
~/.config/cmd-ime/config.json
```

## Package

```sh
./script/package_app.sh 0.1.11
shasum -a 256 dist/CmdIME-0.1.11.zip
```

Notarized release packaging requires a `Developer ID Application` signing
identity. While CmdIME is distributed as an explicitly labelled unnotarized
preview, set `CMDIME_ALLOW_UNNOTARIZED=1`:

```sh
CMDIME_ALLOW_UNNOTARIZED=1 ./script/package_app.sh 0.1.11
```

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

Browser-downloaded unnotarized preview builds are blocked by Gatekeeper and can
appear as "damaged" because they are not signed with Developer ID and notarized.
Label preview release notes clearly and publish the SHA-256 printed by the
package script.

Update `Casks/cmd-ime.rb` with the release zip SHA-256 before publishing a
Homebrew cask. The cask links `keyboardctl` through `Contents/Resources`, which
is a compatibility symlink to the signed helper in `Contents/MacOS`.

## Homebrew

Install from this repository cask:

```sh
brew install --cask https://raw.githubusercontent.com/ShunmeiCho/cmd-ime/main/Casks/cmd-ime.rb
```

Local cask test from a checkout:

```sh
brew install --cask ./Casks/cmd-ime.rb
```

After a GitHub release is published, the cask can also live in a Homebrew tap.

## Project Shape

- `Sources/KeyboardSwitcherCore`: config, shortcut parsing, input-source scan,
  matching, switching, and global event tap logic
- `Sources/CmdIME`: AppKit background app with a SwiftUI settings window
- `Sources/keyboardctl`: CLI for scan, config, switching, and listener mode
- `script`: local run and release package scripts
- `Casks`: Homebrew cask template
