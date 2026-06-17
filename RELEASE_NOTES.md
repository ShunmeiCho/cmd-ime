## CmdIME v0.1.11 Preview

CmdIME v0.1.11 improves input-source switching reliability, configuration recovery, shortcut handling, and the settings UI.

This is an unnotarized preview release.

### Highlights

- Improved input-source switch confirmation and clearer failure messages.
- Reduced key-trigger switch latency on the global keyboard listener path.
- Fixed shortcut matching when Caps Lock or Fn is active.
- Removed Caps Lock as a single-tap trigger because macOS treats it as a latching key.
- Added safer config recovery: unreadable config files are backed up before CmdIME resets to defaults.
- Improved settings layout, scrolling, and switch indicator customization.
- Added update check support in Settings.

### Install

Recommended install command with version and SHA-256 verification:

```sh
CMDIME_VERSION=0.1.11 CMDIME_SHA256=b3ae83d20266197e302ee3b472ad578b8286df8e6eef277667c50ababdec8dfd /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ShunmeiCho/cmd-ime/v0.1.11/script/install.sh)"
```

Direct download SHA-256:

```text
b3ae83d20266197e302ee3b472ad578b8286df8e6eef277667c50ababdec8dfd  CmdIME-0.1.11.zip
```

Manual verification:

```sh
shasum -a 256 CmdIME-0.1.11.zip
```

### Preview Notice

This build is signed with an Apple Development certificate and is not notarized. Browser downloads may show Gatekeeper warnings. The installer verifies the downloaded zip with SHA-256; the installer script is fetched over HTTPS from this repository tag.

### After Installing

CmdIME needs both macOS permissions:

- Accessibility
- Input Monitoring

Open CmdIME, grant both permissions in System Settings, then click Resume.
