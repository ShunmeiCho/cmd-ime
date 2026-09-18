# CmdIME

A macOS agent that switches the active input method from keyboard triggers, so a user who types in several languages can jump straight to the one they want.

## Language

**Slot**:
One user-facing switch target that a trigger can be bound to. It names a preferred input source and falls back to another input source of the same language when the preferred one is missing.
_Avoid_: Role (internal name only), mode, language

**Input Source**:
One concrete, selectable input method or keyboard layout installed on the system.
_Avoid_: IME, keyboard, input method (when the layout/method distinction does not matter)

**Trigger**:
The keyboard gesture bound to a slot: either a one-shot modifier tap or a key-press chord.
_Avoid_: Shortcut, hotkey

## Dynamic slots (PR1)

The ordered `config.slots` collection stores stable `InputRole` string IDs,
display names and tints. `InputRole` remains the internal type name; JSON keeps
`role` and `inputSources`. Fresh GUI setup and CLI `init` use
`SwitcherConfig.detected(from:)`: one slot per primary language in system source
order. The first five triggers are Left Command, Right Command, Left Option,
Right Option and Left Control; later slots are unbound. If no selectable source
has a usable primary language, `.default` retains the legacy English/Chinese/
Japanese setup, including Option+J. Existing configurations remain unchanged.

New slots pin one source and derive `fallbackLanguage` from its primary language.
Legacy preference rules are preserved. Assignment rejects only another slot's
first preferred ID; fallback/legacy resolution may duplicate another slot and
both keep working. CLI diagnosis exposes those duplicates. See ADR 0001.

CLI supports listing, adding and removing slots and querying by ID or unique
case-insensitive name. The GUI renders dynamic slots; GUI management/notice is
PR2; PR3 implements source-detected first-run defaults. Added slots get the first
free Command/Option/Left Control tap, never automatic Shift or Right Control.

GUI Reset to Detected confirms replacement of all slots and triggers while
preserving unrelated settings, including general indicator preferences. It
backs up the original file to `config.json.before-reset.bak` (unique subsequent
backups) before saving; failure leaves the reset unapplied. CLI `init --force`
replaces the entire config with detected defaults through the existing save
path, without an additional before-reset backup. Plain `init` refuses to
overwrite an existing config. Refreshing sources never rebuilds existing slots.

Migration is in-memory until save. Before overwriting a file lacking `slots`,
ConfigStore preserves it once as `config.json.v1.bak`; backup failure aborts the
save. Only successful CLI writes print the migration note, including version-2
files missing `slots`. Restore the backup before downgrading: older binaries
reject custom IDs or discard the collection. CLI edits require quitting and
reopening the GUI because configuration hot reload is not implemented.
