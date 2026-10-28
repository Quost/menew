# Contributing to Menew

Thanks for wanting to help! Menew is a small, dependency-free Swift app, so getting started takes a minute.

Please follow our [code of conduct](CODE_OF_CONDUCT.md). Found a security problem? Report it privately as described in [SECURITY.md](SECURITY.md), not in a public issue.

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
| `Cleaner.swift` | Free up space: scans and cleaning |
| `Snippets.swift` | Saved texts and placeholders |
| `Updater.swift` | Auto-updates (Sparkle) |
| `L10n.swift` | All UI strings and translations |
| `Theme.swift` | Colors and shared UI components |
| `HotKey.swift` | Global shortcuts (Carbon) |
| `Snapshot.swift` | Renders screenshots of every screen |

## Website

The site (https://menew.web.app) is generated in 5 languages from `site/template.html` and `site/i18n/*.json`:

```bash
python3 scripts/build-site.py
```

Don't edit `docs/**/index.html` by hand; CI checks they match the template. Visitors are sent to their browser's language automatically, and the language menu remembers their choice.

## Screenshots

Changed something visual? Regenerate the screenshots used by the README and website:

```bash
./build.sh
build/Menew.app/Contents/MacOS/Menew --snapshot /tmp/menew-shots -language en
```

This renders every screen in light and dark mode using fake data, never your real clipboard. Copy the ones you need into `docs/assets/`.

## Good first contributions

No Swift needed for these:

- **GIFs for the README and website.** Short screen recordings (5–10 s) of the ⌘⇧V panel, the quick actions and the cleaning mode. Keep them under 3 MB and add them to `docs/assets/`.
- **Translations.** Spot something awkward in your language? All strings live in `Sources/Menew/L10n.swift`. New languages are welcome too.

## Commit messages

Menew follows [Conventional Commits](https://www.conventionalcommits.org). A check runs on every push and pull request.

```
<type>(<optional scope>): <short summary in lowercase>
```

| Type | Use it for |
|---|---|
| `feat` | A new feature |
| `fix` | A bug fix |
| `docs` | README, CONTRIBUTING, comments |
| `refactor` | Code changes that don't change behavior |
| `perf` | Performance improvements |
| `ci` | GitHub Actions, release pipeline |
| `chore` | Maintenance (dependencies, config, Homebrew bumps) |

Common scopes: `ui`, `i18n`, `clipboard`, `snippets`, `notes`, `monitor`, `cleaner`, `actions`, `updates`, `installer`, `release`, `site`, `homebrew`.

Examples: `feat(notes): add Markdown checklists`, `fix(clipboard): keep pinned items when clearing history`.

Add `!` after the type (`feat!:`) for breaking changes.

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
| `SPARKLE_PRIVATE_KEY` | EdDSA key that signs updates (`generate_keys --account menew -x key.txt`) |

Without them, the release is still published, just unsigned. Each release also uploads `appcast.xml` (the Sparkle update feed) and bumps `Casks/menew.rb` for Homebrew.

## Numbers

```bash
scripts/stats.sh
```

Downloads per version, update checks and repo traffic, all from GitHub's public stats. Menew itself never phones home.

## Reporting bugs

Use **Report a problem…** in Menew's right-click menu: it opens a GitHub issue with your versions filled in. Or open an [issue](https://github.com/Quost/menew/issues/new/choose) directly.
