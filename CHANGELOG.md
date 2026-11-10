# Changelog

Each version's section is shown in the in-app update window and on the GitHub release.

## 1.99.0

### New
- **External monitors follow the Mac display.** Turn on "Follow the Mac display" right below the brightness sliders (Actions › Windows and displays, also in Settings › Windows and displays) and, as the Mac's display gets brighter or dimmer with the room's light, external monitors follow, over the cable (DDC/CI) or by software dimming. Move a monitor's slider to keep it brighter or dimmer than the Mac display; it then follows with that difference. The Mac display's darkest settings are close to black, so a monitor never follows it below about a quarter of its brightness unless you move its slider lower. Off by default.
- **Download a recording.** A new Export menu in Recordings saves the audio as one .m4a (your voice and the Mac's audio mixed, light enough to send: about 30 MB per hour) or a .zip with the audio and the minutes in Markdown.
- **Copied captures go to Memory.** When you copy a capture from Menew (⌃⌥⌘S), it's also saved to Memory with the app and link it came from, so you can find it later by asking. Turn it off in Settings › Clipboard.
- **AI agents.** A new section in the Menew window for Claude Code, Codex and Gemini CLI. See which sessions are working, done or waiting for you, and get a notice in the notch (with a button that opens the right terminal) and a notification when a long request finishes or needs your permission. Rest the pointer on the notch to see each agent's current step, how long it has been working, and today's tokens, cost and limits; turn it on per tool under Set up. See your plan limits (5 hours, week and month) with when they reset and, at the pace of the last hour, when you'd run out or how far you'll get before the reset, with alerts at 75% and 90% and an hour before you run out, and your usage: tokens per day, estimated cost at API prices, cache savings, top models and projects. Read from the logs each tool keeps on your Mac. Claude's plan limits are optional and off by default, since they come from Anthropic.
- **MCP server.** Your agents can ask Menew: search Memory and notes, read meeting minutes and tasks, check how the Mac is doing or see agent usage, and save something to Memory, create a note or notify you. One switch adds it to Claude Code, Codex, Gemini CLI, Claude Desktop or Cursor; it runs on your Mac with no network, and each source has its own switch.

### Fixed
- **Widgets missing on macOS 27.** Menew's widgets didn't show up in the widget gallery on macOS 27; they're back.
- Buttons that turn something on (screen time, keep awake, presentation mode) said "Unmute" in English.

## 1.98.0

### New
- **Dismiss the meeting alert in the notch.** Rest the pointer on the notch and use the ✕ next to Join: dismiss this alert, or never show that title again (like "Lunch"). Silenced titles are listed in Settings › Notch, where a click brings them back.
- **Calendar blocks no longer show up.** By default, the notch only alerts you about meetings with a call link or other people invited; events that are only yours (lunch, a workout, focus time) stay quiet. Turn it off in Settings › Notch.

## 1.97.1

### Improved
- **Minutes read like minutes.** Topics, decisions and next steps are written in the third person, in the style of formal minutes, instead of quoting the speech; obvious speech-recognition errors and small talk are left out, and your name is used instead of "Eu".
- **Passwords notes are easier to read.** Each field now has its name on top, in full, and its value below across the whole width; a revealed value wraps instead of being cut off. Copying shows a checkmark, and the remove button only appears when you point at a field.
- **Progress while the minutes are written.** A long meeting takes a few minutes on your Mac; the recording now shows which part the AI is on ("part 3 of 10").

### Fixed
- Tasks no longer get a deadline nobody said, and placeholders like "no decision was made" or "no date" don't show up as decisions or deadlines.
- **External monitor going black when Menew opens.** With some USB-C adapters, talking to the monitor over DDC/CI made it lose the signal; Menew then rescanned and asked again every time it came back, so the screen kept blinking and the CPU stayed high until you quit. Now, if a monitor reconfigures right after Menew talked to it, Menew remembers that monitor (even after you quit), stops sending it commands and uses software dimming instead. Turning “External monitor brightness” off and on again in Settings › Windows and displays makes Menew try the cable again.

## 1.97.0

### New
- **Detailed meeting minutes.** Recordings now get minutes that follow the whole conversation, not just a summary: the main topic, a summary, every topic discussed with what was actually said (facts, numbers, names, concerns), decisions, a task table with owner and due date, next steps and notes. Long meetings are read in full, in parts, instead of being squeezed into a few lines, and tasks are extracted separately and checked against the part of the conversation they came from, so fewer get lost or end up with the wrong owner. Copy the minutes or save them as a note in Markdown; for older recordings, use Redo the minutes.

## 1.96.0

### New
- **The notch knows when you're in a call.** Rest the pointer on the notch while any app is using the microphone and the panel turns into call controls: how long you've been in the call, mute, **Record minutes** (Mac audio and microphone, transcribed into Recordings) and live captions. Outside a call, Memory takes the Palette's place among the shortcuts (Capture, Memory, Clipboard, Shelf), and a line below your next meeting shows the one after it.

### Fixed
- “No more meetings today” in the Menew window's agenda was shown in Portuguese in every language.

## 1.95.0

### New
- **Battery wear.** A new Wear card in the Menew window's Battery section shows where your battery wears out: cycles per day over the last 30 days (100% drained = 1 cycle), this week against the last, the hours of the day that drain it most, the apps that used the most battery, and what wears it without adding cycles: time at 35 °C or more, time plugged in above 95% and drops below 20%, with one tip for whatever weighed most. The Battery card in the menu shows this week's cycles with a link to the details. It starts counting after you update, and it's all kept on your Mac.

### Fixed
- The 7- and 30-day system history kept its hourly points only until Menew quit, so the charts started over after every restart. They're saved now.

## 1.94.1

### New
- **Passwords tab in the menu.** The Clipboard tab now has History, Snippets and **Passwords**, with its own search and a New passwords note button. Picking one works like in ⌘⇧V: Touch ID first, ↩ pastes the password, ⌥↩ the username.

### Fixed
- In the Menew window, choosing a passwords note in Clipboard now asks for Touch ID and copies the password (cleared after 30 seconds), instead of copying the placeholder text.

## 1.94.0

### New
- **Passwords in ⌘⇧V.** A new Passwords filter, after Snippets, lists your passwords notes by title. Pick one and your Mac asks for Touch ID (or your password), then pastes it straight into the app you were using: ↩ pastes the password, ⌥↩ the username. It's marked as confidential, so it never enters the clipboard history, and it's cleared from the clipboard after 30 seconds. Copy, share and transform are left out for these items on purpose.

## 1.93.2

### Fixed
- **Eject disks is always in the command palette.** It used to show up only while a disk was connected, so searching for it found nothing. Now it's always listed, says when no disk is connected, and is found by more words in every language (“eject”, “unmount”, “USB”, “drive”, “auswerfen”, “expulsar”, “推出”…). It also lives in Actions › Files.

## 1.93.1

### Fixed
- **Meetings switch on time.** The meeting at the top of the menu now changes the second one meeting ends or the next begins (and two minutes early for back-to-back meetings), instead of waiting up to a minute. The Mac also rereads the calendar on wake.
- **The notch meeting card leaves once you join.** It hides when you press Join, or when a call app is using the microphone after the meeting starts, instead of showing “Meeting now · Join” while you're already in the call.

## 1.93.0

### New
- **Screen recording with sound.** Right-click Record screen (Actions › Screen and capture) to choose the sound: none (as before), microphone, Mac audio, or both; or use “Record screen with sound” in the palette. The video gets the sound tracks, and with “Transcribe and write minutes” on (the default when there is sound), the audio also shows up in Recordings with a transcript, minutes and tasks, plus an Open the video button. Recording the microphone together with the screen needs macOS 15 or later.

## 1.92.0

### Changed
- **One window.** Settings now live inside the Menew window, as the last item of the sidebar: click it and the sidebar shows the settings categories, with a way back. One search box at the top finds both sections (Memory, Recordings…) and settings (shortcuts, notch, AI…). ⌘, and the gear button open the same window, already on Settings.

## 1.91.0

### New
- **Record faster.** A Record button in the Now tab with three choices: Mac audio and microphone (a call), Mac audio only (a video, a class, a call where you only listen) or microphone only (ideas and voice notes). The palette has a command for each, and ⌃⌥⌘G uses your last choice.
- **Recordings in Notes.** A Recordings folder at the top of Notes lists every recording with search, tag filters and newest or oldest first; open one to read its minutes right there. Saving each set of minutes as a separate note is now optional.

### Changed
- **Discreet while recording.** Instead of the notch, there is only a small stop symbol in the menu bar (click it to stop), so nothing shows when you share your screen. Hover the notch to see the time and a Stop button. You can bring back the notch alert in Settings › Notch.
- **No more invented minutes.** Short recordings get just a title, and tasks are only listed when someone actually asked for or promised something (each one is double-checked by the AI). A new Redo button rebuilds the minutes of an older recording.

## 1.90.0

### New
- **Messages and email.** Select a message in Mail, Outlook, Slack, WhatsApp or anywhere and press ⌃⌥⌘R: **Requests and deadlines** lists what you’re being asked to do, who asked and by when, with a button to turn them all into reminders (with dates when the message gives one); **Draft a reply** writes an answer in the message’s language and tone, keeping the dates it mentions, ready to copy. Menew never reads your mailbox: only the text you select.

## 1.89.0

### New
- **Organize files by content.** Pick a folder (Downloads by default) and Menew reads each file: text from PDFs and documents, and from images with OCR. The Mac’s AI suggests a clear name and a folder, like “Invoice - Acme - 2026-10” in Invoices, or “Meeting minutes - Building - 2026-10” in Minutes and notes. Screenshots, installers and archives are sorted by rule. Review and edit every name and folder first; files are only moved and renamed inside that folder, nothing is deleted, and Undo puts everything back. Without Apple Intelligence, files are sorted by type. Find it in Actions › Files and iPhone, Tools in the Menew window, or “organize” in the palette.

## 1.88.0

### New
- **Do more with selected text.** ⌃⌥⌘R still rewrites the selection anywhere, and now it can also **explain** it, **document code**, **write tests** for it, or turn it into a **reminder** or a **calendar event** (the Mac’s AI finds the title, date, time and place), a **note**, or a **memory** item. Explanations and tests open in the same small window to copy; documented code can replace the selection.
- Without Apple Intelligence, ⌃⌥⌘R still turns selected text into a note or a memory item.

## 1.87.0

### New
- **Recordings.** Press ⌃⌥⌘G (or Record in the new Recordings section of the Menew window) to start and stop. The microphone and the Mac’s audio are saved separately, so in a call the transcript shows what was **Me** and what was **Others**. Your Mac transcribes it offline, and with Apple Intelligence it writes the minutes: title, summary, decisions, tasks with owner and due date, people and tags. Recordings are listed by date, with search and tag filters. Send your tasks to Reminders with one click (or turn on automatic reminders), save the minutes as a note, copy them, or play the audio back. While recording, the notch shows the time and a Stop button.
- **About you.** In Settings › AI, tell the AI your name, what people call you, who you work with and a glossary of your work’s names and acronyms. The minutes use it to know which tasks are yours.

## 1.86.0

### New
- **Screen time by kind of app.** Apps are now grouped into 12 kinds (Development, Office, Design, AI, Organizing, Communication, Browsing, Learning and reading, Utilities, Entertainment, Social media and Other), using what each app declares about itself when Menew doesn’t know it. The card shows time per kind, and each app shows its kind.
- **You decide what counts.** Categories… sets whether each kind counts as focus, neutral or distraction; right-click an app to change its kind or mark that app alone.

## 1.85.0

### New
- **Knowledge graph.** In Memory, switch from Cards to Graph: the topics the AI found in what you saved (tools, people, projects and tags) are linked to the items and to your notes with #tags. Topics that show up in more places are bigger and closer to the middle. Click a topic to filter your memory by it, or a dot to open that item.

### Improved
- “Why is my Mac slow?” explains technical process names, like swift-frontend (the Swift compiler from Xcode), callservicesd (FaceTime and Continuity calls) or mds_stores (Spotlight indexing).

## 1.84.0

### New
- **Ask your memory.** Type a question in Memory and press ↩ (or type “remember …” in the palette): “which was that charts library in Swift?”. The Mac’s AI turns it into search terms, with synonyms and translations, so a question in Portuguese finds something you saved in English. Menew looks through your memory, notes and clipboard and answers in two or three sentences, with numbered sources you can click to open. Nothing leaves your Mac.
- **Memory in Spotlight.** What you save to memory now shows up in Spotlight (⌘Space) and opens in Menew. Turn it off with the Spotlight switch in Settings › Privacy.

## 1.83.0

### New
- **Menew window.** The menu bar keeps what matters now; the new window has the depth, with a sidebar like System Settings: Overview (today’s agenda, Mac health, screen time and what you saved), Memory, Clipboard, Notes, Performance, History and screen time, Battery, Tools, and Apps, profiles and automations. Open it from the new window button at the top of the menu or with “Menew window” in the palette.
- **Memory.** Press ⌃⌥⌘K and pick an area or window: Menew keeps the image, reads its text and notes where it came from (app, window and the link of the browser tab). With Apple Intelligence it adds a title, a summary, tags and the named things in it. Search everything in Memory or the palette, and save any clipboard item to memory with the new brain button. It only saves when you ask, and everything stays on your Mac.

## 1.82.0

### New
- **A calmer menu.** Menew now opens on **Now**: a search box for the command palette, CPU, memory, free disk and battery in one row, an “All good” (or what needs attention, with a Why? button), running timers and focus, world clocks and your favorites. Everything else from the old System tab is one click away in **Mac details**.
- **Actions in six groups.** Favorites stay on top; everything else is grouped into Screen and capture, Windows and displays, Sound and focus, Files and iPhone, AI on your Mac, and System and cleanup, each opening its own page. New buttons for Text from screen, Read QR code, Ask AI, Do it for me and the Shelf.
- The welcome tour mentions that everything starts on, with a Customize link if you want Menew leaner.

## 1.81.2

### Improved
- The CPU, Memory and Battery panels in the menu bar (separate icons) now show a chart of the last 24 hours and the three apps that used the most, so you can see the trend without opening Menew.

## 1.81.1

### Fixed
- Menew could quit right after opening when another copy of it was running from a different folder (an old download, for example). Now only a second copy of the same app closes itself.
- German: the clipboard is now called “Zwischenablage” everywhere, so it no longer shares a name with the shelf (“Ablage”). Tabs that don’t fit drop their icon instead of cutting the word.

## 1.81.0

### New
- **Battery care.** Two new alerts in Settings › Alerts: **Battery charged** tells you when it reaches the level you choose on the charger (80, 85, 90 or 95%), so you can unplug and help it last longer; **Battery hot** tells you when it gets to 40 °C or more, the thing that wears batteries out the most. No admin password, no helper.
- **Battery health history.** The Battery card now shows how much health your battery lost over time and how many cycles you use a month, with a small chart. Menew keeps one reading a day in a small file on your Mac; the history appears after a week.

## 1.80.0

### New
- **Live captions.** Your Mac’s audio (a call, a video) or the microphone becomes captions in a small floating window you can move anywhere. On macOS 26 they are also translated as you go, into Portuguese, English, Spanish, German, Chinese, French, Italian or Japanese. Speech is recognized with Apple’s new on-device transcriber and translated with Apple’s translator: nothing is recorded or sent. Start them from Actions › Live captions or by typing “captions” in the command palette. The first time, macOS may download the language model; capturing the Mac’s audio uses the screen and audio recording permission.

## 1.79.0

### New
- **More PDF tools on the shelf:** split a PDF into one file per page, extract the text to a .txt next to it (scanned pages without text are read on your Mac), and save a password-protected copy (you type the password twice; the original stays as it is).
- **More image tools on the shelf:** rotate 90° and copy the text in all the images to the clipboard.
- **Two new Shortcuts actions:** Get Text from PDF and Protect PDF with Password.

## 1.78.0

### New
- **Focus filters.** Menew now appears in System Settings › Focus › (a Focus) › Focus Filters. Choose what changes while that Focus is on: pause the clipboard history, show only meetings in the notch, mute the microphone, turn on presentation mode or activate a work profile. When the Focus ends, Menew undoes only what it changed (if you had paused the clipboard yourself, it stays paused). Settings › General › Focus has a shortcut to the right place.

## 1.77.0

### New
- **Notch panel.** Rest the pointer on the notch for a moment and it opens: your next meeting with a Join button, the focus or timer countdown, and shortcuts to mute the mic, capture the screen, open the clipboard, the shelf or the command palette. Move away and it closes. It doesn’t open when the pointer just passes by on its way to a menu.
- **Drop files on the notch.** Drag files toward the notch and a drop zone appears; let go and they go to the shelf.
- Both can be turned off in Settings › Notch.

## 1.76.0

### New
- **Continuity Camera.** Take a photo, scan a document or draw a sketch on your iPhone or iPad and it lands in Menew. Actions › From iPhone puts it on the clipboard; right-click it to send it to the shelf (saved in Downloads) or to copy only the text (every scanned page is read on your Mac). Also in the command palette (“iphone”, “scan text”) and as a button on the shelf. It uses macOS’s own Import from iPhone: your iPhone needs the same Apple Account, with Wi-Fi and Bluetooth on.

## 1.75.0

### New
- **Live Text in images.** In clipboard image previews and pinned screenshots, select the text or click links, phone numbers and addresses right on the image, like in Photos. Recognized on your Mac.
- **Remove background.** Keep only the subject of a photo (a person, pet or object) with a transparent background: from the shelf’s Images menu for all photos on it, from the command palette for the copied image (“remove background” copies the cutout), or with the new Remove Background action in Shortcuts. The result is a PNG; originals are never changed.

## 1.74.0

### New
- **Notes in Spotlight.** Search for a note with ⌘Space and it opens in Menew. The index stays on your Mac; protected notes, password notes and the clipboard history are never indexed. Turn it off in Settings › Privacy and the index is erased.
- **Ask Siri how your Mac is doing.** “How is my Mac in Menew” answers with CPU, memory, free disk space and battery. Also available as the Mac Status action in Shortcuts.
- **Open Note action** in Shortcuts, to open a specific note from a shortcut, a widget stack or the Dock.

## 1.73.0

### New
- **14 new Shortcuts actions that return a result**, so you can chain them in the Shortcuts app: Get System Metric (CPU, memory, free disk, battery, uptime), Get Clipboard History, Find Notes, Add to Note, Rewrite Text with AI (summarize, fix, clearer, formal, friendlier, shorter), Translate Text, Transform Text (case, accents, lines, JSON, Base64, URL), Get Text from Image, Make QR Code, Convert Image (JPEG, PNG or HEIC, resize, remove location), Get Next Meeting, Join Next Meeting, Start Timer and Get Screen Time Today. For example: “if CPU is above 80, start a focus timer”, or “get the last copied text → translate it → add it to a note”. Everything runs on your Mac.

## 1.72.0

### New
- **Widgets.** Four widgets for your desktop and Notification Center, in small and medium sizes: **System** (CPU, memory, disk and battery, plus a CPU chart of the last minute), **Meetings** (the next one with a live countdown, then the rest of the day), **Timers** (focus and timers counting down live) and **Screen time** (today, split into focus, neutral and distraction, with your top apps). Right-click the desktop › Edit Widgets and look for Menew. Click a widget to open Menew. Widgets read a small file Menew updates every minute on your Mac; they have no network access.

## 1.71.0

### New
- **Settings › Notch.** A live preview that cycles through the alerts, the main switch, and one switch per alert (upcoming meeting, screen recording, Menew confirmations, focus, timers, muted mic), each with a Test button that shows it on your notch for a few seconds. Choose whether meetings appear 1, 2 or 5 minutes before they start. Turn off Menew confirmations here and they go back to the middle of the screen.

### Changed
- **Settings are easier to find.** “Shortcuts and actions” is now two pages: **Keyboard shortcuts** (only the key combinations) and **Windows and displays** (window snapping with ⌃⌥ or by dragging, shaking files to open the shelf, external display brightness).

## 1.70.0

### New
- **Live notch.** On Macs with a notch, what matters right now appears on both sides of the camera, one thing at a time and in order of importance: a meeting starting within 2 minutes (with a Join button), screen recording (time and Stop), Menew’s confirmations such as “Copied”, a focus or timer countdown, and a muted mic while an app is using it. When there is nothing to show, it disappears and the menu bar is untouched. On Macs without a notch you can turn it on as a pill at the top of the screen. Settings › Shortcuts and actions.

## 1.69.1

### Fixed
- Menew could end up running twice (for example when an update relaunched it while it was opening at login), which showed every menu bar icon twice. A second copy now quits right away.

## 1.69.0

### New
- **Settings › AI.** Every AI feature in one list, with how to use it and a switch to turn it off; turned off, it disappears from the palette, shortcuts and buttons. The top shows whether Apple Intelligence is on for this Mac, with a shortcut to turn it on.
- **Easier to find.** Screen time can now be turned on in Settings › Privacy and from the command palette (“Screen time” opens its card), and its card sits right after History instead of at the bottom. Actions gained buttons for Ask about the screen, Scripts and Login items, and the clipboard search box shows an example of smart search.

### Changed
- New cards in the System tab now appear next to where they belong, even if you reordered your cards.

## 1.68.0

### New
- **Screen time.** A new card in the System tab shows how long you spend in each app, today or as a daily average over 7 or 30 days, split into focus, neutral and distraction, with an hour-by-hour timeline for today and a bar per day for the week and month. Right-click an app to change its category. It counts only the app in front and only while you are using the Mac (it pauses after 2 minutes without input). It starts off: turn it on in the card. Everything stays in a small file on your Mac, and Delete history erases it.

## 1.67.0

### New
- **Rewrite anywhere.** Select text in any app, press ⌃⌥⌘R (or pick “Rewrite selected text” in the command palette) and choose Fix, Clearer, More formal, Friendlier, Shorter or In English, or press 1 to 6. Press Replace and the new text takes the place of your selection; your clipboard goes back to what it held before, and the rewrite never lands in your clipboard history. Runs on your Mac’s on-device AI; nothing leaves your Mac. The shortcut can be changed in Settings › Shortcuts and actions.

## 1.66.0

### New
- **Ask about the screen.** Choose “Ask about the screen” in the command palette (or add it to your favorites), select any area, an error message, a chart, a page in another language, and ask: Explain, Summarize, Translate, What should I do?, or type your own question. Menew reads the text on your Mac and your Mac’s on-device AI answers; nothing is uploaded. Without Apple Intelligence you still get the recognized text, ready to copy.

## 1.65.0

### New
- **Smart clipboard search.** Type what you remember instead of the exact words: “the hotel link from yesterday”, “that Xcode error”, “images from today”. Menew understands dates (today, yesterday, this week) and types (link, image, file), matches word roots (“erro” finds “error”, “compilação” finds “Compile”) and close synonyms using macOS’s own language model. These results show up after the exact matches, in the clipboard panel and the command palette. Works on any Mac, no Apple Intelligence needed, nothing leaves your Mac.

## 1.64.0

### New
- **“Why is my Mac slow?”** A button at the bottom of the System tab (and in the command palette) checks memory pressure and swap, CPU now and over the last hour, heat, disk space, Low Power Mode and uptime, then tells you what is wrong and which apps are to blame. With Apple Intelligence it also explains it in plain words with suggestions. It never suggests quitting macOS system processes, and it works without Apple Intelligence too.
- **Share clipboard items.** Right-click an item (or use the new button in the preview) to send it with the macOS share menu: AirDrop, Messages, Mail, Notes or any app that accepts it.

### Fixed
- The SSD health line in the Disk card never appeared. It does now.

## 1.63.0

### New
- **Natural-language commands.** In the command palette, start with “do” (or “faz”, “mach”, “haz”) and say what you want: “do dark mode, keep the Mac awake and open Safari”. Your Mac’s on-device AI picks the matching actions, window layouts and apps, shows you the steps, and runs them only when you press Do it. It never picks actions that delete or quit things, and nothing leaves your Mac. Needs Apple Intelligence; without it, the palette tells you how to turn it on.

## 1.62.1

### Fixed
- **Wi-Fi details now show up.** In 1.62 the Wi-Fi row in the Network card never appeared. It now shows in the Network card and in the network icon’s panel.
- Login and background items: entries that don’t belong to an app show the program they run instead of repeating their name, and apps that aren’t installed get a generic icon.

## 1.62.0

### New
- **Wi-Fi details.** The Network card in System now shows your Wi-Fi signal and noise in dBm, a quality rating based on the signal-to-noise ratio, link speed, channel and width, band (2.4, 5 or 6 GHz) and standard (Wi-Fi 4 to 7). It needs no location permission, so the network name isn’t shown.
- **Login and background items.** “Login and background items” in the command palette lists the launch agents and services apps installed to start with your Mac or run hidden, with the app that owns each one and whether it starts at login. Show any of them in Finder, or jump to System Settings to turn one off.

## 1.61.0

### New
- **Script commands.** Run your own scripts from the command palette, like Raycast. Choose “Open scripts folder” in the palette, drop in any shell, Python, Node, Ruby or AppleScript file, and it shows up as a command. Raycast script headers work as they are: title, emoji icon, mode (silent, compact or full output) and one argument, typed after the script’s name (“greet Ana”). Scripts run only when you pick them, with Homebrew on the PATH, and stop after 2 minutes.

## 1.60.0

### New
- **Uninstall apps, leftovers included.** Open “Uninstall app…” from the command palette, Actions or your favorites, then drop an app or pick one. Menew lists the app plus the preferences, caches, containers, saved state, logs and launch agents it left in your Library, with their sizes. Untick anything you want to keep; the rest goes to the Trash (nothing is deleted outright). If the app is open, Menew quits it first. Apps that come with macOS are never touched.

## 1.59.0

### New
- **Screen recording.** Record an area or the whole screen (press ↩) as a video, from the command palette, Actions or your favorites. A floating Stop button shows the time and never appears in the recording. The file goes to your Desktop.
- **GIFs.** Same thing, saved as a looping GIF (up to 30 seconds), ready to drop into an issue or a chat.
- **Scrolling capture.** Pick the part of a page or list that scrolls and Menew scrolls it for you, joining each piece into one long image that opens in the screenshot editor. Fixed headers and footers appear only once. Press esc to stop early.

## 1.58.0

### New
- **7- and 30-day history.** The History card in System now goes back a week or a month, hour by hour, and the list of apps that used the most CPU, memory or battery follows the period you pick. Everything stays in a small file on your Mac.
- **Custom alert rules.** In Settings › Alerts, build your own: pick a metric (CPU, memory, chip temperature, battery, free space, download or upload), above or below a limit, and for how long. For example “CPU above 80% for 10 min” or “battery below 30%”. Each rule notifies once and again only after the condition clears.

## 1.57.0

### New
- **Drag to snap.** Drag a window to the left or right edge of the screen for a half, to the top for full screen or into a corner for a quarter. A preview shows where it will land; let go to snap. Turn it off in Settings › Shortcuts and actions. It steps aside automatically when Rectangle, Magnet, BetterSnapTool or Moom is running.

## 1.56.0

- **Separate menu bar icons**: turn on Settings → Menu bar → Separate icons and each metric you show (CPU, memory, network, disk, battery, temperature) gets its own icon. Click one for a panel with just that metric: CPU with cores and the busiest apps, memory pressure, network with apps using it, disk with SSD health, battery with watts and accessories, or temperatures and fan.
- **Temperature in the menu bar**: the chip temperature can now be one of the menu bar items, in the single icon or as its own.
- The Menew icon still opens the full menu. Arrange the icons by holding ⌘ and dragging them.

## 1.55.0

- **Temperatures and fans**: a new Temperatures card in the System tab shows the chip (hottest sensor and average), SSD and battery in °C, each with a color from green to red, and the fan speed in rpm. “See all sensors” lists every one your Mac reports.
- **Clearer cores**: the Processor card now says what each group is and how many cores it has (“Performance · 4 cores · heavy tasks”, “Efficiency · 6 cores · light tasks, save battery”). Hover a bar to see that core's load.
- Temperatures and fans are read-only and use the same interfaces as other monitors; if a future macOS changes them, Menew just hides that number. Macs without a fan don't show the fan line.

## 1.54.0

- **Performance and efficiency cores**: the Processor card shows every core of your Apple Silicon Mac, grouped into performance and efficiency, with their average.
- **Power in watts**: the Battery card shows how much the whole Mac is drawing right now, the real time remaining (or until full) and, when plugged in, how much of the charger's power is being used.
- **SSD health**: the Disk card shows the health your internal SSD reports (SMART), and turns red if it starts failing.
- **Runaway app alert**: turn it on in Settings → Alerts to get a notice when an app stays above 90% CPU for about 6 minutes.
- **Copy report**: one click at the bottom of the System tab copies model, chip, macOS, memory, disk, battery, SSD health and uptime, ready to send to support or IT.

## 1.53.0

- **A tidier Menew**: with so many features, the menu got long, so this version reorganizes it.
- **Favorites in Actions**: your most used actions sit at the top in one tap. Tap Edit to remove one or add others (Read QR, 10-minute timer, focus, free up space and more). Brightness stays visible, and the other sections fold away with a summary like “9 open” or “3 active”.
- **Settings in its own window**, like System Settings: categories in a sidebar and a search box that finds any setting (“password”, “shortcut”, “battery”). Opens from the gear, ⌘, or the command palette.
- **A compact System tab**: the rings and clocks stay on top; CPU, memory, battery, network, disk and processes become one-line rows with their main number. Tap to open a card. **Arrange cards** lets you reorder them, keep each one open or closed, and hide the ones you don't use.
- **Last 24 hours, fixed**: the app list now follows the chart you pick (CPU, memory or battery) and counts helper processes under their app.
- **The command palette shows what it can do**: with an empty search, it suggests commands like “timer 10m tea”, “remind … tomorrow 9am” or “ai …”. Click one to try it.

## 1.52.0

- **Timers and alarms from the command palette**: type “timer 10m tea”, “timer 90s”, “timer 1h30” or “alarm 7:30 meeting” (also “temporizador”, “alarme”, “wecker”, “alarma”) and press ↩. The countdown shows in the menu bar and, on time, Menew plays a sound and sends a notice.
- Several timers can run at once; the next one shows in the menu bar. Type “timer” in the palette to cancel one.

## 1.51.0

- **Last 24 hours**: the System tab now has a chart of CPU, memory and battery over the last day, so you can see when the Mac got busy or how fast the battery went down.
- **Which apps used the most battery**: while the Mac is on battery, Menew notes every few minutes which apps use the most energy and shows the top five for the day.
- The history is a small file on your Mac, and the energy check only runs on battery, every 5 minutes.

## 1.50.0

- **Search inside clipboard images**: Menew now reads the text in the screenshots and images you copy, so searching ⌘⇧V for “order 4821” finds that screenshot with the order number. Images already in your history are read too, slowly in the background.
- “Copy text” on an image is now instant when it has already been read. Everything happens on your Mac; turn it off in Settings → Clipboard if you prefer.

## 1.49.0

- **Snippets with fields**: write `{input:Name}` in a snippet and Menew asks for it in a small window before pasting, so one snippet becomes a real template (“Hi {input:Name}, about order {input:Order}…”). The same field can appear several times.
- **Cursor position**: put `{cursor}` where you want to keep typing; after pasting, the cursor goes right there.
- **More variables**: `{weekday}` and `{tomorrow}` join `{date}`, `{time}` and `{clipboard}`. Works both in ⌘⇧V and with snippet abbreviations.

## 1.48.0

- **Transcribe audio and video**: drop a meeting recording, voice memo or video on the shelf and choose Transcribe (Portuguese, English, Spanish, German, Chinese, French, Italian or Japanese). The text is saved as a note in Menew and copied to the clipboard.
- It runs on your Mac with no internet. On macOS 26 it uses Apple's new transcriber, great with long recordings, and downloads the language model the first time. Older macOS versions use on-device speech recognition and ask for permission once.

## 1.47.0

- **Offline translation**: copy some text, open the command palette and type “translate english” (or Portuguese, Spanish, German, French, Italian, Japanese or Chinese). Apple's translator does it on your Mac and the result is copied, shown in a small window.
- It works on macOS 15 or later **without Apple Intelligence**, so many more Macs get translation. The first time you use a language, macOS offers to download it. Translations now always use Apple's translator, which is more faithful than the AI model.

## 1.46.0

- **Emoji in the command palette**: type “emoji” or “:” followed by a word, like “emoji rocket”, “emoji coração” or “:fire”, and press ↩ to paste it into the app you're using. Common words work in all five languages.
- **Symbols without a key**: type “arrow right”, “degree”, “euro”, “check”, “approximately” or “command” to get →, °, €, ✓, ≈ or ⌘, plus fractions, math signs, currencies and the Mac keyboard symbols.

## 1.45.0

- **Quick reminders from the command palette**: type “remind pay the bill tomorrow at 9”, “lembrar ligar pro João sexta 14h” or “erinnern Arzt morgen um 9 Uhr”, press ↩, and it's in the Reminders app with the date and an alert. Without a time it becomes an all-day reminder; without a date, a simple to-do.
- Dates are understood on your Mac in English, Portuguese, German, Spanish and Chinese. Menew asks for Reminders access the first time you use it.

## 1.44.0

- **Accessory batteries**: the System tab now shows the battery of your connected Magic Mouse, Magic Keyboard, Magic Trackpad and AirPods (left, right and case), in red when it's running low.
- **Low-battery alert**: turn on “Accessory battery” in Settings → Alerts to get a notice when one drops to 15% or less, so your mouse doesn't die in the middle of a call.

## 1.43.0

- **Read QR codes from the screen**: select the area with a QR code (from the command palette or the menu bar icon's right-click menu) and its content goes to the clipboard. Links are never opened on their own, since a QR code can be misleading.
- **Show a QR code**: turn the copied text or link into a big QR code your phone can scan, or create a Wi-Fi QR code so guests can join your network by pointing the camera. Copied links also offer “Show QR code” in the command palette.

## 1.41.1

- **Support Menew**: if Menew saves you time, you can now buy the author a coffee from Settings → Help, the menu bar icon's right-click menu or the command palette (type “coffee”). Nothing ever pops up asking for it.

## 1.41.0

- **Smart clipboard**: Menew recognizes what you just copied and offers the right action at the top of the command palette and in the item's right-click menu in the history.
- **Phone numbers**: call with FaceTime or your iPhone, or open a WhatsApp chat. **Addresses**: open in Maps. **Emails**: write to them. **Tracking codes** (Correios and other international codes, UPS): track the package. **Colors**: copy as HEX, RGB or HSL. **Meeting links** (Zoom, Meet, Teams…): join the call.
- Recognition happens on your Mac, and only when the copied text is basically just that (a sentence with a number in the middle won't trigger anything).

## 1.40.0

- **Ask AI in the command palette**: type “ai” (or “ia”, “ki”, “?”) followed by any question, like “ai how do I politely decline a meeting?”. The answer streams into a small window, in the language you asked, and ⌘C copies it.
- **AI in notes**: a note's ⋯ menu can now summarize it or extract its to-dos, added at the end as a “Summary” section or a checklist (including tasks assigned to other people).
- Like the other AI features, everything runs on Apple Intelligence's model on your Mac: no internet, no account, no cost. Needs macOS 26 or later with Apple Intelligence on.

## 1.39.0

- **Today's agenda**: the next-meeting card now has a “Today · N” button that opens the day's meetings. Past ones are dimmed; click one to join the call or open it in Calendar. Today's meetings also show up in the command palette.
- **Copy my free times**: one click puts your free slots for the next 5 working days on the clipboard, ready to paste into an email or chat (“Mon 11/02: 9:00–10:30, 14:00–18:00”). Meetings you declined or marked as free don't count, and you can set your working hours in Settings → Calendar.

## 1.38.0

- **Quick links in the command palette**: type a keyword and what you're looking for to open the right page in your browser. Built in: “g” (Google), “ddg” (DuckDuckGo), “yt” (YouTube), “wiki” (Wikipedia), “gh” (GitHub) and “maps” (Apple Maps).
- **Your own links**: add them in Settings → Quick links with {q} where the text goes, like “jira” → `https://company.atlassian.net/browse/{q}`, then type “jira ABC-123”. Letter case is kept.
- Type an address like “github.com/quost” to open it directly, and any search ends with “Search on Google” (or your first search link). Menew itself doesn't access the internet for this; your browser does.

## 1.37.0

- **PDF tools on the shelf**: drop PDFs on the shelf and a new PDF menu appears. Combine them into one (in shelf order), compress them with the same “Reduce File Size” filter as Preview (text stays selectable), rotate every page 90°, or turn each page into a PNG image.
- **Images to PDF**: the image menu can now combine the photos on the shelf into a single PDF.
- As with images, the originals are never changed: results are new files next to them, ready to drag out. If compressing wouldn't make a file smaller, Menew keeps the original.

## 1.36.0

- **On-device AI in the command palette**: copy some text, open the palette and type “summarize”, “formal”, “friendly”, “clearer”, “shorter”, “fix” or “translate english”. The result is copied (and pasted, if auto-paste is on), in the same language as your text unless you asked for a translation.
- It uses Apple Intelligence's model on your Mac only, never the cloud: no account, no API key, no cost, and the text never leaves your Mac. Needs macOS 26 or later with Apple Intelligence turned on; otherwise the palette tells you why it's unavailable.

## 1.35.0

- **Siri, Shortcuts and Spotlight**: Menew's actions now show up across macOS with no setup. Capture the screen, copy text from screen, mute the microphone, keep the Mac awake, presentation mode, dark mode, start a focus timer, activate a work profile, create a note, or open the clipboard history and command palette.
- Ask Siri (“Mute my microphone with Menew”, “Activate Work in Menew”), type the action in Spotlight, or combine Menew's actions with other apps in the Shortcuts app. Phrases and names work in all five languages, and your work profiles are offered by name.

## 1.34.0

- **World clocks**: add the cities you work with in Settings → World clocks and they show at the top of the System tab, with the time difference and a “tomorrow” or “yesterday” note when it's already another day there.
- **Time zone conversion in the command palette**: type “3pm ny to london”, “15h em Lisboa”, “9:30 in Shanghai” or just a city like “tokyo” to see the time there, daylight saving included. ↩ copies it. City names work in all five languages, plus nicknames like NY, SF and SP.
- Calculated results in the palette (times, timestamps) now always show first, even with a “:” in what you typed.

## 1.33.0

- **Image tools on the shelf**: drop photos on the shelf and a new image menu appears. Convert them to JPG, PNG or HEIC, shrink them all at once (longest side 3000, 2000, 1200 or 800 px), or remove location and other metadata before sharing.
- The originals are never changed: each result is a new file next to the original (or in Downloads), and it takes the original's place on the shelf, ready to drag into a chat or email. Rotated photos come out upright, and everything runs on your Mac.

## 1.32.0

- **Ports in use**: Actions → Apps now lists the servers running on your Mac (node, Docker, databases) with their ports, and stops the one you pick. In the command palette, type “port” or a port number like “3000”.
- **Developer tools in the command palette**: “Generate UUID”, “Copy Unix timestamp”, paste a 10 or 13 digit timestamp to see its date, and “Decode JWT” to read a copied token's header and payload with readable dates (the signature isn't checked).

## 1.31.0

- **Switch sound output and microphone**: a new Sound section in Actions shows what's playing and recording, and lets you switch to AirPods, headphones, speakers, displays or another microphone in one click. Alert sounds follow along. From the command palette, type “airpods” or “microphone”.
- **Presentation mode**: one switch before presenting or sharing your screen. It hides desktop icons, keeps the Mac awake, pauses clipboard capture and shows only the icon in the menu bar, so no numbers or history leak on screen. Turning it off undoes only what it changed.
- **Automations**: new trigger “When presentation mode turns on/off” (for example, to run a Shortcut that turns on Do Not Disturb) and a new action to turn presentation mode on or off.
- **Pen in screenshots**: draw freely on a capture, in any of the 8 colors.

## 1.30.1

- **Fixed: command palette search**: typing in the palette could keep showing the suggestions instead of the results. Results now update as you type.

## 1.30.0

- **Screenshots with annotations**: press ⌃⌥⌘S (or use Capture screen in Actions or the command palette) to select an area, or press Space to capture a window. The capture opens in an editor where you can add arrows, rectangles and text in 8 colors, and blur passwords, emails or numbers before sharing.
- **Copy, save, drag or pin**: copy it (⌘C), save it as PNG (⌘S), drag it straight into Slack, Mail or Finder, or pin it floating above your windows to keep it in view; double-click a pinned capture to edit it again. “Copy text” reads the text in the capture, on your Mac.
- “Capture the whole screen” in the command palette grabs the screen under the mouse.
- **Clear permission prompt**: screenshots and Copy text from screen now ask for Screen Recording permission and show where to turn it on, instead of failing silently.

## 1.29.0

- **Settings backup**: Settings → Backup exports your settings, keyboard shortcuts, snippets, work profiles, automations and “Never quit” list to a `.menew` file. Restore it later or on another Mac, and Menew reopens with everything in place.
- Notes and clipboard history are optional. Protected and password notes are never included, since their contents stay in the macOS Keychain.
- Restoring keeps the notes already on your Mac and adds the ones from the backup.

## 1.28.0

- **Password notes**: a new note type for logins, Wi-Fi, PINs and the like. Each line is a name and a value; values stay hidden as •••, with an eye to reveal and a button to copy. Password notes are always protected with Touch ID and stored in the macOS Keychain. Create one with the key button next to New.
- **Safe copying**: values copied from a password note are marked confidential, so neither Menew nor other clipboard managers keep them in history, and they're cleared from the clipboard after 30 seconds.
- **Switch a note's type**: in a note's ⋯ menu, choose Text or Passwords. Nothing is lost; text lines become name and value fields and back.
- **Touch ID no longer closes the menu**: unlocking a protected note keeps Menew open and goes straight to the note.

## 1.27.3

- **Lighter in the background**: with the menu closed, Menew no longer reads GPU and disk activity (they only show in the menu) and checks free disk space less often. Idle CPU dropped from 0.9% to 0.5%, wakeups from about 98 to 14 per second, and memory from 55 MB to 19 MB, so it's easier on the battery.
- **Smaller download**: the app is roughly half the size, without debug symbols and unused Sparkle files.

## 1.27.2

- **Software dimming for monitors without DDC**: monitors that don't accept brightness over the cable (often because a USB-C adapter or hub blocks it) now get a brightness slider too, marked “by software”. Menew dims the picture of that screen only, without talking to the monitor, so it can't freeze anything.
- The level is remembered per monitor and comes back when you reconnect it or reopen Menew; quitting Menew restores the normal picture. Brightness automations work on these monitors as well.

## 1.27.1

- **Fixed: screens freezing with an external monitor**: on some Macs (like a MacBook Air M4 with a second display), opening Actions could freeze every screen for a few seconds. Menew now reads an external monitor's brightness only once per connection, gives up quickly on a monitor that doesn't answer, and never sends commands to one that hasn't answered correctly.
- **New setting**: Settings → Shortcuts → “External monitor brightness” turns off brightness control over the cable (DDC/CI) entirely, in case your monitor or adapter still misbehaves.
- Opening Actions no longer waits on slow network or USB hub volumes.

## 1.27.0

- **New automation triggers**: when a meeting is about to start (on time or 1 to 15 minutes before), when a focus session starts or ends, and when the Mac wakes from sleep.
- **Run a Shortcut**: any shortcut from the Shortcuts app can now be an automation action, so you can chain Menew with everything Shortcuts can do. If it fails, you get a notice.
- **Tidier Apps section**: “Force quit” and “Never quit” now sit in a card that matches the rest of Actions, and “Never quit” shows which apps are protected.

## 1.26.0

- **App control**: a new Apps section in Actions to **quit all** apps, **quit others** (everything but the app you were using), **hide others**, or **force quit** a frozen app. Also from the command palette: “quit all”, “quit others”, “hide others”.
- **Work profiles can quit every other app**: turn on “Quit the other apps” in a profile and it closes everything else before opening your apps, for a clean work mode.
- **New automation action**: “Quit all apps”, for rules like “when the battery drops below 5%, quit all apps”.
- Quitting is always a normal request, so apps with unsaved work ask you first; force quit is only ever manual. Finder and Menew are never quit, and a “Never quit” list keeps the apps you choose open.

## 1.25.0

- **Apps using the network**: in System → Internet, open “Apps using the network” to see which apps are downloading and uploading right now, with the speed of each. Helper processes count toward their app (Chrome's helpers show as Chrome).
- It reads macOS's own `nettop`, with no extra permission and nothing sent anywhere. Measuring costs a bit of CPU, so it only runs while the list is open and on screen, and stops as soon as you close it.

## 1.24.0

- **Duplicate files**: the deep scan in Free up space now finds identical copies of your files (1 MB and up) in your home folder. Files are compared byte for byte, the oldest copy is kept as the original, and each copy shows which file it duplicates.
- **Large files**: the limit went down from 500 MB to 250 MB, and every file you review now shows the folder it's in.
- As always, nothing is preselected and anything you remove goes to the Trash. iCloud files that aren't downloaded are skipped, so the scan never triggers downloads.

## 1.23.0

- **Paste queue**: click the numbered-list button next to the clipboard search (or type “queue” in the command palette), then copy several things. Each ⌘V pastes the next one, in the order you copied them, and the queue turns itself off when it's empty. Great for filling forms or moving data between apps.
- The menu bar shows how many items are left, the clipboard tab shows what the next ⌘V will paste, and you can add any history item with right-click → Add to paste queue.
- Menew only watches for ⌘V while the queue is on (it uses the Accessibility permission it already asks for) and never changes the keystroke itself.

## 1.22.0

- **Transform copied text from the command palette**: copy some text, press ⌃⌥Space and type what you want: “upper”, “lower”, “title”, “camel”, “snake”, “kebab”, “accents”, “sort lines”, “json”, “base64”, “url” or “count”. Each option previews the result, and picking one puts it on the clipboard (and pastes it, if auto-paste is on). Invalid JSON or Base64 shows a notice instead of mangling your text.
- **Fixed: freezes with external monitors**: opening Actions scanned the hardware and talked to monitors over DDC on the main thread, all at once. Turning off a second monitor could then spike the CPU, freeze the menu for a few seconds and hide its brightness slider. Monitor communication now runs in the background, one request at a time, gives up quickly on a monitor that doesn't answer, and the list updates by itself when a screen is connected or disconnected.

## 1.21.0

- **Focus timer**: in Actions → Focus, start 25 minutes (or 15, 45, 50, 90 from the ⋯ menu), or type “focus 50” in the command palette for any length. The time left shows in the menu bar, and you can add 5 minutes or stop at any time.
- While you focus, Menew can mute the mic, keep the Mac awake and pause the clipboard. When the time is up it plays a sound, sends a notification, puts back only what it changed and starts a 5-minute break (you can turn the break off).

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
