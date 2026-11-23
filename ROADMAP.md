# Menew roadmap

A long-term plan, written in November 2026 from a benchmark of the ~450 apps on [macmenubar.app](https://macmenubar.app/) and compared with what Menew already does. It is a direction, not a promise: the order may change with issues and what users ask for.

Estimated effort: **S** small, **M** medium, **L** large. In italics, the apps from that site that inspired the item. Items marked ✅ have shipped; the version is in parentheses.

Criteria to get in: native, runs on the Mac, no account, no telemetry and no new network calls (see [CLAUDE.md](CLAUDE.md)). Anything that needs the network is under [Needs a decision](#needs-a-decision).

## First cycle (priority)

A lot of value for little effort, reusing what already exists:

1. **1.99, AI agents** ✅ (1.99): agents section, notch alerts, "waiting for you", cost, limits, forecast and MCP server.
2. **2.0, Agents, part two**: approve or deny permissions from the notch (2.29) and keep the Mac awake while an agent works. The notch, hooks and keep awake already exist.
3. **2.16, Safer clipboard**: strip UTM from links, detect keys and tokens and delete them automatically. Small, useful to everyone, and good for privacy.
4. **2.9, Reminders in the menu bar**: the "Today" list from the Reminders app, mark as done, pin a task to the bar.
5. **2.6, Smart breaks**: 20-20-20, stretch and stand up, postponed automatically during meetings, recording or focus, which competitors don't do.
6. **2.14, Dictation in any app**: hold a key and speak, processed on the Mac, with AI cleanup. Prepares "talk to the agent" (2.32).

Left out of the first cycle on purpose: **hiding icons (2.3)** was the most common request but risky on macOS 26, so it was prototyped separately (it shipped in 1.106.0). **Volume per app (2.20)** and **monitor presets (2.76)** are too big.

How to measure without telemetry: downloads per release on GitHub, stars, issues and GoatCounter clicks on each feature's page.

## Phase 1 · Agents and menu bar (1.99 → 2.5)

- **1.99** AI agents: sessions, limits, MCP ✅ (1.99) · *CodexBar, AIQuota, Burnrate*
- **2.0** Agents in the notch: alerts and "waiting for you" ✅ (1.99); still missing: keep awake while the agent works (S) · *Vibe Island, Look Alive, Belay*
- **2.1** Cost and forecast: cost per model and project, a forecast of when the limit runs out ✅ (1.99) · *Tokenscope, ReserveGauge*
- **2.2** Set up agents: turn skills and MCP servers on and off, switch account or provider (M) · *Wasdy, Prism Switch, Quotio*
- **2.3** Hide menu bar icons: hidden section, always hidden, works with the notch ✅ (1.106.0) · *Ice, Bartender, Hidden Bar*
- **2.4** Menu bar plugins in the SwiftBar/xbar format (M) · *SwiftBar*
- **2.5** An icon with personality: animated CPU, optional seasonal themes (S) · *RunCat, Festivitas*

## Phase 2 · Health and the day (2.6 → 2.13)

- **2.6** Smart breaks, postponed during meetings, recording or full screen (M) · *LookAway, Pausebar, Recess*
- **2.7** Posture from the AirPods sensor, no camera (M) · *Poise*
- **2.8** Water and habits: 1-click check-in, a streak that forgives (S) · *Aqumi, Keystone, Tasktile*
- **2.9** Reminders in the menu bar: "Today", mark as done, one pinned task (S) · *Barrie, One Thing, Satu*
- **2.10** Plan the day: reminders fitted into the free slots between meetings (M) · *Tideline, Nowline*
- **2.11** Month calendar, birthdays from Contacts, countdowns (S) · *Itsycal, Honeyday, Await*
- **2.12** Full-screen meeting alert, each colleague's local time and shared hours (M) · *Dato, Chime, There*
- **2.13** Time per project: 1-click timer, forgotten time, a "receipt" for the day (M) · *Dial, Punchcard*

## Phase 3 · Text, capture, sound and Mac (2.14 → 2.28)

- **2.14** Hold-a-key dictation, in any app, on the Mac (M) · *parrot, Handy, HoldSpeak*
- **2.15** Action bubble when you select text, with the ⌃⌥⌘R actions (M) · *PopClip, SwiftBiu*
- **2.16** Safer clipboard: no UTM, secrets that expire, Touch ID (S) · *UTMBeGone, Klipvault*
- **2.17** Keys and clicks on screen, spotlight, zoom, draw on screen (M) · *KeyCastr, ClickLight, Presentify*
- **2.18** Pretty screenshots: background, shadow, fixed aspect ratio, pixel ruler (M) · *Tuji, Framéd, PixelSnap*
- **2.19** Screen edges as a ring light, camera mirror, privacy screen (S) · *DisplayFill, Hand Mirror, Shoji*
- **2.20** Volume per app, device priority, mute when the headphones come off (L) · *FineTune, AudioPriorityBar, Default0*
- **2.21** Now playing: Music and Spotify in the menu and the notch ✅ (1.106.0; the volume and brightness HUD is still open) (M) · *Boring Notch, Tuneful*
- **2.22** Focus sounds generated on the Mac, tied to the timer (S) · *Patter, CapyMuMu*
- **2.23** AirPods by shortcut, Bluetooth that doesn't reconnect while the Mac sleeps, what the USB-C cable supports (M) · *Sharptooth, Bluesnooze, WhatCable*
- **2.24** Guard mode: alarm when the charger is unplugged or the lid is closed, lock when the iPhone moves away (M) · *Stealward, Peeku*
- **2.25** macOS tweaks with undo: Dock, screenshots, hidden files (S) · *Mainspring, One Switch*
- **2.26** History of internet and Wi-Fi drops, with no extra traffic (S) · *NetCheck, Online Indicator*
- **2.27** Shortcut per app (⌥1 opens Slack), window switcher with thumbnails (L) · *Spring, DockDoor, cmdcmd*
- **2.28** Browser per domain, meeting links straight into the app, bookmarks from every browser in the palette (M) · *Portals, Bookmark Bar*

## Phase 4 · Agents, second wave (2.29 → 2.36)

- **2.29** Approve or deny agent permissions from the notch (M) · *Vibe Island*
- **2.30** Session timeline: what the agent did, files and commands (M)
- **2.31** Carry on by itself when the limit resets, with a prompt queue (M) · *CodexReset*
- **2.32** Talk to the agent: dictation straight into the active session (S) · *Agent Bar*
- **2.33** More MCP tools, with permission for each action: windows, apps, capture, reminders, calendar (M) · *Macuse, Orchard*
- **2.34** A `menew` command for scripts: notices, progress in the notch, clipboard, notes (M) · *Notchification*
- **2.35** Build progress in the notch (xcodebuild, npm, tests) (S)
- **2.36** Agents as floating characters, an optional fun mode (S) · *Agenteam*

## Phase 5 · Menu bar and notch your way (2.37 → 2.44)

- **2.37** Spacing between menu bar icons (S) · *Menu Bar Spacing*
- **2.38** A clock in the corner when the bar is hidden (S) · *Corner Time*
- **2.39** Search the active app's menus from the palette (M)
- **2.40** Build-your-own notch: choose the blocks of the panel (M) · *OmniNotch, NotchDodo*
- **2.41** Clipboard cards coming out of the notch (M) · *Just Copy, Supaste*
- **2.42** Favorite folders as menus, quick links in the notch (S) · *Folder Peek, LinkNotch*
- **2.43** Any app in the bar, with unread counts from Slack or Mail (M) · *Badgeify*
- **2.44** A folder from the Shortcuts app as a menu in the bar (S) · *Short Run*

## Phase 6 · Health, second wave (2.45 → 2.51)

- **2.45** Typing, click and scroll stats, counts only (S) · *Mac Input Stats*
- **2.46** Gentle per-app limits ("30 min of YouTube a day") (M) · *BalmyTime*
- **2.47** A guided 1-minute breathing exercise in the notch (S) · *Mysa*
- **2.48** A night filter stronger than Night Shift, with a red mode and a schedule (M) · *Nox, Sundown*
- **2.49** Screen and keyboard light below the system minimum (S) · *Doze, Lowlight*
- **2.50** Movement reminders with short exercises (S) · *DeskSquat, Standflow*
- **2.51** Weekly summary: breaks, posture, screen time, late hours (S)

## Phase 7 · Ideas and writing (2.52 → 2.59)

- **2.52** Sticky notes floating or pinned to the screen edge (M) · *Tucky, FloatyDo*
- **2.53** Notes per app or per window (M) · *Flip*
- **2.54** Append a line straight to the end of a chosen .md file (Obsidian) (S) · *Markie*
- **2.55** A journal in conversation form, tied to Memory (M) · *mynd*
- **2.56** Save the browser tab to Memory with a shortcut (S) · *Snaggy, Clipii*
- **2.57** A mini spreadsheet in the menu (M) · *MenuSheet*
- **2.58** Review of the day and the week on one page (M)
- **2.59** Clipboard collections, "always paste without formatting" per app (S) · *PastePal*

## Phase 8 · Video and demos (2.60 → 2.66)

- **2.60** Camera in a bubble on the screen recording (M) · *FaceScreen*
- **2.61** Bug report kit: recording, system data and logs in a .zip (M) · *Jam*
- **2.62** Compress images in bulk, with WebP and AVIF (S) · *Zipic, Tinyowl*
- **2.63** Trim and speed up recordings before exporting (M)
- **2.64** Color palette from an image, eyedropper history (S) · *Sip*
- **2.65** Captions burned into the video from the transcript (M)
- **2.66** Translate the screen: the translation appears on top of the area (M) · *TrueDict, PinsGO*

## Phase 9 · Files and space (2.67 → 2.73)

- **2.67** Find any file from the palette, with a preview (M) · *Everywhere*
- **2.68** Automatic rules for folders like Downloads, with undo (M) · *DropSweep*
- **2.69** Convert a file by changing its extension (S) · *Consul*
- **2.70** X-ray of "System Data": snapshots, iPhone backups, simulators (M) · *System Data*
- **2.71** Send to your other Mac over the local network, no cloud (M) · *Sharee*
- **2.72** Cut and paste files in Finder with ⌘X (M) · *FinderClip*
- **2.73** Similar (not identical) photos in the cleaner, always to the Trash (M)

## Phase 10 · Sound, displays and input (2.74 → 2.81)

- **2.74** System equalizer per device (M) · *FineTune*
- **2.75** Two headphones or several outputs at once (S) · *PairPods, Cacophony*
- **2.76** Monitor presets (resolution, HiDPI, brightness) per profile (L) · *BetterDisplay, Crisp*
- **2.77** Windows go back to their place when the monitor reconnects (M) · *ScreenPlace, Stay*
- **2.78** Smooth scrolling and separate direction for mouse and trackpad (M) · *AirScroll*
- **2.79** Keyboard language per app (S) · *LinguaX*
- **2.80** Privacy panel: which app used the camera, microphone and location, and when (M)
- **2.81** Lid angle, with actions (S) · *LidAngleSensor, Lid Plane*

## Phase 11 · Dev, second wave (2.82 → 2.88)

- **2.82** Dev servers grouped by project (S) · *TidyPorts, Port Menu*
- **2.83** Docker and Apple `container` containers: list, stop, logs (M) · *Berthly*
- **2.84** iOS simulators and Android emulators: open, clean, deep link (M) · *MiniSim, SimTag*
- **2.85** Git identity per folder, personal and work (S) · *Switzy*
- **2.86** A bigger dev kit in the palette: JSON, Base64, hash, regex, cron (S)
- **2.87** "Tell me when it's done" for long terminal commands (S)
- **2.88** Code snippets with syntax highlighting (S) · *BearGist*

## Phase 12 · Platform and polish (2.89 → 3.0)

- **2.89** Sync notes, snippets and settings between your Macs through iCloud, optional and with no new account (L)
- **2.90** Clipboard across your Macs, optional (M) · *CliperX*
- **2.91** A Menew plugin API, with their own panels (L)
- **2.92** More languages in the app and the site: French, Japanese, Korean, Italian (M)
- **2.93** Chinese lunar calendar and holidays by country (S) · *LunarBar*
- **2.94** Accessibility: full VoiceOver, everything by keyboard (M)
- **2.95** Low-power mode: Menew measures its own energy use (M)
- **2.96** An optional mascot that reacts to CPU and focus (S) · *CatPod, RunCat*
- **2.97** Coin flip, draw and dice in the palette (S) · *Flippr*
- **3.0** **Day panel**: agenda, agents, health, tasks and Mac on one screen, with "Now" redesigned around it (L)

## Needs a decision

These create new network calls, which are not allowed today. They only get in as optional and on demand, like the currency rate:

- Weather (WeatherKit)
- GitHub PRs and issues (through the installed `gh`)
- Update notices for other apps · *MacUpdater*
- A fast HTTP client · *Pingo*
- Upload to a bucket of your own · *Tinyowl*

## Out

- Battery charge limit: needs a helper with an admin password, which Menew promises not to use.
- Firewall: that is another product (LuLu already does it).
- Always-on recording "for when you forgot to record": a privacy risk.
- A proxy to share AI subscriptions: against the terms of use.
- Wallpapers downloaded from the internet, keyboard sounds, Hue and TV controls.
