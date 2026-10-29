# ClipHistory

A menu bar app for Apple Silicon Macs that remembers everything you copy, like the clipboard history on Windows. Press **⌥V** and a small menu opens at the text cursor with the last 50 things you copied. Pick one and it's pasted where you were typing.

The history is kept in memory only, so it starts empty each time the Mac starts up and nothing you copied is ever written to disk.

## The menu

Press **⌥V** anywhere:

- Click an item, or use the arrow keys and Return, to paste it. **1–9** and **0** pick the first ten straight away. Escape closes the menu.
- Items paste back exactly as they were copied, with their formatting, line breaks, images and files.
- Text shows its first line, with the whole text in a tooltip. Images show a thumbnail and their size, and files show their icon and name.
- Passwords copied from a password manager are kept, but show as dots.
- Copying something that's already in the history moves it back to the top.
- **Clear History** empties the list.

The menu opens at the text cursor in apps that report where it is, and at the mouse pointer in apps that don't, such as many Electron apps.

Click the clipboard icon in the menu bar for **Show Clipboard History**, **Clear History**, **Open at Login** and **Quit**.

The app and its menus are in English and Italian, following your Mac's language.

## How it works

ClipHistory checks the clipboard a few times a second and saves each new copy in every format the app put it on the clipboard in. Copies larger than 32 MB are skipped, and so is anything an app marks as only on the clipboard for a moment.

⌥V is a system-wide hot key, which needs no permission. To paste, ClipHistory puts the item back on the clipboard, brings back the app you were in and presses ⌘V for you. Pressing ⌘V needs Accessibility access, and so does finding the text cursor. Without it, picking an item only copies it, and ClipHistory says so.

- ⌥V no longer types the character it normally makes, such as √.
- If another app already uses ⌥V, the menu bar menu says so.
- A password stays in the history even after your password manager clears it from the clipboard, until you clear the history, quit ClipHistory or restart the Mac.

## Install

Requires macOS 13 or later and the Xcode Command Line Tools (`xcode-select --install`).

```bash
git clone https://github.com/Veehementia/ClipHistory.git
cd ClipHistory
./scripts/install.sh
```

The script builds the app, moves it to `/Applications` and opens it. ClipHistory then asks for Accessibility access: turn it on in System Settings → Privacy & Security → Accessibility. Choose **Open at Login** from its menu so the history is there from the moment you log in.

The app is signed ad-hoc, so macOS treats every new build as a different app. The install script clears the old Accessibility permission each time, and you allow the new build again. To avoid this, sign with your own certificate:

```bash
SIGN_IDENTITY="Apple Development: Your Name (TEAMID)" ./scripts/install.sh
```

If the menu bar icon is dimmed, macOS doesn't trust ClipHistory for Accessibility. This can happen even when System Settings still shows it switched on. Choose **Reset Permission and Ask Again** from its menu, then allow it again.

To build without installing, run `./scripts/build.sh`. The app goes to `build/ClipHistory.app`, where Spotlight lists it as a second copy until you install or delete it.

## Uninstall

```bash
pkill -x ClipHistory; rm -rf /Applications/ClipHistory.app && tccutil reset Accessibility com.matteonardone.ClipHistory
```

## License

[MIT](LICENSE)
