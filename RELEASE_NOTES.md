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
