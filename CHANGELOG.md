# Changelog

Each version's section is shown in the in-app update window and on the GitHub release.

## 1.12.0

- **Command palette**: press **⌃⌥Space** from any app to find and run anything: apps, Menew actions (mute, dark mode, keep awake, screenshot…), window layouts, snippets, notes and recent clipboard items. Type “brightness 60” or “awake 2h” to set a value directly. Your recent picks come first, and you can change the shortcut in Settings → Shortcuts. Also in the right-click menu.

## 1.11.0

- **Window manager**: snap the front window to halves (⌃⌥ + arrows), corners (⌃⌥ U I J K), thirds (⌃⌥ D F G, E T), maximize (⌃⌥↩), center (⌃⌥C) or back to its old size (⌃⌥⌫). ⌃⌥⌘→ sends it to the other display. There's also a grid of layouts in Actions. Already use Rectangle or similar? Turn the shortcuts off in Settings → Shortcuts.
- **No more surprise update windows**: when a new version is found in the background, Menew no longer opens a window over your work. It shows a small dot on its menu bar icon, and the next click on the icon shows what's new with an Install and Relaunch button. Choose Later and it installs the next time Menew quits.

## 1.10.0

- **Display brightness**: a slider for every screen in Actions, including external monitors from other brands over DDC/CI (Apple Silicon).
- **Mute the microphone** from any app with **⌃⌥⌘M** (change it in Settings → Shortcuts), with a quick on-screen confirmation. Mute the sound too.
- **Hide the Dock** with one switch in Actions.
- **GPU usage** in the Processor card and a new **Disk** card with live read and write speed.

## 1.9.1

- Fixed pasting (⌘V) and the other editing shortcuts (⌘C, ⌘X, ⌘A, ⌘Z) not working in notes and other text fields.
- Protected notes now ask for Touch ID again every time: they lock when you leave the note, close the menu, lock your Mac or it goes to sleep. Before, a protected note stayed open until you quit Menew.

## 1.9.0

- **Welcome tour**: new installs get a short, 5-step introduction: pick your modules, choose what shows in the menu bar, allow Accessibility (optional) and learn the shortcuts. See it again anytime in Settings → Help.
- **Optional modules**: turn off Clipboard, Actions or Notes in Settings → Modules and their tab disappears. With Clipboard off, Menew stops reading the clipboard and ⌘⇧V does nothing.
- The menu bar icon now has a VoiceOver label.

## 1.8.1

- Tidier Settings: Help links are now even rows, and the shortcut recorders and the history size control use the same glass style as the rest of the app.

## 1.8.0

- **Ignore apps the easy way**: in Settings → Clipboard, pick apps from the ones open right now or choose any app in Applications. No more typing bundle IDs. Remove one with a click.

## 1.7.3

- Fixed the menu opening too high on macOS 26 and later, covering the menu bar and hiding the top of the window. It now opens right below the menu bar again.

## 1.7.1

- Fixed content covering the header and tabs when scrolling on macOS 26. Liquid Glass now stays on the fixed controls (tabs, search, filters, buttons), and scrolling content uses a clean translucent card.

## 1.7.0

- **Liquid Glass everywhere**: Clipboard, Snippets, Notes, Free up space and Settings now share the glass tabs, search fields, filter chips and buttons from macOS 26.
- **Redesigned Settings**: clean glass sections, a theme picker with icons and simple menus for language and auto-delete.
- The menu bar preview in Settings now shows your Mac's real values and updates live.
- A softer highlight for the selected clipboard item.

## 1.6.2

- Fixed cards sliding over the header and tabs when scrolling on macOS 26.

## 1.6.1

- **A cleaner Actions tab**: switches like Dark mode, Keep awake, Hidden files and Desktop icons now show what's on right now, and they follow changes you make elsewhere in macOS.
- **Keep awake for a while**: 30 minutes, 1, 2 or 4 hours, and it shows until when.
- Every action says what it does. Hover for a longer explanation.
- **Liquid Glass** look on macOS 26 and later, with a translucent style on older versions.
- Eject disks shows how many are connected, and the Empty Trash confirmation is now translated.

## 1.5.0

- **Memory pressure**: see whether your Mac actually needs more memory, plus how much is used by apps, the system, compression and swap.
- **Battery details**: health, charge cycles and the charger's wattage.
- **Quit processes** right from the list: hover and click ✕, or right-click to force quit.
- **Alerts** (off by default, turn them on in Settings): a nearly full disk, low battery, critical memory pressure, or CPU stuck above 90% for 2 minutes.
- **Your menu bar, your way**: pick any mix of CPU, a mini CPU graph, memory, network, disk and battery, with a live preview.
- Sizes now follow the app's language (for example 824.4 GB in English).

## 1.4.2

- A nicer install window: drag Menew to Applications on a clean, branded background.

## 1.4.1

- **Report a problem** and **Suggest an idea** in the right-click menu and in Settings. They open GitHub with your Menew and macOS versions already filled in; you review everything before sending.

## 1.4.0

- **Many notes, organized with #tags**: write `#work` or `#ideas` anywhere in a note and filter by it.
- **Markdown**: switch between editing and reading. Headings, **bold**, lists, quotes, code and clickable `- [ ]` checklists.
- **Protected notes** for sensitive stuff: the content lives in the macOS Keychain and opens with Touch ID or your Mac password.
- Search across all notes. Your existing note was kept as the first one.
- Update notes now show up right here, instead of the GitHub page.

## 1.3.0

- **Free up space**: a quick scan clears app caches, logs and developer junk. A deep scan also finds old downloads and large files for you to review, and those go to the Trash.
- **Snippets**: save texts you reuse and paste them from ⌘⇧V. `{date}`, `{time}` and `{clipboard}` are filled in when you paste.
- **Custom shortcuts** for the clipboard history and the Menew menu.
- **Auto-delete** clipboard items older than 1, 7, 30 or 90 days. Pinned items always stay.
- **Automatic updates**, like the one you're seeing now.
- **Homebrew**: `brew install --cask menew` (see the README).
- See which apps use the most memory and quit them in one click.

## 1.2.4

- Menew now speaks **English, Português, Deutsch, Español and 中文**. It follows your Mac's language, or pick one in Settings.
- First version signed and notarized by Apple: it opens without warnings.
- Light, dark or automatic theme.
- Clearer quick action icons in both themes.

## 1.1.0

- Cleaning mode: lock the keyboard or black out the screen while you clean.
- Internet speed test, public IP and Bluetooth battery levels.
- Quick notes.
- New design for the menu and the ⌘⇧V panel.

## 1.0.0

- First version: system monitor, clipboard history with search (⌘⇧V) and quick actions.
