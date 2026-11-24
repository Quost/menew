# Contributing to Menew

Thanks for wanting to help! Menew is a small, dependency-free Swift app, so getting started takes a minute.

Please follow our [code of conduct](CODE_OF_CONDUCT.md). Found a security problem? Report it privately as described in [SECURITY.md](SECURITY.md), not in a public issue.

## Getting started

Requirements: macOS 14+ and Xcode 16+ (or the Swift 6 toolchain). The on-device AI features need the FoundationModels SDK (`#if canImport(FoundationModels)`, see `AIAgent.swift`), which comes with Xcode 26+; with older tools the app still builds, without them. Releases are built with Xcode 27.

```bash
git clone https://github.com/Quost/menew
cd menew
./build.sh --install   # builds build/Menew.app, copies it to /Applications and opens it
```

You can also open `Package.swift` in Xcode and run the `Menew` scheme.

> Local builds are signed ad-hoc, so macOS may ask again for Accessibility permission after each rebuild. Remove the old entry in System Settings → Privacy & Security → Accessibility and add it again.

## Project layout

The app is one flat Swift target, `Sources/Menew`, with one file per feature. By area:

| Area | Main files |
|---|---|
| Entry point and launch flags | `App.swift` (menu bar item, popover, global shortcuts), `HotKey.swift` (Carbon shortcuts), `Migration.swift`, `DemoMode.swift` |
| Clipboard | `ClipboardManager.swift`, `ClipboardViews.swift`, `SmartClip.swift`, `SmartClipSearch.swift`, `PasteQueue.swift`, `Snippets.swift`, `TextExpander.swift`, `Shelf.swift`, `SecretShare.swift` |
| Notes | `Notes.swift`, `NotesViews.swift`, `Markdown.swift` |
| System monitor | `SystemMonitor.swift`, `MonitorViews.swift`, `SystemHistory.swift`, `Sensors.swift`, `Hardware.swift`, `BatteryCare.swift`, `BatteryWear.swift`, `NetUsage.swift`, `Ports.swift`, `WiFi.swift`, `Diagnosis.swift`, `Alerts.swift`, `AlertRules.swift`, `RunawayWatch.swift` |
| Command palette | `Palette.swift`, `Calculator.swift`, `TextTransforms.swift`, `QuickLinks.swift`, `QuickReminders.swift`, `Emoji.swift`, `Timers.swift`, `Translate.swift`, `ScriptCommands.swift`, `WorldClock.swift` |
| Memory | `Memory.swift`, `MemoryAsk.swift`, `MemoryFeed.swift`, `MemoryGraph.swift`, `MemoryViews.swift`, `Spotlight.swift` |
| Recordings and captions | `Recorder.swift`, `Recordings.swift`, `RecordingsView.swift`, `Transcribe.swift`, `LiveCaptions.swift`, `Meetings.swift`, `Capture.swift`, `ScrollCapture.swift`, `TextRecognizer.swift`, `LiveText.swift` |
| On-device AI | `AIAgent.swift`, `AIFeatures.swift`, `AIText.swift`, `Rewriter.swift`, `ScreenAsk.swift` |
| AI agents and MCP | `AgentHub.swift`, `AgentSources.swift`, `AgentUsage.swift`, `AgentHistory.swift`, `AgentPlugins.swift`, `AgentsView.swift`, `MCPServer.swift` (stdio), `MCPHTTP.swift` (HTTP, key-protected, `127.0.0.1` only) |
| Notch and menu bar | `Notch.swift`, `NotchHover.swift`, `NowPlaying.swift`, `MenuBarPro.swift`, `MenuBarHider.swift`, `NowView.swift` |
| Cleaner, uninstaller, organizer | `Cleaner.swift`, `Uninstaller.swift`, `Organizer.swift`, `StartupItems.swift`, `ImageTools.swift`, `PDFTools.swift` |
| Windows and actions | `Windows.swift`, `DragSnap.swift`, `Profiles.swift`, `Toolbox.swift`, `ActionsView.swift`, `Favorites.swift`, `Automations.swift`, `Focus.swift`, `FocusFilter.swift`, `Cleaning.swift`, `Presentation.swift`, `Intents.swift`, `ShortcutActions.swift` |
| Settings and windows | `SettingsWindow.swift`, `MenewWindow.swift`, `Views.swift` (popover tabs), `Onboarding.swift`, `Backup.swift`, `Feedback.swift`, `Updater.swift` (Sparkle), `LaunchAtLogin.swift`, `AccessibilityGrant.swift` |
| Shared UI, theme and strings | `Theme.swift` (colors, shared components), `L10n.swift` (all UI strings and translations), `Extras.swift` |
| Screenshots and demos | `Snapshot.swift` (renders every screen), `VideoFrames.swift` (promo video frames), `DemoMode.swift` |
| Widgets | `Sources/MenewWidgets` (the widget extension), `Sources/MenewShared` (what the app and widgets share), `WidgetBridge.swift` (the app side) |
| Tests | `Tests/MenewTests` |

Not sure where something belongs? Search for its name: files are named after what they do.

### Launch flags

`App.swift` reads these. Most are for development; the normal app takes none.

| Flag | What it does |
|---|---|
| `--snapshot <folder>` | Renders every screen with fake data into the folder, then quits (see Screenshots) |
| `--preview <tab>` | Opens one tab for a quick look |
| `--demo` | Runs the real app on fake data (see Recording a demo) |
| `--video-frames <folder>` | Renders the promo video frames (see Promo video) |
| `--mcp` | Runs Menew's MCP server over stdio and exits, without opening the app. Agents start it |
| `--agent-hook <agent>` | Called by an AI agent's hook: reports the session state and exits |
| `--hardware` | Prints a hardware report to the terminal |

`Resources/Info.plist` holds a placeholder version. `build.sh` overwrites it with the latest git tag (or `VERSION=…`), so local builds show the right version in Settings.

## Website

The site (https://menew.pururucos.com.br) is built and deployed from [Quost/menew-site](https://github.com/Quost/menew-site), in 5 languages. This repository only holds the content of the `/mac` page: the texts in `site/content.json` and the screenshots in `docs/assets/` (see [site/README.md](site/README.md)). Layout, the overview page, comparisons and SEO are changed in menew-site.

To preview the `/mac` page with your changes, from a checkout of menew-site next to this one:

```bash
python3 scripts/build.py --content mac=../menew/site --serve
```

CI checks the content with menew-site's validator (`python3 ../menew-site/scripts/content.py mac site`). After a merge, the site picks it up by itself within about 30 minutes.

## Screenshots

Changed something visual? Regenerate the screenshots used by the README and website:

```bash
./build.sh
build/Menew.app/Contents/MacOS/Menew --snapshot /tmp/menew-shots -language en
```

This renders every screen in light and dark mode using fake data, never your real clipboard. Copy the ones you need into `docs/assets/` and refresh their WebP copies with `scripts/webp.sh` (needs `cwebp`: `brew install webp`).

### Recording a demo

To record a video of the real, running app (menu bar, popover, command palette, notch, Menew window) without your own data, quit Menew and start it in demo mode:

```bash
./build.sh
build/Menew.app/Contents/MacOS/Menew --demo
```

Every store shows the same fake data as `--snapshot` (clipboard, notes, memory, recordings, meetings, AI agents, profiles…). Nothing real is read or written: files go to a temporary folder that is deleted on quit, settings go to their own domain (`com.matheusquost.menew.demo`, reset with `defaults delete com.matheusquost.menew.demo`), and clipboard capture, Automatic Memory, Spotlight, widgets, automations, agent hooks and the update check stay off. The app is in English; pass `-language pt|de|es|zh` for another language. If you add a store with personal data, give it a `demo()` and load it in `DemoMode.populate`.

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

Common scopes: `ui`, `i18n`, `clipboard`, `snippets`, `notes`, `monitor`, `system`, `cleaner`, `actions`, `palette`, `agents`, `ai`, `notch`, `menubar`, `memory`, `recordings`, `shelf`, `displays`, `windows`, `settings`, `updates`, `installer`, `release`, `site`, `homebrew`.

Examples: `feat(notes): add Markdown checklists`, `fix(clipboard): keep pinned items when clearing history`.

Add `!` after the type (`feat!:`) for breaking changes.

## Tests and checks

```bash
swift test                        # the app's pure logic: passwords, battery wear, meetings, minutes, search
python3 scripts/check-l10n.py     # every L("…") has en, de, es and zh, and no key is repeated
```

Tests live in `Tests/MenewTests` and only cover logic that needs no screen, network, permissions or user data. When you fix a bug in that kind of code, add a test that fails without the fix.

Every pull request runs the same checks on GitHub (`.github/workflows/ci.yml`): it builds the app on macOS 26 like the release does, runs the tests, checks the translations and checks the website content in `site/`. Commit messages are checked separately. On a contributor's first pull request, GitHub waits for a maintainer to approve the run.

## Guidelines

- **Keep it native and light.** No third-party dependencies unless there's a very good reason.
- **Privacy first.** No telemetry, no network calls the user didn't ask for.
- **Match the surrounding code.** Small files, clear names, comments only where something isn't obvious.
- **Test both themes.** Light and dark mode, and a small screen.
- **One change per pull request**, with a screenshot if it touches the UI.

## Pull requests

Pull requests are merged with **Squash and merge**: the whole PR becomes one commit on `main`, and its message is the PR title. So the title must follow Conventional Commits too (`fix(clipboard): …`), and a check fails the PR until it does. Your commits inside the PR can be as granular as you like.

## Changelog

`CHANGELOG.md` is written by hand, for users, in English. In a pull request, add your line under `## Unreleased` at the top (create the section if it isn't there) and leave the version number out: it's chosen when releasing, and a numbered section conflicts as soon as another release ships first.

## Releasing (maintainers)

Before tagging, rename `## Unreleased` to the new version (or add a `## X.Y.Z` section). That section becomes the release notes in the in-app update window and on GitHub.


Maintainers run `scripts/release.sh X.Y.Z "type(scope): message"`: it checks the changelog and translations, regenerates the site, commits, waits for any running release, tags and follows the `Release` workflow to the end. Under the hood it's just a tag, and GitHub Actions does the rest:

```bash
git tag -a v1.2.0 -m "Menew 1.2.0"   # annotated tag, after the changelog is updated and pushed
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

## Promo video

The promo video is rendered off-screen from demo data, so it never shows your real screen and needs no screen recording permission:

```bash
./build.sh
build/Menew.app/Contents/MacOS/Menew --video-frames /tmp/frames -language en
swift scripts/make-video.swift /tmp/frames /tmp/video-out
ffmpeg -framerate 30 -i /tmp/video-out/%04d.jpg -c:v libx264 -crf 26 -pix_fmt yuv420p -movflags +faststart menew.mp4
```

The video has no burned-in text besides shortcuts and the address, so one file serves every language.
