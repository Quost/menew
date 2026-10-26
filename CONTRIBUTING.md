# Contributing to Menew

Thanks for wanting to help! Menew is a small, dependency-free Swift app, so getting started takes a minute.

## Getting started

Requirements: macOS 14+ and Xcode 16+ (or the Swift 6 toolchain).

```bash
git clone https://github.com/Quost/menew
cd menew
./build.sh --install   # builds build/Menew.app, copies it to /Applications and opens it
```

You can also open `Package.swift` in Xcode and run the `Menew` scheme.

> Local builds are signed ad-hoc, so macOS may ask again for Accessibility permission after each rebuild. Remove the old entry in System Settings → Privacy & Security → Accessibility and add it again.

## Project layout

| File | What lives there |
|---|---|
| `App.swift` | Entry point, menu bar item, popover, global shortcuts |
| `SystemMonitor.swift` | CPU, memory, disk, network, battery, processes |
| `ClipboardManager.swift` | Clipboard capture, history, search, paste |
| `ClipboardViews.swift` | ⌘⇧V panel, list, preview |
| `Views.swift` | Popover tabs: System, Actions, Notes, Settings |
| `Toolbox.swift` | Quick actions |
| `Cleaning.swift` | Keyboard lock and screen cleaning |
| `Extras.swift` | Bluetooth devices, public IP, speed test, notes |
| `Theme.swift` | Colors and shared UI components |
| `HotKey.swift` | Global shortcuts (Carbon) |
| `Snapshot.swift` | Renders screenshots of every screen |

## Screenshots

Changed something visual? Regenerate the screenshots used by the README and website:

```bash
swift build -c release
.build/release/Menew --snapshot /tmp/menew-shots
```

This renders every screen in light and dark mode using fake data, never your real clipboard. Copy the ones you need into `docs/assets/`.

## Good first contributions

No Swift needed for these:

- **GIFs for the README and website.** Short screen recordings (5–10 s) of the ⌘⇧V panel, the quick actions and the cleaning mode. Keep them under 3 MB and add them to `docs/assets/`.
- **Translations.** Spot something awkward in your language? All strings live in `Sources/Menew/L10n.swift`. New languages are welcome too.

## Guidelines

- **Keep it native and light.** No third-party dependencies unless there's a very good reason.
- **Privacy first.** No telemetry, no network calls the user didn't ask for.
- **Match the surrounding code.** Small files, clear names, comments only where something isn't obvious.
- **Test both themes.** Light and dark mode, and a small screen.
- **One change per pull request**, with a screenshot if it touches the UI.

## Releasing (maintainers)

Push a tag and GitHub Actions does the rest:

```bash
git tag v1.2.0
git push origin v1.2.0
```

The `Release` workflow builds a universal app, signs and notarizes it (when the secrets below exist), and publishes `Menew.dmg` and `Menew.zip`. The website always links to the latest release, so it doesn't need to change.

| Secret | Content |
|---|---|
| `DEVELOPER_ID_P12` | Developer ID Application certificate exported as `.p12`, base64-encoded |
| `DEVELOPER_ID_P12_PASSWORD` | Password used when exporting the `.p12` |
| `APPLE_ID` | Apple ID email of the developer account |
| `APPLE_TEAM_ID` | Team ID (10 characters) |
| `APPLE_APP_PASSWORD` | App-specific password from appleid.apple.com |

Without them, the release is still published, just unsigned.

## Reporting bugs

Open an [issue](https://github.com/Quost/menew/issues) with your macOS version, Mac model (Apple Silicon or Intel), what you expected and what happened.
