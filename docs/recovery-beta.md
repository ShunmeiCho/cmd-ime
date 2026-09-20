# Recovery (beta): put mistyped pinyin back into Chinese

You meant to type Chinese, the switch had not taken, and `nihao` is sitting in your document.
Recovery takes those letters back out, switches to your Chinese input source, and replays them so
the candidate window opens and you pick the word you meant.

**This is a beta with a deliberately small boundary.** It is measured in one editor with one input
source, and it refuses everywhere else rather than guessing. Read [Where it works](#where-it-works)
before turning it on.

## What one press does

1. Reads the run of latin letters immediately before the caret.
2. Refuses unless it reads as pinyin, so `hello world` is left alone.
3. Selects exactly that run, switches to the Chinese source, and replays the letters into it.
4. Your input source's normal candidate window opens. You choose the word.
5. **One Command+Z undoes the whole thing** and brings back the exact letters you typed.

Recovery never picks a candidate for you, never touches anything but that one run, and never
uses the clipboard.

## Where it works

| | status |
|---|---|
| TextEdit, with 微信输入法 (WeType Pinyin) | measured, works |
| Safari, Chrome, Electron editors | **refused** |
| Password fields, secure input | **refused** |
| Any other editor or input source | **refused** |

An editor gets onto that list by being measured on a real Mac: the run is replaced, the replay
actually composes, a candidate commits, and one Command+Z restores the original — both while
candidates are open and after a commit. Safari passes every part of that except the last one, so
it is refused. Details in the project's reliability notes.

When recovery refuses it says why, and it does this before reading or changing anything.

## What it measures at

Sixty runs through the trigger in TextEdit with WeType, alongside thirty plain switches as a
yardstick, on macOS 27.0:

| | attempts | failed |
|---|---:|---:|
| a plain switch, for comparison | 30 | 1 |
| recovery: the replay composed | 60 | 5 |
| recovery: one Command+Z restored the original | 60 | 1 |

## Known limits

- **Failures come in blocks.** Switching an input source is not reliable in the way a keypress is,
  and when it goes wrong it tends to go wrong several times in a row before working again. All five
  failures above were consecutive. Recovery inherits this: when the replay does not compose you get
  your latin letters back, unchanged, and nothing is lost — but it can happen a few times running.
  A short successful run does not mean the next one will work.
- **One Command+Z does not always finish the job.** Once in those sixty runs, undo took the Chinese
  back out but left the composition open with the pinyin still in it, instead of restoring the plain
  letters. Whether a second Command+Z recovers from that was not measured, because it did not happen
  again. This is the one part of the release gate recovery does not meet, and the reason it is a
  beta rather than a feature.
- **Full pinyin only.** Double pinyin, bopomofo, Cangjie, Wubi and Rime schemas are not covered.
- **Japanese romaji is not covered.**
- **One run, one word boundary.** Recovery stops at punctuation, digits, existing CJK text, a line
  break, or a double space.

## Turning it on

There is no setting for this yet — it is configured by hand, on purpose, while it is a beta.

1. Quit CmdIME.
2. Open `~/.config/cmd-ime/config.json` and add one entry to `bindings`:

```json
{
  "action": { "type": "recoverPinyin", "role": "chinese" },
  "enabled": true,
  "trigger": {
    "kind": "oneShotModifier",
    "keyCode": 60,
    "keyName": "right-shift",
    "modifiers": [],
    "gesture": "tap"
  }
}
```

3. Start CmdIME again.

`role` is the slot holding your Chinese input source — whatever `keyboardctl slots` prints in its
`id` column, usually `chinese`.

### Choosing the trigger

**Do not use `option`+letter.** In a password field macOS turns on secure keyboard entry, so no
event tap sees your keystroke — recovery correctly never runs, but it also cannot swallow the key,
and `option+r` types `®` into the password. The same key is also a common global shortcut in other
apps.

Pick something that produces no character. A tap on a modifier you have not bound is the simplest:

| key | `keyCode` | `keyName` |
|---|---|---|
| right shift | 60 | `right-shift` |
| left shift | 56 | `left-shift` |
| right control | 62 | `right-control` |
| left control | 59 | `left-control` |

Many Mac keyboards have no physical right control key. Check yours before choosing it.

## Turning it off

Quit CmdIME, delete that entry from `bindings`, start it again. There is no other state to clean up.

## If you go back to an older CmdIME

A build older than this one does not know the `recoverPinyin` action. Older builds than **0.8.0**
treat a binding they cannot read as a corrupt config: they move the whole file aside and start from
defaults, taking every other setting with it, without saying so.

**Before downgrading below 0.8.0, delete the recovery binding.** From 0.8.0 on, an unreadable
binding costs you that binding and nothing else, and the app tells you it happened.
