# Changelog

Each version's section is shown in the in-app update window and on the GitHub release.

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
