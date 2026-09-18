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
