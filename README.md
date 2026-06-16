# CmdIME

CmdIME is a macOS input-source switcher inspired by `cmd-eikana`, but built for a
three-IME workflow: English, Chinese, and Japanese.

Default bindings:

- left Command switches to English
- right Command switches to Chinese
- Option+J switches to Japanese

The bindings are configurable, and CmdIME scans the input sources already
installed in macOS instead of hardcoding one keyboard layout.

## App Behavior

CmdIME is a menu bar agent. The settings window is only a control panel:
closing the window does not stop keyboard listening. Release builds are packaged
with `LSUIElement`, so the app does not appear in the Dock or app switcher.

If `Show menu bar icon` is turned off, CmdIME keeps running in the background.
Open `CmdIME.app` again to bring the settings window back.

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
swift run keyboardctl listen
```

Config lives at:

```text
~/.config/cmd-ime/config.json
```

## Package

```sh
./script/package_app.sh 0.1.0
shasum -a 256 dist/CmdIME-0.1.0.zip
```

Update `Casks/cmd-ime.rb` with the release zip SHA-256 before publishing a
Homebrew cask.

## Homebrew

Local cask test:

```sh
brew install --cask ./Casks/cmd-ime.rb
```

After a GitHub release is published, the cask can live in this repository or a
Homebrew tap.

## Project Shape

- `Sources/KeyboardSwitcherCore`: config, shortcut parsing, input-source scan,
  matching, switching, and global event tap logic
- `Sources/CmdIME`: SwiftUI menu bar app and settings window
- `Sources/keyboardctl`: CLI for scan, config, switching, and listener mode
- `script`: local run and release package scripts
- `Casks`: Homebrew cask template
