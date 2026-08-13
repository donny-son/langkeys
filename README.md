# LangKeys

A tiny macOS menu bar app: tap a modifier key **on its own** to jump straight to a specific
keyboard input source. Hold the same key as part of a shortcut (⌘C, ⌥←) and nothing happens.

Out of the box, Right ⌘ and Right ⌥ are mapped to your first two input sources — change them
from the menu.

## Build & install

```sh
./build.sh --install     # builds, copies to /Applications, launches
./build.sh               # just builds build/LangKeys.app
```

Then grant **System Settings → Privacy & Security → Accessibility → LangKeys**. The app polls
every two seconds, so it starts working as soon as the toggle flips — no relaunch needed.

## Using it

The menu bar shows the current input source's flag (🇺🇸, 🇰🇷, …), falling back to a language code
for languages with no obvious country. Clicking it gives you:

- a row per modifier key (Right/Left ⌘ ⌥ ⇧ ⌃ and Fn) with a submenu of your enabled input
  sources — pick one, or None to unassign
- **Enabled** — pause the key handling without quitting
- **Open at Login** — registers the app as a login item via `SMAppService`

The icon dims when the app is paused or missing Accessibility permission.

## How it works

`EventTapController` installs a listen-only `CGEvent` tap on `flagsChanged`, `keyDown`, and mouse
downs. Press and release are distinguished by the device-dependent flag bit for each physical key
(`ModifierKey.flagBit`), so left and right keys are tracked separately. A pending modifier is
discarded the moment any other key, mouse click, or second modifier arrives; only a clean
press→release fires `TISSelectInputSource`.

The tap is listen-only, so it never delays or swallows your keystrokes. If macOS disables it for
being slow, the callback re-arms it.

## App icon

`Resources/AppIcon.icns` is the 🎏 emoji rendered to a full iconset. Swap it for any other emoji with:

```sh
swift scripts/make-icon.swift 🐙 && ./build.sh --install
```

## Notes

- The app is ad-hoc signed with a fixed identifier (`so.dou.langkeys`) so the Accessibility grant
  survives rebuilds. If macOS ever stops trusting it after a rebuild, remove and re-add it in the
  Accessibility list.
- Mappings live in `UserDefaults` under `so.dou.langkeys`.
- Requires macOS 13+.
