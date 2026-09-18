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
`role` and `inputSources`. Default initialization still uses English, Chinese,
and Japanese with the existing triggers.

New slots pin one source and derive `fallbackLanguage` from its primary language.
Legacy preference rules are preserved. Assignment rejects only another slot's
first preferred ID; fallback/legacy resolution may duplicate another slot and
both keep working. CLI diagnosis exposes those duplicates. See ADR 0001.

CLI supports listing, adding and removing slots and querying by ID or unique
case-insensitive name. The GUI renders dynamic slots; GUI management/notice is
PR2 and source-detected first-run defaults are PR3. Added slots get the first
free Command/Option/Left Control tap, never automatic Shift or Right Control.

Migration is in-memory until save. Before overwriting a file lacking `slots`,
ConfigStore preserves it once as `config.json.v1.bak`; backup failure aborts the
save. Only successful CLI writes print the migration note, including version-2
files missing `slots`. Restore the backup before downgrading: older binaries
reject custom IDs or discard the collection. CLI edits require quitting and
reopening the GUI because configuration hot reload is not implemented.
