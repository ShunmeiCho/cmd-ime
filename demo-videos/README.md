# CmdIME Demo Videos

This folder is the production workspace for short CmdIME demo videos.

HyperFrames composition HTML is intentionally not committed yet. The HyperFrames
workflow requires a visual identity (`DESIGN.md`) before authoring composition
HTML. Once the visual direction is confirmed, create the composition here and
render final videos into `demo-videos/renders/`.

## Planned Videos

### 1. Default Switching Demo

- Target length: 15 seconds
- Format: 16:9 landscape, 1920x1080
- Purpose: show why CmdIME exists and demonstrate deterministic switching
- README placement: near `What It Does`
- Output filename: `renders/cmdime-default-switching-demo.mp4`

Storyboard:

| Time | Beat | On-screen content |
| --- | --- | --- |
| 0-3s | Problem | macOS cycles through input sources; the target is not obvious |
| 3-7s | CmdIME model | Left Command -> English, Right Command -> Chinese, Option+J -> Japanese |
| 7-12s | Demo | Three quick switches with clear input-source labels |
| 12-15s | Close | Direct target switching for multilingual typing |

### 2. Install And Permissions Demo

- Target length: 30 seconds
- Format: 16:9 landscape, 1920x1080
- Purpose: reduce friction around preview distribution, Gatekeeper, and macOS permissions
- README placement: near `Install` or `First Launch And Permissions`
- Output filename: `renders/cmdime-install-permissions-demo.mp4`

Storyboard:

| Time | Beat | On-screen content |
| --- | --- | --- |
| 0-5s | Distribution status | Unnotarized preview, technical users, no Mac App Store |
| 5-12s | Install paths | Homebrew or pinned installer with SHA-256 |
| 12-20s | First launch | Open CmdIME and grant Accessibility + Input Monitoring |
| 20-27s | Gatekeeper | If browser zip is blocked, use Open Anyway only when you trust the release |
| 27-30s | Close | Use one stable app location to avoid permission churn |

## Visual Direction Questions

Answer these before generating HyperFrames composition HTML:

1. Mood: technical, premium, playful, cinematic, or warm?
2. Canvas: light, dark, or adaptive macOS-style neutral?
3. Brand direction: use only the current app icon colors, or introduce a second accent color?

## README Embed Template

Once rendered and committed, embed videos in `README.md` with a plain link first
and a GitHub-compatible HTML video block if the file size is reasonable:

```md
[Watch the default switching demo](demo-videos/renders/cmdime-default-switching-demo.mp4)

<video src="demo-videos/renders/cmdime-default-switching-demo.mp4" controls muted playsinline width="720"></video>
```

For large files, attach the rendered videos to GitHub Releases and link the
release asset instead of committing the binary.
