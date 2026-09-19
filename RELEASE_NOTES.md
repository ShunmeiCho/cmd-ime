## CmdIME v0.7.0 Preview

The settings window gets a Liquid look and follows light and dark.

### New

- **A settings window that follows the macOS appearance.** The window was always dark. It now follows the system, in light and in dark, and **General > Appearance** pins it to **Light** or **Dark** or returns it to **System**. Every panel it opens follows along: General, the slot menus, the colour and font pickers and the shortcut recorder.
- **Liquid look.** The window sits on a system material, so a little of the desktop shows through, and the status and update bars use Liquid Glass on macOS 26 and later. Slot cards stay close to opaque so slot colours and text keep their contrast. With Reduce Transparency on, everything turns opaque.
- **Readable status colours in light mode.** Success, warning and danger colours, and the Quit CmdIME label, have darker light-mode values.

### Fixes

- The window's rows no longer slide up underneath the title bar while scrolling.
- Under **Theme**, a note explains why the thumbnails can differ from the window: the switch indicator appears over other apps, so it follows the macOS appearance rather than this window's. It shows only when the two differ.

### Known limits

- Checked on macOS 27 only. Before macOS 26 the bars use the translucent surface instead of Liquid Glass; that path was not run on a real system.

## CmdIME v0.6.4 Preview

The slot menus open every time.

### Fixes

- **Single tap, Double tap and the other slot menus always open.** These controls were a system menu laid over a drawn field, and the menu only reacted to clicks on part of that field, so a click often did nothing. The whole field is now a button, and the choices open in a small panel below it. This covers Single tap, Double tap, the input-source picker, Add Slot, Manage, the slot's "…" actions and the theme actions.
- **A slot whose input source was removed says "Source missing".** After uninstalling an input method, its slot falls back to another source of the same language. Both slots were then marked "Duplicate", including the one that had done nothing wrong. Now only the slot that lost its source is marked, as "Source missing", and the slot it fell back onto stays clean. Two slots that name the same source on purpose are still marked "Duplicate".

## CmdIME v0.6.3 Preview

Updates tell you what they change, and you decide how often CmdIME looks for them.

### New

- **What an update changes, right beside Update Now.** The update bar at the top of the settings window now shows the release's opening sentence and the title of each change, taken from the release notes that the update check already downloads. **Release Notes** still opens the full text in the browser.
- **Choose how often CmdIME checks.** **General** has **Every 6 hours / Daily / Weekly** under **Check automatically**. The default moves from once a day to every six hours, so a fix reaches an app that rarely shows a window the same day. Each check is one anonymous request to GitHub for the newest release; nothing else is sent.
- **Notify me about updates.** A switch in **General** turns the system notification off while the update still shows in the settings window. macOS does not let an app change its own notification permission, so when notifications are blocked in System Settings the panel says so and offers **Open Notification Settings…**. Turning the switch on is also when macOS asks for permission, if it has not asked before.

## CmdIME v0.6.2 Preview

Switching to Google Japanese Input now lands in Hiragana.

### Fixes

- **Google Japanese Input no longer stays in Latin after a switch (#4).** After you had typed under ABC, switching to Google Japanese Input showed Hiragana in the menu bar while Latin letters kept coming out: selecting the source from the background left the input method detached from the app. For this input method CmdIME now presses the Kana key first, which enters Japanese through the system's own path, and selects the slot's source 60 ms later, so the right source wins even with several Japanese input methods installed. On a test Mac this took switches through the trigger from 1 of 16 to 12 of 12, and 12 of 12 with an Option+J shortcut. Other input methods keep the plain select with no added delay; azooKey and WeType Pinyin were measured before and after and did not change.

### New

- **Activation recipes.** If another input method shows the same symptom, add a recipe to `~/.config/cmd-ime/activation-recipes.json` instead of waiting for a release, then press Refresh in the settings window:

  ```json
  { "recipes": [
    { "sourceIDPrefix": "com.example.inputmethod", "strategy": "kanaThenSelect", "delayMs": 60 }
  ] }
  ```

  `keyboardctl scan` lists the source ids. Your recipes win over the built-in one, so `"strategy": "select"` switches the built-in recipe off. `kanaThenSelect` only applies to Japanese sources. Please report what worked in an issue so it can become built in.

### Known limits

- The Kana key is a real key event. In a remote desktop or virtual machine window it may reach the remote side; this was not tested.
- The **Switch** button in the settings window and `keyboardctl switch` still select the source directly.

## CmdIME v0.6.1 Preview

The switch indicator sits at the text caret again.

### Fixes

- **The indicator appears next to the insertion point.** An insertion point is a zero-width rectangle, and CmdIME treated that as "no caret" and fell back to the mouse pointer, so in apps such as TextEdit the bubble showed up near the pointer instead of above the caret. It now accepts a zero-width caret and only falls back to the pointer when an app reports no caret at all, or one outside every display.
- This is also the first release that 0.6.0 users can install with **Update Now**.

## CmdIME v0.6.0 Preview

Updates reach you without opening GitHub.

### Highlights

- **Update Now.** When a new version exists, the settings window shows it at the top and in General, with **Update Now**, **Release Notes** and **Skip**. Update Now downloads the release, checks it against the published SHA-256, verifies that the new app is validly signed by the same developer team, replaces the app in place and reopens it. Permissions carry over because the signing identity is the same.
- **Daily check with one notification.** CmdIME asks GitHub for the newest release at most once a day and posts one system notification per new version; clicking it opens the settings window. Notification permission is requested only when there is an update to announce. Turn the daily check off with **General > Check automatically**. Nothing but the release lookup is sent.

## CmdIME v0.5.1 Preview

Fixes the switch indicator appearing on the wrong display.

### Fixes

- **The indicator stays on the screen you are working on.** With an external display placed above the built-in one (or taller than it), the bubble appeared on that display instead of next to the caret. The caret position from the accessibility API was flipped around the wrong display's height; it is now converted around the primary display only. Setups with a single display, or with displays side by side at the same height, were not affected.
- An app that reports a caret outside every display now gets the bubble next to the pointer instead.

## CmdIME v0.5.0 Preview

The switch indicator becomes themeable: twelve built-in looks including Glass, Liquid Glass, paper-and-ink styles and a switcher that slides between slots, plus your own themes and fonts.

### Highlights

- The switch indicator has a new default look, **Glass**: translucent glass that stays in its active appearance, a soft two-layer shadow, a faint light along the top edge, continuous corners, an opaque tile in the slot's colour with a bold glyph, and a bright title over a dimmer source name. It follows the system appearance with a light variant. Your stored Display, Size, Scale and Color values keep working unchanged.
- Built-in **themes**, chosen from live miniatures drawn for your own first slot: Glass, Classic, Paper One Ink, Paper Two Inks, Paper Slot Inks, Typographic, Tile, Line, Switcher and Switcher Slot Color. The two switcher themes show every slot side by side with a thumb that slides to the new one; beyond what fits in 320 points they become a three-cell carousel with a dot row.
- **Classic** keeps the previous bubble. Known differences: the material is always in its active look, corners are continuous, the width follows the content instead of a fixed 172 points, orange and teal tiles are deepened slightly so the white glyph stays legible, and the trailing padding and source-name opacity follow Glass.
- The bubble is measured from its content, so larger text never clips. It fades in with a few points of travel, a re-trigger while it is visible never dims it, and Reduce Motion, Reduce Transparency and Increase Contrast are each honoured.
- **Text**: font family (system designs, installed families, imported fonts), weight and text size belong to the theme. Changing them on a built-in theme creates an editable copy.
- **Custom themes**: Duplicate and Edit, Import, Export, Remove and Show in Finder. Themes are one JSON file each in `~/.config/cmd-ime/themes` (beside the config file when a custom config path is used). An invalid file is listed with its error and never blocks the others; a selected theme that disappears falls back to Glass and the settings say so. Text contrast below 4.5:1 shows a warning and is never blocked.
- **Custom fonts**: Import Font copies `.ttf`, `.otf` and `.ttc` files into `~/.config/cmd-ime/fonts` and registers them for CmdIME only; nothing is installed system-wide. A font that is removed falls back to the system font and the settings say so. Files dropped into either folder by hand are picked up after a relaunch.
- **Symbols work for any language set**: non-Latin scripts get a representative glyph per language, a single Latin-script slot shows `A`, and two or more show their language codes, so a glyph can change from `A` to `EN` when a second Latin-script slot is added. Slots that still share a glyph get a small mark. Each slot's symbol can be overridden with one or two characters from the indicator settings. Titles use the language's own name unless you renamed the slot, and right-to-left languages lay out right to left.
- **One colour per slot.** The Custom color option is retired: the bubble, the slot card and the live keys all read the slot's own colour, which is edited on the slot card. On the next save a config that used Custom copies each per-slot custom colour into that slot's tint, writes `"switchIndicatorColorStyle": "role"` and `"switchIndicatorCustomRoleColorHexes": {}`, and leaves `switchIndicatorCustomColorHex` as it was. Slots that had no per-slot custom colour keep their own tint, so a config that used one custom colour for every slot now shows each slot's colour; Accent, Mono or a one-ink theme are the closest replacements.
- Selected swatches and theme cells are marked with a fixed high-contrast ring and a checkmark, never with the option's own colour.
- The paper themes' ink palette and print rules are adapted from the mono-color skill by Yan Liu (MIT).
- **Liquid Glass.** Two more built-in themes, **Liquid Glass** and **Switcher, Liquid**, use the system's Liquid Glass material on macOS 26 and later and fall back to the Glass look on earlier systems. With Reduce Transparency or Increase Contrast they turn solid.
- **One highlight colour on glass.** In the theme editor, "Color from" is now **Each slot** or **One color**; with One color on a glass or liquid theme you pick the tile or switcher-thumb colour from the ink presets or any custom colour. Surface can be switched between Glass, Liquid and Paper.
- The indicator **Scale** now goes down to 40% (it was 65%); use the theme's Text size to keep small bubbles readable. The switcher themes stop shrinking earlier, where their cells would otherwise fall under their own text, and the Scale slider shows that limit.
- Your own themes show a remove button on their tile (and "Move to Trash" on right-click); the file goes to the Trash, so it can be put back.
- **General is a panel, not a menu.** The status bar's General button opens a small panel with Launch at login, the update check and its result, Show Setup Guide, the support and GitHub links, and Quit CmdIME. "Open Release Page" appears only when an update exists.
- The indicator's Font control is a searchable list instead of a menu, and the Display, Size and Color controls have room around their labels.
- In the setup guide, Return confirms the detected slots and finishes the guide once every slot was tried; long trigger sentences no longer wrap early.
- Twelve built-in themes in total. The theme picker's miniatures and the settings preview approximate glass; the real material shows on an actual switch.

## CmdIME v0.4.1 Preview

Layout fixes for the 0.4 settings window.

### Fixes

- **General moved to the top.** Launch at Login, Check for Updates, Show Setup Guide and Quit CmdIME are now a **General** menu in the status bar, so none of them needs scrolling to the bottom of the page. The "keeps running after this window closes" hint sits under the status bar.
- **No empty well under the source list.** The input sources panel and the slots panel share one height.
- **Live keys is a small keyboard.** It spans the full width below the board: both Shift keys on the upper row with your shortcuts between them, and Control, Option, Command around the space bar on the lower row.
- The sources panel's "Keyboard Settings…" button stays on one line, and its hint text wraps instead of being clipped.
- The General menu also links to the project's support page and the GitHub repository.
- README updated for the slot board, the three optional triggers, the setup guide and the new icon.

## CmdIME v0.4.0 Preview

The settings window becomes a slot board: add, reorder, rename and recolor slots directly, set Single tap, Double tap and Shortcut triggers side by side, and get a guided first run. The app icon is new.

### Highlights

- **Slot board.** Settings now has two panels: installed input sources on the left, your slots on the right. Drag a source into the slot list (or use **Add Slot**) to create a slot; drag a slot's handle to reorder; Esc cancels a drag. The "..." menu offers Move Up / Move Down, Rename, Color and Remove Slot, and the same actions are available to VoiceOver and the keyboard. Removing a slot shows **Undo** until the next slot change; Undo restores the slot, its triggers, color and position.
- **Three optional triggers per slot.** Single tap and Double tap are menus of the eight physical modifier keys (left and right Command, Option, Control, Shift); Shortcut records a modifier plus a key in a small popover with explicit Cancel and Save. Any trigger you set switches to that slot; leave the rest empty. A key already used for the same gesture by another slot, or by a key remap, is shown as used and cannot be picked. The same key can be a single tap for one slot and a double tap for another. While a shortcut is being recorded, tap triggers are paused so recording never switches the input source.
- **One color per slot.** Click the slot badge to pick one of eight presets or any custom color. The badge, the source list, Live keys and the switch indicator all follow it.
- **The source list stays current.** Adding or removing an input source in System Settings updates the list without a relaunch, new sources are marked "New", and a Refresh button is always available. Removed sources now disappear reliably: the list is taken by a short-lived `keyboardctl scan --json` process because a long-running process can keep seeing sources that were already removed, and the listener resolves switch targets from that same snapshot.
- **"Current" means the system's selected input source**, whether you switched with CmdIME, the menu bar or another tool. The per-slot **Switch** button selects a source directly; it does not test the trigger.
- Clearer structure: one status bar (listener state, permissions, Pause), Live keys as the footer of the slot panel, the switch indicator across the full width, and a compact **General** section with Quit CmdIME, Launch at login, updates and the setup guide. Text follows three type roles, controls look like controls at rest, and the window works at 720 points wide.
- Existing users see a one-line, dismissible "New in 0.4" notice instead of the setup guide.
- New app icon: an "A / 文" switcher capsule.
- Release builds record the real SDK version again in the binary (0.2.1 and 0.3.0 recorded 13.0), matching how 0.2.0 was built.
- New installs open with a three-step **Setup guide** card at the top of Settings: allow keyboard access, check what was detected, try it. The other sections stay folded behind one-line bars until the guide is finished or skipped; every bar can be opened by hand, so Quit and the slot board are never out of reach.
- Step 1 explains what Accessibility and Input Monitoring are each used for, opens the exact System Settings pane, and flips to Ready while System Settings is still in front where macOS reports the change to a running app. Both permissions and a running listener are required before advancing; a paused or stopped listener offers Resume or Start Listening. When macOS only applies a grant to a fresh process, or the listener cannot start although both permissions are ready, the guide offers **Relaunch CmdIME** (the app is reopened only after the old process has exited).
- Step 2 lists every slot as a sentence built from the real bindings, for example "Tap Left Command alone -> English (ABC)", covering taps, double taps and chords. **Change** opens the slot board. It names the slots that currently lack a trigger, separately from the policy that first detection assigns at most five keys. It also covers a Mac with a single input source and a lone Shift trigger that may clash with an input method's own Shift toggle.
- Step 3 is a practice field: only successful event-tap triggers tick a sentence and name the next trigger to try. Direct Switch buttons and system-side input-source changes do not count. Evidence expires when its slot is removed or its bindings or input-source preference change; unrelated appearance changes keep progress. A slot whose input source is not installed is named as such and does not count. CmdIME keeps running without a menu bar icon; reopening the app from Spotlight or the Applications folder shows Settings, and General > Quit CmdIME stops it. The return hint also stays visible in General after Finish or Skip.
- Privacy wording in the guide states what the event tap does: key events are checked in memory, by key code and modifier state, only to spot triggers; what you type is never stored or sent.
- The guide appears only for configs created by a first GUI launch (`hasCompletedSetup: false`). Existing config files, an unreadable config that was reset to defaults, and configs written by `keyboardctl` never show it. **General > Setup guide > Show** replays it at any time without folding anything.
- Steps are labelled groups, status changes are announced to VoiceOver, every action is a button, and motion follows Reduce Motion.

## CmdIME v0.3.0 Preview

Switch slots become a customizable, ordered collection: CmdIME detects them from the installed input sources on first run, migrates existing config files with a backup, and fixes the shortcut recorder.

### Highlights

- Switch slots are now an ordered, customizable collection. Use `keyboardctl slots`, `slot add [<number|source-id>] [--name N]`, and `slot remove <slot>`; the GUI renders configured slots.
- Fresh GUI setup and `keyboardctl init` now detect one slot per primary language in system source order. The first five slots use Left Command / Right Command / Left Option / Right Option / Left Control; later slots have no trigger. If no selectable source has a usable primary language, the legacy English/Chinese/Japanese defaults remain the fallback (including Option+J for Japanese). Existing configs and triggers are unchanged.
- GUI **Reset to Detected** requires confirmation, replaces all slots and triggers, and preserves unrelated settings such as general indicator preferences. It backs up the original config to `config.json.before-reset.bak`, using unique names on subsequent resets; backup or save failure prevents applying the reset. CLI `init --force` instead replaces the entire config with detected defaults using the existing save/migration path, without this additional reset backup.
- New slots prefer a selected input source and fall back to another with the same primary language. Assignment rejects a source already used as another slot's first preference; duplicate resolutions remain usable and are reported by `diagnose` (`duplicateSlots` in JSON, alongside `slot` and `name`). Legacy matching rules are preserved.
- Slot indicator colors now follow each slot's stored tint rather than the matched source's language.
- Added slots use the first free Left Command / Right Command / Left Option / Right Option / Left Control tap, or remain unbound when none is free. Shift is never automatically assigned: many Chinese input sources use Shift to toggle English/Chinese. Right Control remains manual-only.
- Configuration upgrades to version 2 in memory. Every successful write backs up a file lacking `slots` to `~/.config/cmd-ime/config.json.v1.bak` (beside the config when using `--config`), using a fresh `config.json.v1.bak.<uuid>` if the canonical backup exists (never reusing or overwriting earlier backups), and CLI writes print an upgrade note with the new backup path. Read commands do not save the migration or print that note; backup failure prevents saving.
- **Downgrade warning:** quit the app and restore the backup named in the latest migration note before running an older binary (it may have a UUID suffix after repeated upgrades). Custom slot IDs can make older versions move the config to `.corrupt.<uuid>` and reset it; even legacy-only configs lose the `slots` collection on an old binary's save and deleted slots can return. Preserve a separate version-2 copy first.
- Choosing an input source that another slot already uses now swaps the two slots; for a slot with no source yet, used sources are shown as "used by <slot>" instead of failing silently.
- The shortcut recorder no longer traps the keyboard (Tab and Shift+Tab leave it), shows "Press shortcut" while recording, and lets you record a chord that is already bound: it explains which slot or remap owns it instead of switching the input source. Rejected triggers, failed tests and rejected source assignments are explained on the slot card.
- Input sources are labelled by their primary language, so layouts such as German or French are no longer shown as English.
- The live keys strip is drawn from the real bindings: each bound modifier key takes its slot's color (left and right Shift are now shown), chord triggers appear as their own keycaps, and nothing is colored by default assumptions any more.
- Quit the running GUI before CLI edits and reopen afterward; it does not hot-reload configuration and can overwrite those edits.

## CmdIME v0.2.1 Preview

CmdIME removes the menu bar status icon, makes CLI switching verifiable, adds a diagnosis command, and keeps the event tap responsive while a switch is confirmed.

### Highlights

- Fixed a dead end for users without a Chinese or Japanese input source: a slot that shows "Not matched" now offers the input source menu, so any slot can be pointed at any installed input source (for example Korean or German). Previously the only control was "Fix", which rescans by language and could not help.
- Removed the menu bar status icon, its menu, and the `showMenuBarIcon` setting. Settings is opened by launching `CmdIME.app` again; quit via Settings > "Quit agent" or `keyboardctl quit`.
- `keyboardctl switch` now confirms that the switch took effect and exits non-zero with an error message on `stderr` if macOS did not apply the change.
- Added `keyboardctl diagnose [--json]` to inspect each slot's configured preferences (`preferredIDs`, `languagePrefixes`, `nameContains`), the matched input source, and the match reason (`preferredID`, `fallbackLanguage`, `languagePrefix`, `nameContains`, or `none`).
- The event tap no longer blocks the run loop while confirming an input-source switch; confirmation retries are scheduled asynchronously on the main queue, and newer switches supersede older pending switches.
- Left and right modifier keys are now tracked by physical keycode (`pressedModifierKeyCodes`), ensuring accurate side-specific modifier transitions even when aggregate modifier flags remain active.

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
