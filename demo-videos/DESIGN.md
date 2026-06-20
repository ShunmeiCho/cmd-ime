# CmdIME Demo Video Design

## Style Prompt

Design CmdIME demo videos as native premium macOS utility motion graphics for deterministic multilingual input-source switching. The product should feel precise, calm, trustworthy, and system-native. The tone is technical 60%, premium 30%, warm 10%. It should not feel like a flashy marketing page, a cyber-themed developer tool, or a playful consumer app.

Use the local UI exploration draft as visual reference, not as source markup.
Keep its strongest ideas: switch slots, keycaps, live keyboard visualization,
material indicator bubbles, menu bar information structure, and permissions
onboarding copy. Use graphite native-utility surfaces where they help the
videos feel like a focused macOS menu-bar tool. Do not copy the full dashboard
density, heavy glow, or oversized design-board layout into the demo
compositions.

## Colors

- Canvas: `#F5F5F7`, macOS grouped background.
- Card: `#FFFFFF`, elevated utility surfaces.
- Text primary: `#1D1D1F`.
- Text secondary: `#62666D`.
- Primary accent: `#2F7CF6`, CmdIME/app icon blue.
- English: `#4C8DFF`, slot blue.
- Chinese: `#FF5B57`, slot red.
- Japanese: `#46C46B`, slot green.
- Preview warning: `#C47A24`, soft amber.
- Graphite code surface: `#20242A`.

## Typography

- Use system-like typography: `SF Pro Display`, `SF Pro Text`, `-apple-system`, `BlinkMacSystemFont`, `Helvetica Neue`.
- Use `SF Mono` for commands and key labels.
- In renderable HyperFrames HTML, prefer generic `sans-serif` and `monospace`
  families unless local font assets are checked into the composition project.
- Keep headings large and calm, body text compact and readable.
- Avoid decorative, playful, cyber, or editorial display fonts.

## Motion

- Precise and restrained.
- Key press: 120-180ms.
- Indicator bubble reveal: 160-220ms fade + scale.
- Card transitions: 240-420ms, `power2` / `power3` easing.
- Scene transitions: soft cover/reveal or focus pull. No jump cuts.
- Avoid excessive bounce, neon glow, glitch, strong gradients, or cinematic camera moves.

## What NOT To Do

- Do not use cyberpunk, neon, purple-blue gradients, heavy bloom, or glitch transitions.
- Do not make the video feel like a landing page hero.
- Do not use hacker styling; graphite should feel native, quiet, and product-like.
- Do not over-animate interface elements that should feel stable and native.
- Do not show real private system settings or real user input.
