# LangKeys

A tiny macOS menu bar app: tap a modifier key **on its own** to jump straight to a specific
keyboard input source. Hold the same key as part of a shortcut (⌘C, ⌥←) and nothing happens.

Out of the box, Right ⌘ and Right ⌥ are mapped to your first two input sources — change them
from the menu.

## Build & install

```sh
./build.sh --install     # builds, copies to /Applications, launches
./build.sh --dmg         # builds an ad-hoc signed DMG, for your own machines
./build.sh --release     # Developer ID + notarized DMG, for handing to other people
./build.sh               # just builds build/LangKeys.app
```

Then grant **System Settings → Privacy & Security → Accessibility → LangKeys**. The app polls
every two seconds, so it starts working as soon as the toggle flips — no relaunch needed.

Ad-hoc signed builds lose that grant whenever the binary changes, so expect to re-approve after a
rebuild. Builds from `--release` keep it, because the signature is stable.

## Distributing

Both DMG modes stage the app next to an `/Applications` symlink and run `hdiutil create`, giving
the usual drag-to-install window. The difference is the signature:

- `--dmg` is ad-hoc signed. Gatekeeper blocks it on anyone else's Mac (right-click → Open to get
  around it), so it is only useful locally.
- `--release` signs with your Developer ID under the hardened runtime, then notarizes. The result
  passes Gatekeeper cleanly: `spctl -a` reports `source=Notarized Developer ID`.

`--release` reads credentials from a gitignored `.env` (see `.env.example`):

```sh
APPLE_API_KEY=      # path to the App Store Connect .p8, or the key contents
APPLE_API_KEY_ID=
APPLE_API_ISSUER=
APPLE_TEAM_ID=      # picks the matching Developer ID cert out of your keychain
```

If `APPLE_API_KEY` holds the key text rather than a path, it is written to a `umask 077` temp file
and deleted on exit. The signing certificate is selected by SHA-1 hash, so a keychain holding
several identities stays unambiguous.

Notarization runs in **two passes**: the app is submitted and stapled first, then the DMG is built
from the stapled app, signed, submitted, and stapled in turn. Stapling only the DMG would leave an
app that fails to launch when it is copied out and first run offline.

## Using it

The menu bar shows the current input source's flag (🇺🇸, 🇰🇷, …), falling back to a language code
for languages with no obvious country. Clicking it gives you:

- a row per modifier key (Right/Left ⌘ ⌥ ⇧ ⌃ and Fn) with a submenu of your enabled input
  sources — pick one, or None to unassign — plus which side of the notch its flag pops out of
- **Enabled** — pause the key handling without quitting
- **Show Flag in Notch** — turn the notch flag off
- **Open at Login** — registers the app as a login item via `SMAppService`
- **Settings…** (⌘,) — the full settings window

The icon dims when the app is paused or missing Accessibility permission.

## Settings

Three tabs:

- **Keys** — every modifier key, its input source, and which side of the notch its flag uses
- **Notch** — turn the flag on or off, and choose whether it **stays visible** (the default, so
  the current input mode is always on screen) or **disappears** after an adjustable 0.5–6s
- **General** — pause switching, show/hide the menu bar icon, open at login, quit

**The menu bar icon can be hidden entirely.** When it is, open the settings window again by
launching LangKeys from Spotlight, Finder, or the Dock — a relaunch of the running app reopens
settings rather than starting a second copy (`applicationShouldHandleReopen`). Settings also open
automatically at launch when the icon is hidden, so the app is never unreachable.

## How it works

`EventTapController` installs a listen-only `CGEvent` tap on `flagsChanged`, `keyDown`, and mouse
downs. Press and release are distinguished by the device-dependent flag bit for each physical key
(`ModifierKey.flagBit`), so left and right keys are tracked separately. A pending modifier is
discarded the moment any other key, mouse click, or second modifier arrives; only a clean
press→release fires `TISSelectInputSource`.

The tap is listen-only, so it never delays or swallows your keystrokes. If macOS disables it for
being slow, the callback re-arms it.

## The notch HUD

On a switch, the black notch body stretches out one side and the flag springs out from behind it.
By default it stays there, so a glance at the notch tells you the current input mode; set it to
auto-hide in Settings → Notch. Right ⌘ shows 🇺🇸 on the left, Right ⌥ shows 🇰🇷 on the right; only
one flag is ever out, and switching sides mid-flight tucks the first one in first.

In the pinned mode the notch also follows switches made *outside* LangKeys — the input menu, ⌃Space,
another app — by watching the same system notification the menu bar item uses.

Preview it without pressing anything:

```sh
./build/LangKeys.app/Contents/MacOS/LangKeys --preview-notch
```

The window and notch geometry are adapted from [TheBoredTeam/boring.notch](https://github.com/TheBoredTeam/boring.notch):

- `NotchShape` — the notch silhouette (boring.notch's `NotchShape.swift`, itself from
  [DynamicNotchKit](https://github.com/MrKai77/DynamicNotchKit))
- `NotchGeometry` — notch width from `auxiliaryTopLeftArea`/`auxiliaryTopRightArea`, height from
  `safeAreaInsets.top`, following `getClosedNotchSize()`; falls back to a 185×32 pill on displays
  with no notch
- `NotchPanel` — a non-activating `NSPanel` at `.mainMenu + 3` with
  `[.fullScreenAuxiliary, .stationary, .canJoinAllSpaces, .ignoresCycle]`, mirroring
  `BoringNotchWindow`

The rest is ours: the body grows on one side only (width and offset animate together so the
opposite edge stays pinned to the real cutout), and the flag rides out on a slightly slower,
lower-damped spring so it lags the stretch. The flag view stays mounted while hidden — inserting
it on show would make it appear at its final position instead of sliding out.

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
