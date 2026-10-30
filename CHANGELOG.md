# Changelog

Each version's section is shown in the in-app update window and on the GitHub release.

## 1.20.0

- **Next meeting**: turn it on in Settings → Calendar and your next meeting shows at the top of the menu, with a countdown and a **Join** button that opens the Zoom, Meet, Teams, Webex, Whereby, Jitsi, Chime or FaceTime link found in the event. Ongoing meetings show until they end; all-day, canceled and declined events are skipped.
- **1-minute reminder**: a notification right before the meeting starts. Click it to join.
- **From the command palette**: type “join” or “meeting”.
- It reads the Calendar app on your Mac (the accounts you already added there) and nothing leaves your Mac. macOS asks for calendar access only when you turn it on.

## 1.19.0

- **Text expander**: give a snippet an abbreviation like “;sig” and typing it in any app replaces it with the snippet's text, `{date}`, `{time}` and `{clipboard}` included. Turn it on in Settings → Clipboard (it's off by default and uses the Accessibility permission Menew already asks for).
- It never fires in password fields or in apps the clipboard ignores, doesn't trigger in the middle of a word, and puts back whatever you had copied, without adding the expanded text to the history. Menew only listens to the keyboard while it's on and at least one snippet has an abbreviation.

## 1.18.1

- **Better contrast in dark mode**: on macOS 26 the menu's glass turned light gray over bright windows behind it, and the white text was hard to read. It now keeps a dark tint behind the content, so it stays readable over any background.

## 1.18.0

- **Copy text from screen**: press ⌃⌥⌘T (or use the right-click menu or the command palette), select an area and its text goes straight to the clipboard: a video, a PDF, a screenshot, an error message. A “Reading text…” notice stays up until it's ready, then shows how many lines were copied.
- **Text from copied images**: in the clipboard history, the new “Copy text” button (or right-click → Copy text from image) pulls the text out of any image.
- Everything runs on your Mac with Apple's own text recognition, with no internet, and the screen capture is deleted right away. The shortcut can be changed in Settings → Shortcuts.

## 1.17.1

- **Much lighter in the background**: after you opened the System tab, Menew kept listing processes and redrawing its charts every 2 seconds even with the menu closed. Now nothing is drawn while the menu is closed. Idle use went from about 15% CPU and 66 MB to about 0.5% CPU and 16 MB.

## 1.17.0

- **Calculator in the command palette**: type a sum like “12*7.5”, “200 + 10%”, “20% of 340”, “2^10” or “√16” and the result shows at the top. Press ↩ to copy it.
- **Unit conversions**: length, weight, volume, data, time, speed, area and temperature, like “5 km to mi”, “72 f to c” or “1.5 gb to mb”.
- **Currencies**: “100 usd to brl”. Pressing ↩ fetches the day's European Central Bank rate (frankfurter.app, no account) and keeps it for 6 hours. It's the only part that uses the internet, and only when you ask.

## 1.16.0

- **Automations** (Actions → Automations): “when X happens, do Y”. Triggers: a time on chosen days, charger plugged in or out, battery below a level, an app opening or quitting, a display connecting or disconnecting. Actions: turn on a work profile, keep awake, mute or unmute the mic, light or dark mode, brightness, pause or resume the clipboard, open an app. Each rule shows a short notice when it runs, has a “Test now” button and runs at most once a minute. No scripts.

## 1.15.0

- **Quick shelf**: while dragging files, shake the mouse and a shelf appears next to the cursor. Drop files, folders, links, text or images on it, then drag them all out together (or one by one) to another app or folder. Items are always copied, so the originals never move. Also opens from the right-click menu and the command palette. Turn the shake gesture off in Settings → Shortcuts.

## 1.14.0

- **Keep awake, your way**: besides a timer, keep the Mac awake until a set time or while an app is open (it stops when the app quits). From the command palette too: “awake until 18:30”.
- **Pause the clipboard** for 15 minutes or an hour from the ⏸ button next to the search, so you can copy something private without saving it. It resumes on its own.
- **Heat alert**: an optional notification when macOS reports that your Mac is running hot (Settings → Alerts).
- **Keyboard and VoiceOver**: ⌘1–9 paste from the Clipboard tab too, ⌘, opens Settings, and icon-only buttons, switches and command palette results now have proper VoiceOver labels.

## 1.13.0

- **Work profiles**: arrange your windows, then save them as a profile in Actions → Profiles. One click (or its name in the command palette) opens the apps, puts every window back where it was and, if you want, keeps the Mac awake, mutes the mic, switches between light and dark mode and hides the other apps. Windows from a display that isn't connected move to the main one.

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
