<p align="center">
  <img src="docs/assets/icon.png" width="112" alt="Menew icon">
</p>

<h1 align="center">Menew</h1>

<p align="center">
  <b>Your Mac's menu bar, supercharged.</b><br>
  Command palette · System monitor · Clipboard history · Quick actions<br>
  Free, open source, native. No account, no telemetry.
</p>

<p align="center">
  <a href="https://github.com/Quost/menew/releases/latest"><img src="https://img.shields.io/github/v/release/Quost/menew?style=flat-square&color=7c5cff&label=download" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-111?style=flat-square&logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Quost/menew?style=flat-square&color=2ea44f" alt="MIT License"></a>
  <a href="https://github.com/Quost/menew/stargazers"><img src="https://img.shields.io/github/stars/Quost/menew?style=flat-square&color=f5c518" alt="Stars"></a>
</p>

<p align="center">
  <a href="https://menew.web.app/?ref=github"><b>Website</b></a> ·
  <a href="https://github.com/Quost/menew/releases/latest/download/Menew.dmg"><b>Download</b></a> ·
  <a href="CONTRIBUTING.md"><b>Contribute</b></a>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/panel0-dark.png">
    <img src="docs/assets/panel0-light.png" width="760" alt="Clipboard history with search, filters and preview">
  </picture>
</p>

## Features

| | |
|---|---|
| ⌨️ **Command palette** | Press <kbd>⌃</kbd><kbd>⌥</kbd><kbd>Space</kbd> anywhere to find and run any app, Menew action, window layout, snippet, note or copied item. Type “brightness 60” or “awake 2h”, and your recent picks come first. It also does math and conversions: “12*7.5”, “20% of 340”, “5 km to mi”, “72 f to c” and currencies like “100 usd to brl”. It also transforms the text you copied: UPPERCASE, lowercase, Title Case, camelCase, snake_case, kebab-case, remove accents, sort or dedupe lines, format or minify JSON, Base64 and URL encode/decode, and count characters and words, with a live preview. **On-device AI** (Apple Intelligence, macOS 26+): summarize, rewrite clearer, more formal, friendlier or shorter, fix spelling and grammar, or translate the copied text, using only the model on your Mac. For developers: decode a JWT, generate a UUID, copy the Unix timestamp or paste one to see the date. |
| 📊 **System monitor** | CPU and GPU with live graphs, memory pressure and swap, disk space and read/write speed, battery health, cycles and charger, uptime, thermal state and the top processes (quit them in one click). Pick what shows in the menu bar (CPU, CPU graph, memory, network, disk, battery) with a live preview. **World clocks** for the cities you work with sit at the top (Settings → World clocks), and the command palette converts times: “3pm ny to lisbon”, “15h em Lisboa”, “time in Tokyo”. |
| 📅 **Next meeting** | Your next meeting from the Calendar app at the top of the menu, with a countdown and a **Join** button that finds the Zoom, Meet, Teams or Webex link. Optional reminder 1 minute before; click it to join. Also from the command palette. Off by default. |
| 🔔 **Alerts** | Optional macOS notifications for a nearly full disk, low battery, critical memory pressure, CPU stuck above 90% or a Mac running hot. |
| 📋 **Clipboard history** | Text, links, images and files with instant search, filters, pins and a rich preview. Press **⌘⇧V** anywhere. Skips passwords and any app you pick to ignore, and you can pause it for 15 minutes or an hour. Copy the text inside any copied image with one click. **Paste queue**: turn it on, copy several things, then each <kbd>⌘</kbd><kbd>V</kbd> pastes the next one in the order you copied them; the count shows in the menu bar. |
| 🔆 **Display brightness** | A slider for every screen: the Mac's own display and external monitors over DDC/CI (Apple Silicon). Monitors that don't accept DDC (often because of a USB-C adapter or hub) are dimmed by software instead, remembered per monitor. |
| ⚡ **Quick actions** | Switches that show their live state: mute the microphone (**⌃⌥⌘M** from anywhere) or the sound, hide the Dock, dark mode, keep awake (for a while, until a set time or while an app is open), hidden files and desktop icons. One-click actions: color picker, plain-text clipboard, lock screen, eject disks, empty trash. **Copy text from screen** (**⌃⌥⌘T**): select an area and its text goes to the clipboard, recognized on your Mac with no internet. **Sound**: switch the output (AirPods, headphones, speakers, displays) and the microphone from Actions or the command palette. **Presentation mode**: hides desktop icons, keeps the Mac awake, pauses the clipboard and shows only the icon in the menu bar; turning it off undoes only what it changed. |
| 📸 **Screenshots** | Press **⌃⌥⌘S** to capture an area (Space for a window) or the whole screen from the command palette. Annotate with a pen, arrows, rectangles and text, blur sensitive data, then copy, save, drag into another app or **pin it floating on screen**. “Copy text” reads the text in it. |
| 🍅 **Focus timer** | Start 25 minutes from Actions (or any length: type “focus 50” in the command palette) and the time left shows in the menu bar. Optionally mute the mic, keep the Mac awake and pause the clipboard while you focus; when it ends, everything goes back the way it was, with a sound, a notification and a 5-minute break. Add 5 minutes or stop at any time. |
| 🪟 **Window manager** | Snap the front window to halves, corners, thirds or full screen with <kbd>⌃</kbd><kbd>⌥</kbd> shortcuts (the same as Rectangle) or from a grid in Actions. Send it to the other display, or put it back the way it was. |
| 🚪 **App control** | Quit all apps, quit everything but the one you're using, hide the rest, or force quit a frozen app, from Actions or the command palette. Quitting is a normal request, so apps with unsaved work ask first, and a “Never quit” list keeps apps like Music or Zoom open. **Ports in use** lists the servers running on your Mac (node, Docker, databases) so you can stop one; type “port” or “3000” in the palette too. |
| 🗂️ **Work profiles** | Save the apps you have open and where each window sits, then bring it all back with one click (or from the command palette). A profile can also keep the Mac awake, mute the mic, switch to dark mode and hide everything else. It can also quit every other app first, for a clean work mode. |
| 📥 **Quick shelf** | Shake files while you drag them and a shelf pops up next to the cursor. Drop files, links, text or images there, then drag them all out together to another app or folder. Items are always copied, so the originals never move. Also from the right-click menu or the command palette. With photos on the shelf, its image menu converts them to JPG, PNG or HEIC, shrinks them in bulk (3000 to 800 px) or removes location and metadata; results are new files next to the originals, ready to drag out. With PDFs, its PDF menu combines them, compresses them (the same “Reduce File Size” filter as Preview, keeping text selectable), rotates them or turns pages into PNG images; images can also be combined into one PDF. |
| ⚙️ **Automations** | “When X happens, do Y”: at a time on chosen days, when the charger is plugged in or out, when the battery drops below a level, when an app opens or quits, when a display connects, before a meeting starts, when a focus session starts or ends, when presentation mode turns on or off, or when the Mac wakes. Actions: turn on a profile, keep awake, mute the mic, light/dark mode, brightness, pause the clipboard, open an app, quit all apps (say, when the battery drops to 5%) or run one of your Shortcuts. No scripts, a notice when a rule runs and a “Test now” button. |
| 🗣️ **Siri, Shortcuts & Spotlight** | Menew's actions show up on their own, no setup: capture the screen, copy text from screen, mute the mic, keep awake, presentation mode, dark mode, start a focus timer, activate a work profile, create a note, open the clipboard history or the command palette. Say “Mute my microphone with Menew”, find them in Spotlight, or combine them in your own Shortcuts. In all five languages. |
| 🧽 **Cleaning mode** | Lock the keyboard for 2 minutes while you wipe it, or black out every screen to spot smudges. |
| 🌐 **Internet** | Live download/upload, local and public IP, and a real speed test powered by macOS `networkQuality`. **Apps using the network**: download and upload per app, read from macOS `nettop` only while you have the list open. |
| 🎧 **Devices** | Battery levels for AirPods (left, right, case), Magic Mouse, Keyboard and Trackpad. |
| 🧹 **Free up space** | Quick scan for caches, logs and developer junk; deep scan for old downloads, large files (over 250 MB) and duplicate files (identical copies, byte for byte; the oldest is kept as the original). You review everything, and your files go to the Trash. |
| ✂️ **Snippets** | Saved texts with `{date}`, `{time}` and `{clipboard}` placeholders, right inside ⌘⇧V. Give one an abbreviation like `;sig` and typing it in any app turns it into the text (optional, off by default; never in password fields). |
| 📝 **Notes** | Many notes with #tags, search and Markdown (checklists included). Protected notes live in the Keychain and open with Touch ID. **Password notes** keep name and value rows with hidden values, an eye to reveal and a copy button; copied values are marked confidential (no clipboard history) and cleared after 30 seconds. Switch a note's type at any time. |
| 🧩 **Only what you need** | A short welcome tour on first launch helps you set things up. Turn off Clipboard, Actions or Notes in Settings → Modules and they disappear completely (with Clipboard off, Menew doesn't even read it). Settings → Backup saves your settings, shortcuts, snippets, profiles and automations to a `.menew` file (notes and clipboard history optional) to restore later or on another Mac. |
| 🪟 **Liquid Glass** | Native macOS 26 design: glass tabs, search, filters and buttons, with a translucent fallback on macOS 14 and 15. |
| 🌍 **5 languages** | English, Português, Deutsch, Español and 中文. Follows your Mac, or pick one in Settings. |

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/popover-system-dark.png">
    <img src="docs/assets/popover-system-light.png" width="250" alt="System monitor">
  </picture>
  &nbsp;
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/popover-actions-dark.png">
    <img src="docs/assets/popover-actions-light.png" width="250" alt="Quick actions">
  </picture>
  &nbsp;
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/popover-clipboard-dark.png">
    <img src="docs/assets/popover-clipboard-light.png" width="250" alt="Clipboard">
  </picture>
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/palette-dark.png">
    <img src="docs/assets/palette-light.png" width="560" alt="Command palette">
  </picture>
</p>

## Install

**Homebrew:**

```bash
brew tap quost/menew https://github.com/Quost/menew
brew trust quost/menew
brew install --cask menew
```

Or **download** the latest [`Menew.dmg`](https://github.com/Quost/menew/releases/latest/download/Menew.dmg), open it and drag Menew to Applications.

Or **build from source** (needs Xcode 16+ or the Swift toolchain):

```bash
git clone https://github.com/Quost/menew
cd menew
./build.sh --install
```

### Permissions

| Permission | Why |
|---|---|
| **Accessibility** | Paste automatically after picking a clipboard item, expand snippet abbreviations as you type, advance the paste queue on ⌘V, and block keys in cleaning mode. Optional. |
| **Screen & System Audio Recording** | Screenshots and copying text from the screen. Asked the first time you capture; images stay on your Mac. |
| **Calendars** | Show your next meeting with a Join button. Only asked if you turn it on in Settings → Calendar; read on your Mac, never uploaded. |
| **Automation** (Finder, System Events) | Empty the trash and toggle dark mode. Asked the first time you use them. |

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>Space</kbd> | Open the command palette (customizable) |
| <kbd>⌘</kbd> <kbd>⇧</kbd> <kbd>V</kbd> | Open clipboard history (customizable) |
| <kbd>⌥</kbd> <kbd>⌘</kbd> <kbd>M</kbd> | Open the Menew menu (customizable) |
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>⌘</kbd> <kbd>M</kbd> | Mute / unmute the microphone (customizable) |
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>⌘</kbd> <kbd>T</kbd> | Copy text from screen (customizable) |
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>⌘</kbd> <kbd>S</kbd> | Capture the screen and annotate (customizable) |
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>←</kbd> <kbd>→</kbd> <kbd>↑</kbd> <kbd>↓</kbd> | Snap the window to a half |
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>U</kbd> <kbd>I</kbd> <kbd>J</kbd> <kbd>K</kbd> | Snap to a corner |
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>D</kbd> <kbd>F</kbd> <kbd>G</kbd> / <kbd>E</kbd> <kbd>T</kbd> | Thirds / two thirds |
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>↩</kbd> / <kbd>C</kbd> / <kbd>⌫</kbd> | Maximize / center / restore |
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>⌘</kbd> <kbd>→</kbd> | Move the window to the next display |
| <kbd>↩</kbd> / <kbd>⌥</kbd> <kbd>↩</kbd> | Paste / paste as plain text |
| <kbd>⌘</kbd> <kbd>1</kbd>…<kbd>9</kbd> | Quick paste |
| <kbd>⇥</kbd> | Next filter |
| <kbd>⌘</kbd> <kbd>P</kbd> / <kbd>⌘</kbd> <kbd>⌫</kbd> | Pin / delete |

## Performance

Menew only reads what it shows. With the menu closed it uses about **0.5% CPU, 19 MB of memory and 14 wakeups per second** on an Apple Silicon Mac (measured over 50 seconds with `top` and `footprint`, menu bar showing CPU, RAM and disk). GPU, disk activity, charts and the process list are only read while the menu is open, and timers let macOS batch their wakeups with other apps to save battery. The app is about 6 MB on Apple Silicon.

## Privacy

The app has **no telemetry, no analytics and no account**. Clipboard history and notes are stored locally in `~/Library/Application Support/Menew`. Items marked as passwords by password managers (`org.nspasteboard.ConcealedType`) are never saved. Values copied from password notes are marked the same way and cleared from the clipboard after 30 seconds. Backups are files you save yourself; protected notes are never included in them. The only network calls are the ones you can see: your public IP (`api.ipify.org`), the speed test you start yourself, a currency rate when you press ↩ on a conversion in the command palette (`api.frankfurter.app`, European Central Bank data), and a daily update check against this repo's releases (you can turn it off). Text recognition (copy text from screen or images) uses Apple's Vision framework on your Mac; nothing is uploaded, and the screen capture is deleted right after. AI text actions use only Apple's on-device model (never Private Cloud Compute), so the text stays on your Mac. The next meeting is read from the Calendar app through EventKit, only if you turn it on, and stays on your Mac.

The website ([menew.web.app](https://menew.web.app/?ref=github)) counts visits and button clicks with [GoatCounter](https://www.goatcounter.com), which uses no cookies and stores no personal data. The app itself never does this.

## Roadmap

- [x] Disk cleaner (quick and deep scans)
- [x] Custom keyboard shortcuts
- [x] Text snippets
- [x] Auto-delete clipboard items older than X days
- [x] Auto-updates with Sparkle
- [x] Homebrew cask
- [x] Memory pressure, battery health, alerts and a customizable menu bar
- [x] Optional modules and a first-launch tour
- [x] Window manager
- [x] Command palette
- [x] Work profiles (apps + saved window layouts)
- [x] Keep awake until a time or while an app is open, timed clipboard pause, heat alerts
- [x] Quick shelf for dragging files between apps
- [x] Simple automations (time, power and app triggers)
- [x] Calculator and unit conversions in the command palette
- [x] Copy text from the screen and from images (OCR, on device)
- [x] Text expander (snippet abbreviations)
- [x] Next meeting with a Join button
- [x] Focus timer
- [x] Text transforms in the command palette
- [x] Paste queue
- [x] Duplicate files in the cleaner
- [x] Network usage per app
- [x] App control (quit all, quit others, force quit)
- [x] Automations: meeting, focus and wake triggers, run a Shortcut
- [x] Password notes and switchable note types
- [x] Settings backup (export and restore)
- [x] Screenshots with annotations, blur and pinning
- [x] Sound output and microphone switcher, presentation mode
- [x] Developer kit: ports in use, UUID, timestamps, JWT
- [x] Image tools on the shelf (convert, shrink, strip metadata)
- [x] PDF tools on the shelf (combine, compress, rotate, pages to images)
- [x] World clocks and time zone conversion
- [x] Siri, Shortcuts and Spotlight actions
- [x] On-device AI text actions (summarize, rewrite, fix, translate)
- [ ] Your idea here

Ideas? [Open an issue](https://github.com/Quost/menew/issues/new).

## Feedback

Found a bug or have an idea? Use **Report a problem…** or **Suggest an idea…** in Menew's right-click menu (or in Settings → Help). It opens a GitHub issue with your Menew and macOS versions already filled in.

## Contributing

Pull requests are very welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for how the project is organized and how to run it.

## Support

Menew is free and made in spare time. If it saves you a few minutes a day, a ⭐ on GitHub or a coffee goes a long way.

<a href="https://buymeacoffee.com/quost"><img src="https://img.shields.io/badge/Buy%20me%20a%20coffee-ffdd00?style=for-the-badge&logo=buymeacoffee&logoColor=black" alt="Buy me a coffee"></a>

## License

[MIT](LICENSE) © Matheus Quost
