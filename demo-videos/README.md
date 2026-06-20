# CmdIME Demo Videos

This folder contains HyperFrames compositions and rendered demo videos for
CmdIME.

## Visual Direction

The demos use the Native Pro Utility direction from `DESIGN.md`: light macOS
neutral canvas, restrained motion, local graphite surfaces for keyboard/code
moments, role colors that match the app, and material-style switch indicators.

The local UI exploration draft is treated as a visual reference, not source
markup. The videos borrow its switch slots, keycaps, menu-bar popover
structure, indicator bubble, and permissions onboarding ideas while avoiding
the full dashboard density.

## Rendered Videos

| Video | Length | Output |
| --- | ---: | --- |
| Default switching demo | 15s | [cmdime-default-switching-demo.mp4](renders/cmdime-default-switching-demo.mp4) |
| Install and permissions demo | 30s | [cmdime-install-permissions-demo.mp4](renders/cmdime-install-permissions-demo.mp4) |

Poster frames:

- [Default switching poster](renders/poster-default-switching.png)
- [Install and permissions poster](renders/poster-install-permissions.png)

## Composition Projects

- `default-switching/`: 15-second motion graphic showing the default
  English/Chinese/Japanese direct switching model.
- `install-permissions/`: 30-second motion graphic covering preview
  distribution, install paths, Gatekeeper, and macOS permissions.

## Commands

Run checks before rendering:

```sh
cd demo-videos/default-switching
npm run check
npx hyperframes render -o ../renders/cmdime-default-switching-demo.mp4 -q standard

cd ../install-permissions
npm run check
npx hyperframes render -o ../renders/cmdime-install-permissions-demo.mp4 -q standard
```

Extract poster frames:

```sh
ffmpeg -y -ss 00:00:06 -i demo-videos/renders/cmdime-default-switching-demo.mp4 \
  -frames:v 1 -update 1 demo-videos/renders/poster-default-switching.png

ffmpeg -y -ss 00:00:14 -i demo-videos/renders/cmdime-install-permissions-demo.mp4 \
  -frames:v 1 -update 1 demo-videos/renders/poster-install-permissions.png
```
