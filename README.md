<p align="center">
  <img src="docs/assets/icon.png" width="112" alt="Menew icon">
</p>

<h1 align="center">Menew</h1>

<p align="center">
  <b>Your Mac's menu bar, supercharged.</b><br>
  Command palette · Clipboard history · Window manager · Screenshots · System monitor · On-device AI<br>
  Free, open source, native. No account, no telemetry.
</p>

<p align="center">
  <a href="https://github.com/Quost/menew/releases/latest"><img src="https://img.shields.io/github/v/release/Quost/menew?style=flat-square&color=7c5cff&label=download" alt="Latest release"></a>
  <img src="https://img.shields.io/badge/macOS-14%2B-111?style=flat-square&logo=apple" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-SwiftUI-F05138?style=flat-square&logo=swift&logoColor=white" alt="Swift">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Quost/menew?style=flat-square&color=2ea44f" alt="GPL-3.0 License"></a>
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
| ⌨️ **Command palette** | Press <kbd>⌃</kbd><kbd>⌥</kbd><kbd>Space</kbd> anywhere to find and run any app, Menew action, window layout, snippet, note or copied item. Type “brightness 60” or “awake 2h”, and your recent picks come first. It also does math and conversions: “12*7.5”, “20% of 340”, “5 km to mi”, “72 f to c” and currencies like “100 usd to brl”. It also transforms the text you copied: UPPERCASE, lowercase, Title Case, camelCase, snake_case, kebab-case, remove accents, sort or dedupe lines, format or minify JSON, Base64 and URL encode/decode, and count characters and words, with a live preview. **Quick links**: “g coffee”, “gh menew”, “maps paulista”, “yt …”, “wiki …”, plus your own in Settings → Quick links (say “jira ABC-123” with `https://company.atlassian.net/browse/{q}`); a typed address like “github.com/quost” opens directly, and anything else can be searched on the web. They open in your browser. **On-device AI** (Apple Intelligence, macOS 26+): summarize, rewrite clearer, more formal, friendlier or shorter, or fix spelling and grammar in the copied text, using only the model on your Mac. **Offline translation** (macOS 15+, no Apple Intelligence needed): “translate english” (or Portuguese, Spanish, German, French, Italian, Japanese, Chinese) uses Apple's translator on your Mac. Start with “ai” (or “ia”, “ki”, “?”) to **ask anything**; the answer streams into a small window you can copy from. For developers: decode a JWT,**Emoji and symbols**: “emoji rocket”, “emoji coração” or “:fire” for emoji, and words like “arrow”, “degree”, “euro” or “check” for →, °, €, ✓ and more; ↩ pastes it. **Timers and alarms**: “timer 10m tea”, “timer 1h30” or “alarm 7:30 meeting”, with a countdown in the menu bar and a sound and notice on time. **Quick reminders**: “remind pay the bill tomorrow at 9” (or “lembrar …”, “erinnern …”, “recordar …”) creates it in the Reminders app, with the date understood from what you typed.  generate a UUID, copy the Unix timestamp or paste one to see the date. **Script commands**: drop your own scripts (shell, Python, Node, Ruby, AppleScript) in the scripts folder (“Open scripts folder” in the palette) and each one becomes a command; Raycast script headers (title, icon, mode, argument) work as they are. **Natural-language commands**: start with “do” (or “faz”, “mach”, “haz”) and describe what you want, like “do dark mode, mute the mic and open Zoom”; the Mac’s on-device AI picks the matching Menew actions, window layouts and apps, shows the steps and runs them only when you confirm. Nothing that deletes or quits is ever chosen. |
| 📊 **System monitor** | CPU and GPU with live graphs, memory pressure and swap, disk space and read/write speed, battery health, cycles and charger, a **battery health history** (how much health it lost and how many cycles you use a month, from one reading a day kept on your Mac), the battery of connected accessories (Magic Mouse, Keyboard, Trackpad and AirPods, left, right and case), a **history of the last 24 hours, 7 days and 30 days** of CPU, memory and battery with the apps that used the most of each, **temperatures in °C** (chip, SSD, battery and every sensor) and **fan speed**, **performance and efficiency cores** one by one, **power draw in watts** and real time remaining, **SSD health** (SMART), a **runaway app alert** and **Copy report** for support, **Wi-Fi details** (signal, noise, link speed, channel, band and Wi-Fi standard), **login and background items** (the launch agents and services apps installed, from the command palette), **Screen time** (off until you turn it on: time per app today, over 7 or 30 days, split into focus, neutral and distraction and by kind of app (Development, Office, Design, AI, Organizing, Communication, Browsing, Learning and reading, Utilities, Entertainment, Social media), with an hour-by-hour timeline; right-click an app to change its kind or how it counts, and choose how each kind counts; it counts only the front app while you are active and stays on your Mac), **“Why is my Mac slow?”** (checks memory, CPU, heat, disk, Low Power Mode and uptime, points at the apps to blame and, with Apple Intelligence, explains it in plain words; macOS system processes are never suggested for quitting), uptime, thermal state and the top processes (quit them in one click). Pick what shows in the menu bar (CPU, CPU graph, memory, network, disk, battery, temperature) with a live preview, all in one icon or with **separate icons**, each opening its own panel with details and a chart of the last 24 hours with the apps that used the most. **World clocks** for the cities you work with sit at the top (Settings → World clocks), and the command palette converts times: “3pm ny to lisbon”, “15h em Lisboa”, “time in Tokyo”. |
| 📅 **Next meeting** | Your next meeting from the Calendar app at the top of the menu, with a countdown and a **Join** button that finds the Zoom, Meet, Teams or Webex link. Optional reminder 1 minute before; click it to join. **Today · N** opens the day's agenda, and **Copy my free times** puts your free slots for the next 5 working days (within your working hours) on the clipboard, ready to send. Also from the command palette. Off by default. |
| ✨ **On-device AI** | Settings › AI lists every AI feature with how to use it and a switch to turn it off (it then disappears from the palette, shortcuts and buttons), and shows whether Apple Intelligence is on for this Mac. Natural-language commands, Ask AI, summarize and rewrite copied text, ask about the screen, rewrite anywhere (⌃⌥⌘R), the slow-Mac explanation and note summaries use Apple’s on-device model; smart clipboard search, translation and transcription work without Apple Intelligence. Nothing is sent to the internet. |
| 🟣 **Live notch** | What matters right now appears on both sides of the camera, one thing at a time: a meeting about to start with a Join button, screen recording with the time and a Stop button, a timer or focus countdown, a muted mic during a call, and Menew’s confirmations like “Copied”. It disappears when there is nothing to show. Rest the pointer on the notch and it opens a panel with your next meeting (and Join), the focus or timer countdown and shortcuts (mute the mic, capture, clipboard, shelf, palette); drag files to the notch and drop them to keep them on the shelf. Settings › Notch has a live preview, a switch and a Test button for each alert, and how early meetings appear (1, 2 or 5 minutes). On Macs without a notch it can show as a pill at the top of the screen. |
| 🪟 **Menew window** | The menu bar shows what matters now; the **Menew window** has the depth, with a sidebar like System Settings: Overview (today’s agenda, Mac health, screen time and what you saved), Memory, Clipboard, Notes, Performance, History and screen time, Battery, Tools, and Apps, profiles and automations. Open it from the window button in the menu or “Menew window” in the palette. |
| 🧠 **Memory** | Never lose what crossed your screen. Press ⌃⌥⌘K and pick an area or window: Menew keeps the image, reads the text and notes where it came from (app, window and the browser tab’s link). With Apple Intelligence it adds a title, a one-line summary, tags and the named things in it (tools, people, projects). Search it all in the Memory section or the palette, or save a copied text or image from the clipboard with one click. **Ask your memory** in plain words (“which was that charts library in Swift?”, or “remember …” in the palette): the Mac’s AI turns the question into search terms with synonyms and translations, looks through memory, notes and clipboard, and answers with numbered sources you can open. Memory items also show up in Spotlight. The **knowledge graph** view links the topics the AI found (tools, people, projects, tags) to your saved items and #tagged notes; click a topic to filter, click a dot to open the item. Only saves when you ask; everything stays in a folder on your Mac. |
| 🎙️ **Recordings** | Press ⌃⌥⌘G to start and stop recording a meeting, an idea or yourself thinking out loud. The microphone and the Mac’s audio (the other side of a call) are saved separately, so the transcript knows what was **Me** and what was **Others**. Your Mac transcribes it offline and Apple Intelligence writes the minutes: a title, a summary, decisions, tasks with owner and due date, people and tags. Recordings are listed by date with search and tag filters; send your tasks to Reminders (or have Menew do it for you), save the minutes as a note or copy them. The notch shows the recording time with a Stop button. In Settings › AI › About you, tell the AI your name, what people call you, who you work with and a glossary, so the minutes know which tasks are yours. Everything stays on your Mac. |
| ✂️ **Selected text, anywhere** | Select text in any app and press ⌃⌥⌘R: rewrite it (fix, clearer, more formal, friendlier, shorter, in English) and replace it in place, or **explain** it, **document the code**, **write tests** for it, turn it into a **reminder** or a **calendar event** (the AI finds the title, date, time and place), a **note**, or save it to **memory**. Note and memory work without Apple Intelligence. |
| 🗂️ **Organize files** | Pick a folder (Downloads by default): Menew reads each file (PDF and document text, images by OCR) and the Mac’s AI suggests a clear name and a folder, like “Invoice - Acme - 2026-10” in Invoices. Screenshots, installers and archives are sorted by rule. Review and edit every name and folder before applying; files are only moved and renamed inside that folder, nothing is deleted, and Undo puts everything back. Without Apple Intelligence, files are sorted by type. |
| 🧩 **Widgets** | Four widgets for the desktop and Notification Center, small or medium: System (CPU, memory, disk, battery, and a CPU chart of the last minute), Meetings (the next one with a live countdown and the rest of the day), Timers (focus and timers counting down live) and Screen time (today, split into focus and distraction, with your top apps). Right-click the desktop › Edit Widgets › Menew. Click a widget to open Menew. |
| 🔍 **Live Text & background removal** | In clipboard images and pinned screenshots, select text or click links, phone numbers and addresses right on the image, like in Photos. Remove the background from a photo: from the shelf’s Images menu (any number of photos), from the command palette for the copied image (“remove background”), or with the Remove Background action in Shortcuts. The subject comes out as a PNG with a transparent background. Everything runs on your Mac (VisionKit and Vision). |
| 📱 **Continuity Camera** | Take a photo, scan a document or draw a sketch on your iPhone or iPad and it lands in Menew: on the clipboard (Actions › From iPhone), on the shelf (saved in Downloads), or as text only (scanned pages are read on your Mac). Also in the command palette (“iphone”, “scan text”). Uses macOS’s own Import from iPhone, so the photo goes straight from your phone to your Mac. |
| 🌙 **Focus filters** | In System Settings › Focus › (a Focus) › Focus Filters › Menew, choose what changes while that Focus is on: pause the clipboard history, show only meetings in the notch, mute the mic, turn on presentation mode or activate a work profile. When the Focus ends, Menew undoes only what it changed. Shortcut in Settings › General › Focus. |
| 💬 **Live captions** | Your Mac’s audio (a call, a video) or the microphone becomes captions in a small floating window, and on macOS 26 they are translated as you go (Portuguese, English, Spanish, German, Chinese, French, Italian, Japanese). Recognition and translation run on your Mac; nothing is recorded or sent. Actions › Live captions, or “captions” in the command palette. |
| 🔋 **Battery care** | Without an admin password or a helper: alerts when the battery reaches 80, 85, 90 or 95% on the charger (unplugging then helps it last longer) and when it gets to 40 °C or more, plus a health history in the Battery card with the trend and cycles per month. Turn the alerts on in Settings › Alerts. |
| 🔔 **Alerts** | Optional macOS notifications for a nearly full disk, low battery, critical memory pressure, CPU stuck above 90% or a Mac running hot. **Custom rules**: build your own, like “CPU above 80% for 10 min”, “battery below 30%”, “chip above 90 °C” or “free space below 20 GB”. |
| 📋 **Clipboard history** | Text, links, images and files with instant search, filters, pins and a rich preview. Press **⌘⇧V** anywhere. Skips passwords and any app you pick to ignore, and you can pause it for 15 minutes or an hour. Copy the text inside any copied image with one click. **Paste queue**: turn it on, copy several things, then each <kbd>⌘</kbd><kbd>V</kbd> pastes the next one in the order you copied them; the count shows in the menu bar. **Smart actions**: copy a phone number, address, email, tracking code (Correios, UPS and other international codes), color or meeting link and the command palette (and the item's right-click menu) offers the right action: call or WhatsApp, open in Maps, write an email, track the package, copy the color as HEX/RGB/HSL or join the call. Search also finds **text inside copied screenshots and images**, read in the background on your Mac. **Smart search**: type what you remember, like “the hotel link from yesterday”, “that Xcode error” or “images from today”; Menew understands dates (today, yesterday, this week) and types (link, image, file) and matches word roots and synonyms with macOS’s own language model, no Apple Intelligence needed. |
| 🔆 **Display brightness** | A slider for every screen: the Mac's own display and external monitors over DDC/CI (Apple Silicon). Monitors that don't accept DDC (often because of a USB-C adapter or hub) are dimmed by software instead, remembered per monitor. |
| ⚡ **Quick actions** | Switches that show their live state: mute the microphone (**⌃⌥⌘M** from anywhere) or the sound, hide the Dock, dark mode, keep awake (for a while, until a set time or while an app is open), hidden files and desktop icons. One-click actions: color picker, plain-text clipboard, lock screen, eject disks, empty trash. **Copy text from screen** (**⌃⌥⌘T**): select an area and its text goes to the clipboard, recognized on your Mac with no internet. **Rewrite anywhere** (**⌃⌥⌘R**): select text in any app (Mail, Slack, Notion…) and pick Fix, Clearer, More formal, Friendlier, Shorter or In English; the new text replaces the selection and your clipboard goes back to what it was, all with your Mac’s on-device AI. **Sound**: switch the output (AirPods, headphones, speakers, displays) and the microphone from Actions or the command palette. **Presentation mode**: hides desktop icons, keeps the Mac awake, pauses the clipboard and shows only the icon in the menu bar; turning it off undoes only what it changed. |
| 📸 **Screenshots** | Press **⌃⌥⌘S** to capture an area (Space for a window) or the whole screen from the command palette. Annotate with a pen, arrows, rectangles and text, blur sensitive data, then copy, save, drag into another app or **pin it floating on screen**. “Copy text” reads the text in it. **Ask about the screen**: select an area (an error, a chart, text in another language) and ask your Mac’s on-device AI to explain, summarize, translate or tell you what to do; without Apple Intelligence it still shows the recognized text to copy. **QR codes**: read one from the screen (the content is copied, links never open by themselves), or show a QR of the copied text, a link or your Wi-Fi so your phone can open or join it. **Screen recording**: record an area or the whole screen as video (.mov) or as a looping **GIF**; a floating Stop button stays out of the recording and the file lands on your Desktop. **Scrolling capture**: pick an area that scrolls and Menew scrolls it for you, joining everything into one long image you can annotate. |
| 🍅 **Focus timer** | Start 25 minutes from Actions (or any length: type “focus 50” in the command palette) and the time left shows in the menu bar. Optionally mute the mic, keep the Mac awake and pause the clipboard while you focus; when it ends, everything goes back the way it was, with a sound, a notification and a 5-minute break. Add 5 minutes or stop at any time. |
| 🪟 **Window manager** | Snap the front window to halves, corners, thirds or full screen with <kbd>⌃</kbd><kbd>⌥</kbd> shortcuts (the same as Rectangle) or from a grid in Actions. Send it to the other display, or put it back the way it was. **Drag to snap**: drag a window to the left or right edge for a half, the top for full screen or a corner for a quarter; a preview shows where it lands (turns itself off when Rectangle or Magnet is running). |
| 🚪 **App control** | Quit all apps, quit everything but the one you're using, hide the rest, or force quit a frozen app, from Actions or the command palette. Quitting is a normal request, so apps with unsaved work ask first, and a “Never quit” list keeps apps like Music or Zoom open. **Ports in use** lists the servers running on your Mac (node, Docker, databases) so you can stop one; type “port” or “3000” in the palette too. |
| 🗂️ **Work profiles** | Save the apps you have open and where each window sits, then bring it all back with one click (or from the command palette). A profile can also keep the Mac awake, mute the mic, switch to dark mode and hide everything else. It can also quit every other app first, for a clean work mode. |
| 📥 **Quick shelf** | Shake files while you drag them and a shelf pops up next to the cursor. Drop files, links, text or images there, then drag them all out together to another app or folder. Items are always copied, so the originals never move. Also from the right-click menu or the command palette. With photos on the shelf, its image menu converts them to JPG, PNG or HEIC, shrinks them in bulk (3000 to 800 px), rotates them, removes the background or location and metadata, or copies the text in all of them; results are new files next to the originals, ready to drag out. With PDFs, its PDF menu combines them, compresses them (the same “Reduce File Size” filter as Preview, keeping text selectable), rotates them, turns pages into PNG images, splits them into one PDF per page, extracts the text to a .txt (scanned pages are read on your Mac) or saves a password-protected copy; images can also be combined into one PDF. With audio or video files, **Transcribe** turns speech into text on your Mac (offline), saved as a note and copied. |
| ⚙️ **Automations** | “When X happens, do Y”: at a time on chosen days, when the charger is plugged in or out, when the battery drops below a level, when an app opens or quits, when a display connects, before a meeting starts, when a focus session starts or ends, when presentation mode turns on or off, or when the Mac wakes. Actions: turn on a profile, keep awake, mute the mic, light/dark mode, brightness, pause the clipboard, open an app, quit all apps (say, when the battery drops to 5%) or run one of your Shortcuts. No scripts, a notice when a rule runs and a “Test now” button. |
| 🗣️ **Siri, Shortcuts & Spotlight** | Menew's actions show up on their own, no setup: capture the screen, copy text from screen, mute the mic, keep awake, presentation mode, dark mode, start a focus timer, activate a work profile, create a note, open the clipboard history or the command palette. Actions that return a result, to chain in your own Shortcuts: get a system metric (CPU, memory, free disk, battery, uptime), get the clipboard history, find notes and add to a note, rewrite or summarize text with on-device AI, translate text, transform text (case, JSON, Base64, URL), get text from an image, make a QR code, convert and shrink images (removing location), get the next meeting or join it, start a timer and get today's screen time. Say “Mute my microphone with Menew” or ask “How is my Mac in Menew” and Siri answers with CPU, memory, disk and battery. Your notes show up in Spotlight (⌘Space) and open in Menew (protected and password notes never do; turn it off in Settings › Privacy). Find the actions in Spotlight, or combine them in your own Shortcuts. In all five languages. |
| 🧽 **Cleaning mode** | Lock the keyboard for 2 minutes while you wipe it, or black out every screen to spot smudges. |
| 🌐 **Internet** | Live download/upload, local and public IP, and a real speed test powered by macOS `networkQuality`. **Apps using the network**: download and upload per app, read from macOS `nettop` only while you have the list open. |
| 🎧 **Devices** | Battery levels for AirPods (left, right, case), Magic Mouse, Keyboard and Trackpad. |
| 🧹 **Free up space** | Quick scan for caches, logs and developer junk; deep scan for old downloads, large files (over 250 MB) and duplicate files (identical copies, byte for byte; the oldest is kept as the original). You review everything, and your files go to the Trash. **Uninstall apps**: drop an app (or pick one) and Menew finds the preferences, caches, containers, saved state and logs it left in your Library; review the list and everything goes to the Trash. macOS apps are never touched. |
| ✂️ **Snippets** | Saved texts with `{date}`, `{time}` and `{clipboard}` placeholders, right inside ⌘⇧V. Give one an abbreviation like `;sig` and typing it in any app turns it into the text (optional, off by default; never in password fields). Variables: `{date}`, `{time}`, `{weekday}`, `{tomorrow}`, `{clipboard}`, `{cursor}` (where the cursor lands) and `{input:Name}` (asked in a small window before pasting). |
| 📝 **Notes** | Many notes with #tags, search and Markdown (checklists included). Protected notes live in the Keychain and open with Touch ID. With Apple Intelligence, a note's ⋯ menu can **summarize it** or **extract its to-dos** as a checklist, on your Mac. **Password notes** keep name and value rows with hidden values, an eye to reveal and a copy button; copied values are marked confidential (no clipboard history) and cleared after 30 seconds. Switch a note's type at any time. |
| 🧩 **Only what you need** | A short welcome tour on first launch helps you set things up. The menu opens on **Now**: a search box for the command palette, CPU, memory, disk and battery in one row with an “All good” or what needs attention, running timers, world clocks and your favorites; **Mac details** has every system card (reorder, fold or hide them). **Actions** has your **Favorites** on top and everything else in six groups (Screen and capture, Windows and displays, Sound and focus, Files and iPhone, AI on your Mac, System and cleanup), each opening its own page, and **Settings opens in its own window** with categories and search. Turn off Clipboard, Actions or Notes in Settings → General and they disappear completely (with Clipboard off, Menew doesn't even read it). Settings → Backup saves your settings, shortcuts, snippets, profiles and automations to a `.menew` file (notes and clipboard history optional) to restore later or on another Mac. |
| 🪟 **Liquid Glass** | Native macOS 26 design: glass tabs, search, filters and buttons, with a translucent fallback on macOS 14 and 15. |
| 🌍 **5 languages** | English, Português, Deutsch, Español and 中文. Follows your Mac, or pick one in Settings. |

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/assets/popover-now-dark.png">
    <img src="docs/assets/popover-now-light.png" width="250" alt="Now: what matters at a glance">
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
| **Reminders** | Create the reminders you type in the command palette. Only asked the first time you use it. |
| **Calendars** | Show your next meeting with a Join button. Only asked if you turn it on in Settings → Calendar; read on your Mac, never uploaded. |
| **Automation** (Finder, System Events) | Empty the trash and toggle dark mode. Asked the first time you use them. |

## One app instead of many

Menew covers the everyday features of these popular Mac utilities in one free, native app. Keep using them if you need their advanced features.

| Instead of | Menew gives you |
|---|---|
| Raycast · Alfred | Command palette: apps, actions, math, conversions, quick links and AI (⌃⌥Space). |
| Maccy · Paste | Clipboard history with search, preview, snippets and a paste queue (⌘⇧V). |
| Rectangle · Magnet | Snap windows to halves, corners and thirds with the same ⌃⌥ shortcuts. |
| iStat Menus · Stats | CPU, GPU, memory, disk, network and battery in the menu bar. |
| CleanShot X | Screenshots with arrows, text, blur and pinning on screen (⌃⌥⌘S). |
| Amphetamine · Caffeine | Keep the Mac awake for a while, until a time or while an app is open. |
| CleanMyMac | Disk cleaner for caches, logs, big files and duplicates, plus an app uninstaller with leftovers; files go to the Trash. |
| Dropover · Yoink | A shelf for dragging files between apps, plus image and PDF tools. |

<sub>Names are trademarks of their owners and appear only for comparison. Menew isn't affiliated with or endorsed by any of them.</sub>

## Keyboard shortcuts

| Shortcut | Action |
|---|---|
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>Space</kbd> | Open the command palette (customizable) |
| <kbd>⌘</kbd> <kbd>⇧</kbd> <kbd>V</kbd> | Open clipboard history (customizable) |
| <kbd>⌥</kbd> <kbd>⌘</kbd> <kbd>M</kbd> | Open the Menew menu (customizable) |
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>⌘</kbd> <kbd>M</kbd> | Mute / unmute the microphone (customizable) |
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>⌘</kbd> <kbd>T</kbd> | Copy text from screen (customizable) |
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>⌘</kbd> <kbd>S</kbd> | Capture the screen and annotate (customizable) |
| <kbd>⌃</kbd> <kbd>⌥</kbd> <kbd>⌘</kbd> <kbd>R</kbd> | Rewrite the selected text with on-device AI, in any app (customizable) |
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

The app has **no telemetry, no analytics and no account**. Clipboard history and notes are stored locally in `~/Library/Application Support/Menew`. Items marked as passwords by password managers (`org.nspasteboard.ConcealedType`) are never saved. Values copied from password notes are marked the same way and cleared from the clipboard after 30 seconds. Backups are files you save yourself; protected notes are never included in them. The only network calls are the ones you can see: your public IP (`api.ipify.org`), the speed test you start yourself, a currency rate when you press ↩ on a conversion in the command palette (`api.frankfurter.app`, European Central Bank data), and a daily update check against this repo's releases (you can turn it off). Text recognition (copy text from screen or images) uses Apple's Vision framework on your Mac; nothing is uploaded, and the screen capture is deleted right after. AI text actions use only Apple's on-device model (never Private Cloud Compute), so the text stays on your Mac. The next meeting is read from the Calendar app through EventKit, only if you turn it on, and stays on your Mac. Notes you can search in Spotlight are indexed by macOS on your Mac (never protected or password notes, never the clipboard history). Live captions listen only while they are on and never record; speech is recognized and translated on your Mac. Recordings only happen when you start them; the audio, transcript and minutes are kept in `~/Library/Application Support/Menew/recordings`. Memory captures are only taken when you press the shortcut and are kept in `~/Library/Application Support/Menew/memory`. Widgets read a small file Menew rewrites every minute in its own shared container (`~/Library/Group Containers/9527N6XKKW.com.matheusquost.menew`); they run sandboxed and have no network access.

The website ([menew.web.app](https://menew.web.app/?ref=github)) counts visits and button clicks with [GoatCounter](https://www.goatcounter.com), which uses no cookies and stores no personal data. The app itself never does this.

## FAQ

**Is Menew really free?**  
Yes. Menew is free and open source under the GPL-3.0 license: no ads, no subscription, no paid tier. Anyone can read, change and share the code, and any version they distribute must stay open source too. If it helps you, you can buy the author a coffee, but nothing in the app asks for it.

**Does Menew collect my data?**  
No. There is no telemetry, no analytics and no account. Clipboard history and notes stay on your Mac. The only network calls are the update check, your public IP, a speed test you start and a currency rate you ask for. AI features use Apple's on-device model only.

**Which Macs does it run on?**  
macOS 14 Sonoma or later, on Apple Silicon and Intel. The AI features need macOS 26 or later with Apple Intelligence turned on.

**How do I install it?**  
Download the DMG and drag Menew to Applications, or use Homebrew: brew install --cask menew after adding the quost/menew tap. Updates arrive automatically.

**Is it safe to install?**  
Menew is signed with an Apple Developer ID and notarized by Apple, and all of its source code is public on GitHub.

**Can I turn off the parts I don't use?**  
Yes. In Settings → Modules you can turn off Clipboard, Actions or Notes, and they disappear completely. With Clipboard off, Menew doesn't even read it.

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
- [x] Quick links and web search in the command palette
- [x] Today's agenda and “copy my free times”
- [x] Ask AI in the command palette, AI summaries and to-dos in notes
- [x] Smart clipboard actions (phone, address, email, tracking, color, meeting link)
- [x] World clocks and time zone conversion
- [x] Siri, Shortcuts and Spotlight actions
- [x] On-device AI text actions (summarize, rewrite, fix, translate)
- [x] QR codes: read from the screen, generate for text, links and Wi-Fi
- [x] Accessory batteries (Magic Mouse, Keyboard, Trackpad, AirPods) with low-battery alerts
- [x] Quick reminders from the command palette
- [x] Emoji and symbols in the command palette
- [x] Offline translation with Apple's translator
- [x] Transcribe audio and video on the shelf
- [x] Snippets with variables, fields and cursor position
- [x] Search text inside clipboard images
- [x] 24-hour system history and battery usage by app
- [x] Timers and alarms from the command palette
- [x] New layout: favorites, foldable sections, Settings window with search
- [x] Advanced monitor: P/E cores, watts, SSD health, runaway app alert, system report
- [x] Temperatures in °C and fan speed
- [x] Separate menu bar icons with their own panels
- [x] Drag windows to screen edges and corners to snap them
- [x] 7- and 30-day history and custom alert rules
- [x] Screen recording, GIFs and scrolling capture
- [x] App uninstaller that also removes leftovers
- [x] Script commands in the palette (Raycast-compatible)
- [x] Wi-Fi details and login/background items
- [x] Natural-language commands with on-device AI
- [x] “Why is my Mac slow?” diagnosis and sharing clipboard items
- [x] Smart clipboard search by meaning, date and type
- [x] Ask about the screen with on-device AI
- [x] Rewrite selected text in any app with on-device AI
- [x] Screen time with focus and distraction
- [x] Live alerts in the notch
- [x] Settings › Notch (preview, per-alert switches) and Settings split into Keyboard shortcuts and Windows and displays
- [x] Widgets: system, meetings, timers and screen time
- [x] Shortcuts actions that return results (system, clipboard, notes, AI, translate, images, meetings, timers, screen time)
- [x] Notes in Spotlight, “How is my Mac” for Siri and an Open Note action
- [x] Live Text in images and background removal
- [x] Continuity Camera: photos, scans and sketches from iPhone to the clipboard, shelf or text
- [x] Notch panel on hover and drop files on the notch
- [x] Focus filters (pause clipboard, quiet notch, mute mic, presentation mode, work profile)
- [x] More PDF and image tools: split, extract text with OCR, password-protect, rotate images, copy text from images
- [x] Live captions of system audio or the microphone, translated on the Mac
- [x] Battery care: charge-level and heat alerts, health history
- [x] Menew window with a sidebar, and Memory (capture with source, OCR and AI tags)
- [x] Ask your memory in plain words, with sources, and memory in Spotlight
- [x] Knowledge graph of memory and notes
- [x] Recordings with transcript, AI minutes, tasks to Reminders and About you
- [x] Actions on selected text: explain, document, tests, reminder, event, note, memory
- [x] Organize files by content, with review and undo
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

[GPL-3.0](LICENSE) © Matheus Quost. Versions up to 1.81 were released under the MIT license.

The name “Menew”, the icon and the website are not part of the license: a fork needs its own name and icon. See [TRADEMARK.md](TRADEMARK.md).
