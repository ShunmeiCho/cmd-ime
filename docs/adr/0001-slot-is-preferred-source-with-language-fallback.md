---
status: accepted
---

# A slot is a preferred input source with a same-language fallback

Slots are becoming user-defined (two, three, five or more) instead of the fixed English / Chinese / Japanese set, so a slot needs a meaning that does not depend on a built-in language. We decided that a slot names one preferred input source, picked from the installed list, and falls back to another input source of the same language when the preferred one is missing; the settings UI says when a fallback is in use. Users never edit matching rules: the fallback is derived from the chosen source's language. The three-tier rules in existing config files (`preferredIDs`, `languagePrefixes`, `nameContains`) are kept as-is on migration so old files, the CLI and hand-written configs keep working. Two slots may not resolve to the same input source; the UI reports the conflict.

## Considered Options

- Pinned source only: an uninstalled input method leaves the slot unmatched and its trigger dead until the user re-picks. Simplest model, but a silent dead key after uninstalling or reinstalling an input method.
- Keep the three-tier rule as the user-facing model: most flexible, but forces users to understand IDs and language prefixes to bind a key, which is the problem being solved.
