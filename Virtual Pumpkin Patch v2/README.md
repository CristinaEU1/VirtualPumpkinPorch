# 🎃 Pumpkin Porch

Candle-lit carved pumpkins for your Mac desktop.

![The six pumpkin faces](faces-preview.png)

- A row of pumpkins sits on a "porch" just above your Dock.
- Two little ones hop onto the top edge of whichever window is in front, and follow it when you switch or move windows.
- Point at a pumpkin and it gets a fright: it wobbles and its face goes "O!".
- **Cute** faces (smiles, blush, a sleepy one that snores) or **spooky** ones (classic jack-o'-lanterns, a toothy grin).
- Now and then a bat with glowing eyes flaps past.
- Clicks always pass straight through to whatever is underneath.

Everything is controlled from the 🎃 in the menu bar: pause, faces, how many pumpkins, sitting on windows, bats, stats and quit.

## Requirements

- A Mac with macOS 12 (Monterey) or later, Apple Silicon or Intel
- Apple's free Command Line Tools (the build step below installs nothing else)

## Install

1. Download this folder: **Code → Download ZIP**, then unzip it.
2. Open **Terminal**. If you have never installed Apple's developer tools, run `xcode-select --install` and click **Install** in the window that appears.
3. Type `cd ` (with a space), drag the unzipped folder into the Terminal window, and press **Enter**.
4. Run:

   ```
   bash build.sh
   ```

5. Double-click **Pumpkin Porch.app**, which appears in the same folder.

To start it automatically, add the app under **System Settings → General → Login Items**.
To stop it, click the 🎃 in the menu bar → **Quit Pumpkin Porch**.

## Privacy and stats

Pumpkin Porch keeps a few fun stats: how long it has been running, how many pumpkins you have frightened, bats flown past, hops onto windows, and time spent with cute or spooky faces.

- **The stats stay on your Mac. Nothing is ever sent anywhere.** The app makes no network connections at all.
- The app never records which apps or windows you use. It only looks at where the front window is, so the little pumpkins know where to sit.
- The stats live in a small, readable file:
  `~/Library/Application Support/Pumpkin Porch/stats.json`
- See them under 🎃 → **Pumpkin stats**, open the file with **Show stats file in Finder**, or clear them with **Reset stats**. Deleting the file also resets them.

## Credits

Inspired by [Fall Desktop](https://github.com/starrlord/FallDesktop) for Windows by starrlord. Pumpkin Porch is a separate, original Mac app and shares no code with it.

Written with the help of Claude.

## License

[MIT](LICENSE). Free to use, change and share. Provided "as is", without warranty of any kind.
