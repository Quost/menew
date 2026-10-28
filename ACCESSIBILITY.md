# Accessibility

We want Menew to work for everyone who uses a Mac. This page says honestly what works today, what doesn't yet, and how to tell us about a barrier.

## What works

- **Native controls.** Menew is built with SwiftUI and AppKit, so text, buttons, switches and menus are standard macOS controls.
- **Dark and light mode**, following your Mac or chosen in Settings. The glass and translucent backgrounds are drawn by macOS, so they follow its **Reduce transparency** setting.
- **Keyboard.** The clipboard panel (⌘⇧V) works entirely from the keyboard: type to search, arrows to move, Return to paste, ⌘1–9, Tab to switch filters, Esc to close. The menu itself opens with a global shortcut (⌥⌘M by default), and both shortcuts can be changed.
- **Five languages**: English, Portuguese, German, Spanish and Chinese.
- **No time limits**, except the keyboard-cleaning lock, which you start yourself and which ends after 2 minutes or with a click.

## Known limitations

- **VoiceOver hasn't been fully tested yet.** Some icon-only buttons and the menu bar item may not have a spoken label, and charts (CPU graph, sparklines, rings) have no text alternative beyond the numbers shown next to them.
- **Dynamic Type**: text sizes are fixed and don't follow a larger system text size.
- **Color**: usage warnings (orange and red) also show the number, but the memory and disk bars rely on color to tell the parts apart.

We're working on these. Pull requests that improve accessibility are very welcome.

## Supported environments

macOS 14 Sonoma or later, on Apple silicon and Intel Macs.

## Report a barrier

[Open an issue](https://github.com/Quost/menew/issues/new?template=bug_report.yml) and tell us what you tried, what assistive technology you use (VoiceOver, Switch Control, Voice Control, zoom…), and what got in the way. Accessibility bugs are treated as bugs, not feature requests.
