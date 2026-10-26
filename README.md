<p align="center">
  <img src="docs/assets/icon.png" width="112" alt="Menew icon">
</p>

<h1 align="center">Menew</h1>

<p align="center">
  <b>Your Mac's menu bar, supercharged.</b><br>
  System monitor · Clipboard history · Quick actions · Cleaning mode<br>
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
  <a href="https://menew.web.app"><b>Website</b></a> ·
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
| 📊 **System monitor** | CPU with live graph, memory, disk, battery, uptime, thermal state and the top processes. Live stats right in the menu bar. |
| 📋 **Clipboard history** | Text, links, images and files with instant search, filters, pins and a rich preview. Press **⌘⇧V** anywhere. |
| ⚡ **Quick actions** | Keep awake, hidden files, hide desktop icons, eject disks, empty trash, dark mode, color picker, screenshot to clipboard. |
| 🧽 **Cleaning mode** | Lock the keyboard for 2 minutes while you wipe it, or black out every screen to spot smudges. |
| 🌐 **Internet** | Live download/upload, local and public IP, and a real speed test powered by macOS `networkQuality`. |
| 🎧 **Devices** | Battery levels for AirPods (left, right, case), Magic Mouse, Keyboard and Trackpad. |
| 🧹 **Free up space** | Quick scan for caches, logs and developer junk; deep scan for old downloads and large files. You review everything, and your files go to the Trash. |
| ✂️ **Snippets** | Saved texts with `{date}`, `{time}` and `{clipboard}` placeholders, right inside ⌘⇧V. |
| 📝 **Notes** | A scratchpad that saves itself. |
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
| **Accessibility** | Paste automatically after picking a clipboard item, and block keys in cleaning mode. Optional. |
| **Automation** (Finder, System Events) | Empty the trash and toggle dark mode. Asked the first time you use them. |

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| <kbd>⌘</kbd> <kbd>⇧</kbd> <kbd>V</kbd> | Open clipboard history (customizable) |
| <kbd>⌥</kbd> <kbd>⌘</kbd> <kbd>M</kbd> | Open the Menew menu (customizable) |
| <kbd>↩</kbd> / <kbd>⌥</kbd> <kbd>↩</kbd> | Paste / paste as plain text |
| <kbd>⌘</kbd> <kbd>1</kbd>…<kbd>9</kbd> | Quick paste |
| <kbd>⇥</kbd> | Next filter |
| <kbd>⌘</kbd> <kbd>P</kbd> / <kbd>⌘</kbd> <kbd>⌫</kbd> | Pin / delete |

## Privacy

Menew has **no telemetry, no analytics and no account**. Clipboard history and notes are stored locally in `~/Library/Application Support/Menew`. Items marked as passwords by password managers (`org.nspasteboard.ConcealedType`) are never saved. The only network calls are the ones you can see: your public IP (`api.ipify.org`), the speed test you start yourself, and a daily update check against this repo's releases (you can turn it off).

## Roadmap

- [x] Disk cleaner (quick and deep scans)
- [x] Custom keyboard shortcuts
- [x] Text snippets
- [x] Auto-delete clipboard items older than X days
- [x] Auto-updates with Sparkle
- [x] Homebrew cask
- [ ] Your idea here

Ideas? [Open an issue](https://github.com/Quost/menew/issues/new).

## Contributing

Pull requests are very welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for how the project is organized and how to run it.

## Support

Menew is free and made in spare time. If it saves you a few minutes a day, a ⭐ on GitHub or a coffee goes a long way.

<a href="https://buymeacoffee.com/quost"><img src="https://img.shields.io/badge/Buy%20me%20a%20coffee-ffdd00?style=for-the-badge&logo=buymeacoffee&logoColor=black" alt="Buy me a coffee"></a>

## License

[MIT](LICENSE) © Matheus Quost
