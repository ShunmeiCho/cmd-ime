# CmdIME

[![Swift](https://github.com/ShunmeiCho/cmd-ime/actions/workflows/swift.yml/badge.svg)](https://github.com/ShunmeiCho/cmd-ime/actions/workflows/swift.yml)
[![Release](https://img.shields.io/github/v/release/ShunmeiCho/cmd-ime)](https://github.com/ShunmeiCho/cmd-ime/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

CmdIME is a macOS input-source switcher inspired by `cmd-eikana`, but built for a
three-IME workflow: English, Chinese, and Japanese.

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

Each role can use one of three trigger types:

- `Shortcut`: click the recorder field, then press a real keyboard shortcut
  such as `option+j`.
- `Single tap`: choose a side-specific modifier from the list.
- `Double tap`: choose a side-specific modifier from the list.

Single-key modifier bindings and keyboard shortcuts are intentionally separate
so common shortcuts such as `Command+C`, `Command+V`, `Command+Tab`, and
multi-modifier chords are not treated as one-shot Command taps.

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

For broader distribution, sign the release with a Developer ID Application
certificate and notarize it.

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
swift run keyboardctl remap caps-lock escape
swift run keyboardctl quit
swift run keyboardctl listen
```

Config lives at:

```text
~/.config/cmd-ime/config.json
```

## Package

```sh
./script/package_app.sh 0.1.8
shasum -a 256 dist/CmdIME-0.1.8.zip
```

Release packaging requires a `Developer ID Application` signing identity. For a
local-only package smoke test on machines without that certificate, set
`CMDIME_ALLOW_UNNOTARIZED=1`. Do not publish local-only builds.

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
