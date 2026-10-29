# Menew: project rules for agents

Native macOS menu bar app (Swift/SwiftUI, Swift Package). Public, MIT, distributed outside the App Store: signed with Developer ID, notarized, auto-updated with Sparkle, installable with Homebrew. Website: https://menew.web.app (Firebase Hosting, `docs/`).

## Always keep these in sync

Whenever a change is visible to users (new feature, renamed screen, new setting, visual change), update all of these **in the same change**:

1. **Translations**: every UI string goes through `L("…")` and needs all 4 translations in `Sources/Menew/L10n.swift` (en, de, es, zh; Portuguese is the key). Missing keys silently fall back to Portuguese.
2. **Screenshots**: regenerate in English and copy the ones that changed into `docs/assets/` (used by the README and the website):
   ```bash
   ./build.sh
   build/Menew.app/Contents/MacOS/Menew --snapshot /tmp/shots -language en -notesReading YES
   ```
   Snapshots use fake data (`ClipboardManager.demo()`, `NotesStore.demo()`); never screenshot the user's real clipboard or notes. Add new screens to `Snapshot.swift`.
3. **README.md**: the Features table, Keyboard shortcuts, Privacy and Roadmap sections.
4. **Website**, in 5 languages like the app. Never edit the generated `docs/**/index.html`; edit `site/template.html` (layout) and `site/i18n/<lang>.json` (texts, all 5 files), then run `python3 scripts/build-site.py` (it also writes `docs/sitemap.xml` and `docs/robots.txt`). Localized screenshots live in `docs/assets/<lang>/` (English in `docs/assets/`); regenerate them with `-language pt|de|es|zh`. Link-preview images (`docs/assets/og/<lang>.png`, 1200×630) come from `swift scripts/make-og.swift`; rerun it after changing the title or the screenshots. Pushing `docs/` to `main` deploys it, and CI fails if the generated pages are out of date.
5. **CHANGELOG.md**: add a `## X.Y.Z` section *before* tagging. It becomes the release notes in the in-app update window and on GitHub. Write it for users, in English.

## Commits

- [Conventional Commits](https://www.conventionalcommits.org), in English, enforced by commitlint (`commitlint.config.mjs`). Examples: `feat(notes): …`, `fix(clipboard): …`, `docs: …`, `ci(release): …`.
- Commits are signed with the maintainer's SSH key. If `git commit` hangs, the key isn't loaded: ask the user to run `ssh-add --apple-use-keychain ~/.ssh/id_ed25519`. Never disable signing.
- Never force-push or rewrite history without explicit approval.

## Releasing

1. Update `CHANGELOG.md` (and the items above), commit, push.
2. `git tag -a vX.Y.Z -m "Menew X.Y.Z" && git push origin vX.Y.Z`
3. The `Release` workflow builds, signs, notarizes, publishes the `.dmg`/`.zip`/`appcast.xml` and bumps `Casks/menew.rb`. Check it finished green.

## Don'ts

- No telemetry or analytics in the app, ever (the README and site promise this). The website only uses GoatCounter (cookieless; `GOATCOUNTER` in `scripts/build-site.py`, clicks tagged with `data-goatcounter-click`); never add cookies or another tracker. Network calls are limited to the update check, the public-IP lookup, the user-started speed test and the currency rate fetched when the user presses ↩ on a conversion in the command palette.
- Don't add third-party dependencies without a strong reason (only Sparkle today).
- Don't use the WEG certificates in the keychain; the project uses the personal Developer ID (team `9527N6XKKW`).
- Cleaner: user files go to the Trash, only caches/logs are deleted, and `com.apple.*` caches are skipped.
