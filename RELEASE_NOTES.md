## CmdIME v0.1.12 Preview

CmdIME v0.1.12 improves input-source switching reliability, mouse-click handling, scanned input-source preferences, and the settings UI.

This is an unnotarized preview release.

### Highlights

- Moves mouse-down observation out of the active CGEventTap so slow input-source switching can no longer stall mouse clicks.
- Keeps mouse-down cancellation for one-shot modifier state through global and local NSEvent monitors.
- Sanitizes scanned preferred input-source IDs to avoid cross-role fallbacks such as Japanese sources leaking into English or Chinese slots.
- Caches TIS input-source handles to reduce per-switch enumeration work.
- Normalizes Runtime settings typography so status rows and permission rows use consistent text sizing.

### Install

Recommended install command with version and SHA-256 verification:

```sh
CMDIME_VERSION=0.1.12 CMDIME_SHA256=ed4b1e8230fb7ade55c97ef73e79558a81ea765fff9f60e04b0747e0c23d0fb8 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/ShunmeiCho/cmd-ime/v0.1.12/script/install.sh)"
```

Direct download SHA-256:

```text
ed4b1e8230fb7ade55c97ef73e79558a81ea765fff9f60e04b0747e0c23d0fb8  CmdIME-0.1.12.zip
```

Manual verification:

```sh
shasum -a 256 CmdIME-0.1.12.zip
```

### Preview Notice

This build is signed with an Apple Development certificate and is not notarized. Browser downloads may show Gatekeeper warnings. The installer verifies the downloaded zip with SHA-256; the installer script is fetched over HTTPS from this repository tag.

### After Installing

CmdIME needs both macOS permissions:

- Accessibility
- Input Monitoring

Open CmdIME, grant both permissions in System Settings, then click Resume.
