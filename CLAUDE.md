# Menew: project rules for agents

Native macOS menu bar app (Swift/SwiftUI, Swift Package). Public, GPL-3.0 (the name, icon and site are not covered: see `TRADEMARK.md`), distributed outside the App Store: signed with Developer ID, notarized, auto-updated with Sparkle, installable with Homebrew. Website: https://menew.pururucos.com.br, built and deployed from [Quost/menew-site](https://github.com/Quost/menew-site); this repo only holds the `/mac` page content (`site/`). The old addresses menew.web.app and menew-prd.web.app only 301 to it; never point links at them.

## Always keep these in sync

Whenever a change is visible to users (new feature, renamed screen, new setting, visual change), update all of these **in the same change**:

1. **Translations**: every UI string goes through `L("…")` and needs all 4 translations in `Sources/Menew/L10n.swift` (en, de, es, zh; Portuguese is the key). Missing keys silently fall back to Portuguese.
2. **Screenshots**: regenerate in English and copy the ones that changed into `docs/assets/` (used by the README and the website), then refresh their WebP copies with `scripts/webp.sh` (the site serves the `.webp` when there is one):
   ```bash
   ./build.sh
   build/Menew.app/Contents/MacOS/Menew --snapshot /tmp/shots -language en -notesReading YES
   ```
   Snapshots use fake data (`ClipboardManager.demo()`, `NotesStore.demo()`); never screenshot the user's real clipboard or notes. Add new screens to `Snapshot.swift`.
3. **README.md**: the Features table, Keyboard shortcuts, Privacy and Roadmap sections.
4. **Website** (https://menew.pururucos.com.br), in 5 languages like the app. Layout, the overview page (`/`), the `/vs` comparisons, shared strings, SEO and the deploy live in [Quost/menew-site](https://github.com/Quost/menew-site); this repo owns only the **`/mac` page content**:
   - `site/content.json`: the `/mac` texts in `en`, `pt`, `de`, `es`, `zh` (same keys in every language; a little inline HTML like `<b>`, `<code>`, `<span class="grad">` is allowed). The format is the content contract described in menew-site's README.
   - The screenshots in `docs/assets/` (English) and `docs/assets/<lang>/` (regenerate with `-language pt|de|es|zh`). `content.json` points there (`"assets": "../docs/assets"`), so the README and the site share one copy. The overview page shows these screenshots too, from `/assets/…`.
   - CI (job "Website content") checks `site/` with menew-site's validator: `python3 ../menew-site/scripts/content.py mac site` locally. Preview the real pages from a menew-site checkout: `python3 scripts/build.py --content mac=../menew/site --serve`.
   - Once merged, menew-site picks the change up by itself within about 30 minutes (it polls this repo; no token or workflow here). Versions and download links come from this repo's GitHub Releases at build time: nothing to update for a release.
   - The overview texts (features, highlights, FAQ, "one app instead of many", comparisons) and the link-preview images are in menew-site (`site/i18n/<lang>.json`, `static/assets/og/`, `swift scripts/make-og.swift` there). When a feature visible on the overview changes, open a pull request there too. Never add site templates, generated pages, `firebase.json` or deploy workflows back to this repo.
5. **CHANGELOG.md**: add a `## X.Y.Z` section *before* tagging. It becomes the release notes in the in-app update window and on GitHub. Write it for users, in English.

## Commits

- [Conventional Commits](https://www.conventionalcommits.org), in English, enforced by commitlint (`commitlint.config.mjs`). Examples: `feat(notes): …`, `fix(clipboard): …`, `docs: …`, `ci(release): …`.
- Commits are signed with the maintainer's SSH key. If `git commit` hangs, the key isn't loaded: ask the user to run `ssh-add --apple-use-keychain ~/.ssh/id_ed25519`. Never disable signing.
- Never force-push or rewrite history without explicit approval.

## Releasing

1. Update `CHANGELOG.md` (and the items above), commit, push.
2. `git tag -a vX.Y.Z -m "Menew X.Y.Z" && git push origin vX.Y.Z`
3. The `Release` workflow builds, signs, notarizes, publishes the `.dmg`/`.zip`/`appcast.xml` and bumps `Casks/menew.rb`. Check it finished green.

### Where workflows run

Two repo variables (Settings › Secrets and variables › Actions › Variables) pick the runner; empty means GitHub's machines:

- `RELEASE_RUNNER`: the `Release` workflow. Releases need Xcode 27, which the `macos-26` image lacks, so it is set to `["self-hosted","macOS","menew-release"]`, the maintainer's Mac.
- `CI_RUNNER`: every other workflow (CI, Commits, CodeQL). Set it to the same value to move them all to the Mac (for example, when GitHub Actions minutes are blocked). PRs from forks always stay on GitHub's machines.
- `SELF_HOSTED_AUTHORS`: comma-separated GitHub logins allowed on the Mac, set to `Quost`. A job goes to the Mac only if whoever triggered it (and, on a PR, the PR's author) is in the list; anyone else runs on GitHub's machines. Empty allows anyone in the repo (forks never).

```bash
gh variable set CI_RUNNER --body '["self-hosted","macOS","menew-release"]'   # to the Mac
gh variable delete CI_RUNNER                                                # back to GitHub
```

The runner lives in `~/actions-runner-menew` and is not a service: start it with `~/actions-runner-menew/run.sh` when a job should run on the Mac. The other `~/actions-runner*` folders belong to other projects; don't touch them.

## Don'ts

- No telemetry or analytics in the app, ever (the README and site promise this). The website (Quost/menew-site) only uses GoatCounter (cookieless; clicks tagged with `data-goatcounter-click`); never add cookies or another tracker. Network calls are limited to the update check, the public-IP lookup, the user-started speed test, the currency rate fetched when the user presses ↩ on a conversion in the command palette, and the opt-in Claude plan limits (`api.anthropic.com/api/oauth/usage`, off by default). Ollama/LM Studio are read on `127.0.0.1` only. The optional MCP-over-HTTP server (for agents in Docker) listens on `127.0.0.1` only, needs its key, and is off by default; never bind it to other interfaces.
- Don't add third-party dependencies without a strong reason (only Sparkle today).
- Don't use the WEG certificates in the keychain; the project uses the personal Developer ID (team `9527N6XKKW`).
- Cleaner: user files go to the Trash, only caches/logs are deleted, and `com.apple.*` caches are skipped.
