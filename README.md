# AC Notch

iPhone-style autocorrect for the Mac. When you misspell a word in any app, two options
appear: what you typed and the fix (`“teh” | the`). Correctly spelled words show nothing,
unless **Suggest Word Completions** is on. On Macs with a notch, the notch grows "wings": the main
word (what space will type) on the left, the two alternatives on the right.

```
   the   [ notch ]   “teh”
```

**It follows your text cursor.** By default the strip appears as a frosted `“teh” | the`
capsule right next to the blinking cursor: below it when you're typing near the top of the
screen (a browser's search bar), above it near the bottom (a chat box). The cursor is its
home: if it's ever in the way, drag it somewhere else and it stays there until you press
**⌃⌥H** (Control + Option + H), which sends it gliding back to the cursor. In a browser's
address bar it sits on the notch instead, and never autocorrects there, since words are often
web addresses. Turn off
**Follow Text Cursor** in the menu to keep it on the notch instead.

**On the notch, drag it anywhere.** Pull the strip off the notch and it breaks free into a floating,
frosted-glass `“teh” | the` capsule. Drop it wherever your eyes are (near a chat box, a search bar)
and it stays there. Drag it back near the notch and it snaps home, or use **Dock Back to Notch**
in the menu.

Macs without a notch get a notch-shaped pill instead (`“teh” | the`), or turn on
**Preview Notch Layout** in the menu to see the wings around a pretend notch.

- Press **space** or punctuation and a misspelled word is fixed automatically.
- Press **backspace** straight after a fix to undo it.
- **Click** a suggestion to use it.
- **⌃⌥Space** (Control + Option + Space) turns it on or off. The menu bar icon does too.
- It's off by default in terminals and code editors, and you can turn it off per app from the menu bar.

Everything runs on your Mac using Apple's built-in spell checker. Nothing you type is sent anywhere.

Requires macOS 12 or later. Works on both Intel and Apple Silicon Macs.

## Install (no Xcode needed)

1. Download **ACNotch.zip** from the [Latest build release](../../releases/tag/latest-build)
   (or from the newest run under the **Actions** tab).
2. Unzip it and drag **AC Notch.app** into **Applications**.
3. **Right-click** the app and choose **Open**, then **Open** again. The app isn't signed with a
   paid Apple developer account, so this is only needed the first time.
4. When asked, open **System Preferences → Security & Privacy → Privacy → Accessibility**,
   unlock it, and tick **AC Notch**. It starts working within a couple of seconds.

**Updating to a new build:** macOS treats every build as a new app. In the Accessibility list,
select the old **AC Notch** entry, remove it with **−**, then open the new app and tick it again.

## Building

GitHub Actions builds the app on every push (`.github/workflows/build.yml`). To build it
yourself on a Mac with the Swift toolchain, run:

```
./scripts/build-app.sh
```
