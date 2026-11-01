# 🎃 Pumpkin Porch

Candle-lit carved pumpkins for your Mac desktop. **Version 3.0**

 ![The six pumpkin faces](Virtual%20Pumpkin%20Porch%20v3/faces-preview.png)

- A row of pumpkins sits on a "porch" just above your Dock.
- Up to three little ones hop onto the top edge of whichever window is in front, and follow it when you switch or move windows.
- Point at a pumpkin and it gets a fright: a gentle wobble or a big jump.
- **Cute**, **spooky** or **mixed** faces.
- Bats with glowing eyes flap past: rarely, now and then, or in whole flocks.
- Clicks always pass straight through to whatever is underneath.

## The control panel

Click the 🎃 in the menu bar to open the control panel. It's an ordinary window: drag it anywhere, keep it open behind your other windows, or minimise it to the Dock, where it shows the pumpkin icon. While it's open, a little pumpkin sits on top of it and follows it around. Every change applies instantly.

| Section | Controls |
|---|---|
| **Pumpkins** | Faces (tap a preview), how many per screen (1–10), size, candle glow (off to bright), sit on windows (on/off, 1–3 pumpkins), bats (off, rare, normal, flock), fright reaction (gentle wobble, big jump), rearrange |
| **Behaviour** | Pause, hide in full-screen apps, start at login, remember my choices |
| **Look** | Panel theme: Halloween, System, Light or Dark |
| **Your data** | Data tracking on/off, open data folder, export, delete |
| **Pumpkin stats** | Your totals, plus About and Quit |

**Remember my choices:** when on, your settings come back the next time the app starts. When off, it starts with the defaults each time.

## Requirements

- A Mac with macOS 12 (Monterey) or later, Apple Silicon or Intel. *Start at login* needs macOS 13 or later.
- Apple's free Command Line Tools (the build step below installs nothing else)

## Install

1. Download this folder: **Code → Download ZIP**, then unzip it.
2. Open **Terminal**. If you have never installed Apple's developer tools, run `xcode-select --install` and click **Install** in the window that appears.
3. Type `cd ` (with a space), drag the unzipped folder into the Terminal window, and press **Enter**.
4. Run:

   ```
   bash build.sh
   ```

5. Double-click **Pumpkin Porch.app**, which appears in the same folder with its own pumpkin icon (made from `AppIcon.png`).

For *Start at login*, move the app into your **Applications** folder first.
To stop it, open the panel and click **Quit**.

**Updating from an earlier version:** quit the old app first, then build and open the new one. Your stats are kept.

## Your data and privacy

Pumpkin Porch can record how it is used, to support research on the app. Here is exactly how that works.

**It's opt-in.** On first launch, the app explains what it records and asks. Tracking stays **off** until you turn it on, and you can switch it on or off anytime in the panel.

**When tracking is on, the app records:**
- when the app starts and stops, and how long each session lasts
- every setting you change: which setting, from what, to what, and when (to the second)
- how often the control panel is opened and how long it stays open
- pausing and resuming, pumpkin frights, bats and hops onto windows
- the app version (including updates from one version to another), your macOS version and number of screens
- running totals of all of the above

Every record is tagged with a **random ID**. It is not your name or email, and it isn't derived from your Mac or your accounts.

**It never records** which apps, windows, websites or files you use, and never reads window titles or contents. It only looks at *where* the front window is, so the little pumpkins know where to sit.

**It stays on your Mac.** The app makes no network connections at all. Your data lives in:

```
~/Library/Application Support/Pumpkin Porch/
```

| File | What's in it |
|---|---|
| `events.jsonl` | One line per event, with timestamps to the second |
| `stats.json` | Running totals |
| `settings.json` | Your choices (only if *Remember my choices* is on), the tracking switch and the random ID |

**You're in control:**
- **Open data folder** shows the files.
- **Export my data** saves a copy to your Desktop as CSV and JSON, with a note explaining every field. Review it before sharing.
- **Delete my data** erases the stats and event log and gives your installation a new random ID.
- Turning tracking off stops all recording. What was already recorded stays until you delete it.

**Sharing is your choice.** You can keep your data to yourself, or share an export with the app's author to support research on the app.

## Credits

Inspired by [Fall Desktop](https://github.com/starrlord/FallDesktop) for Windows by starrlord. Pumpkin Porch is a separate, original Mac app and shares no code with it.

Written with the help of Claude.

## License

[MIT](LICENSE). Free to use, change and share. Provided "as is", without warranty of any kind.
