# CmdIME Demo Videos

This folder contains the rendered demo videos for CmdIME and the HyperFrames
composition behind the install video.

## Visual Direction

The demos use the Native Pro Utility direction from `DESIGN.md`: light macOS
neutral canvas, graphite utility surfaces for keyboard/popover moments,
restrained motion, role colors that match the app, and material-style switch
indicators.

The local UI exploration draft is treated as a visual reference, not source
markup. The videos borrow its switch slots, keycaps, menu-bar popover
structure, indicator bubble, and permissions onboarding ideas while avoiding
the full dashboard density.

## Rendered Videos

| Video | Length | Output |
| --- | ---: | --- |
| Promo: one key per input source (0.6, Switcher / Glass / Liquid Glass themes) | 29s | [cmdime-promo.mp4](renders/cmdime-promo.mp4) |
| Install and permissions demo | 30s | [cmdime-install-permissions-demo.mp4](renders/cmdime-install-permissions-demo.mp4) |

GitHub-friendly README assets:

- [Install and permissions poster](renders/poster-install-permissions.png)
- [Promo GIF preview](renders/preview-promo.gif)
- [Install and permissions GIF preview](renders/preview-install-permissions.gif)

## GitHub Publishing

GitHub can host MP4 files, but repository pages and READMEs are not a reliable
inline video player. Use the poster or GIF preview in `README.md`, and link it
to the full MP4 uploaded as a GitHub Release asset.

```md
[![CmdIME demo: one key per input source](demo-videos/renders/preview-promo.gif)](demo-videos/renders/cmdime-promo.mp4)

[Open the full demo video](demo-videos/renders/cmdime-promo.mp4)
```

Recommended commit policy:

| File | Commit to repo? | Purpose |
| --- | --- | --- |
| `renders/poster-*.png` | Yes | Reliable README thumbnail |
| `renders/preview-*.gif` | Yes, if under about 10 MB | Inline motion preview |
| `cmdime-*.mp4` | Prefer GitHub Release asset | Full-quality video |

YouTube is optional. Use it for public marketing, captions, analytics, or easy
sharing outside GitHub. For the project README, Release assets plus a thumbnail
or GIF keep the repository self-contained.

## Composition Projects

- The promo (`renders/cmdime-promo.mp4`) is cut from real screen recordings of the
  app (Switcher, Glass and Liquid Glass indicator themes) with authored titles; it
  has no composition project in this folder.
- `install-permissions/`: 30-second motion graphic covering preview
  distribution, install paths, Gatekeeper, and macOS permissions.

## Commands

Run checks before rendering:

```sh
cd demo-videos/install-permissions
npm run check
npx hyperframes render -o ../renders/cmdime-install-permissions-demo.mp4 -q standard
```

Extract poster frames:

```sh
ffmpeg -y -ss 00:00:14 -i demo-videos/renders/cmdime-install-permissions-demo.mp4 \
  -frames:v 1 -update 1 demo-videos/renders/poster-install-permissions.png
```

Create compact GIF previews:

```sh
ffmpeg -y -i demo-videos/renders/cmdime-promo.mp4 \
  -vf "fps=10,scale=720:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=80[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5" \
  demo-videos/renders/preview-promo.gif

ffmpeg -y -i demo-videos/renders/cmdime-install-permissions-demo.mp4 \
  -vf "fps=8,scale=720:-1:flags=lanczos,split[s0][s1];[s0]palettegen=max_colors=96[p];[s1][p]paletteuse=dither=bayer:bayer_scale=5" \
  demo-videos/renders/preview-install-permissions.gif
```
