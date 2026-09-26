# AC Notch

iPhone-style autocorrect for the Mac. While you type in any app, three suggestions
show at the top of the screen. On Macs with a notch, the notch grows "wings": the main
word (what space will type) on the left, the two alternatives on the right.

```
   the   [ notch ]   “teh” | ten
```

Macs without a notch get a notch-shaped pill instead (`the | “teh” | ten`), or turn on
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
