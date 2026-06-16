# Contributing

Thanks for helping improve CmdIME.

## Development Setup

Requirements:

- macOS on Apple Silicon or Intel
- Xcode command line tools
- Swift toolchain bundled with Xcode

Run the focused checks before opening a pull request:

```sh
swift test
bash -n script/*.sh
ruby -c Casks/cmd-ime.rb
```

For local app testing:

```sh
./script/build_and_run.sh
```

The app needs Accessibility and Input Monitoring permissions for global
keyboard listening. Use one stable app location when granting permissions.

## Pull Requests

- Keep changes small and focused.
- Include tests for shortcut parsing, config behavior, and input-source matching
  when changing core behavior.
- Update `README.md` or `docs/` when changing install, packaging, or permission
  behavior.
- Do not commit local agent files, derived build output, release zips, or
  personal signing credentials.

## Release Packaging

Release packages are generated with:

```sh
./script/package_app.sh 0.1.2
shasum -a 256 dist/CmdIME-0.1.2.zip
```

The public cask SHA must match the release asset SHA.
