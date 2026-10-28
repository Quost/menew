## What changes

<!-- What this PR does and why. Link the issue if there is one: "Closes #123". -->

## Screenshots

<!-- For visual changes: before and after, light and dark mode if it matters. -->

## Checklist

- [ ] Builds with `./build.sh` and I tried the change in the app.
- [ ] Every new UI string uses `L("…")` and has en, de, es and zh translations in `L10n.swift`.
- [ ] Screenshots regenerated if a screen changed (`--snapshot`, see CONTRIBUTING).
- [ ] README and website (`site/`, then `python3 scripts/build-site.py`) updated if the change is visible to users.
- [ ] `CHANGELOG.md` has a line for users.
- [ ] Commits follow [Conventional Commits](https://www.conventionalcommits.org) (`feat(notes): …`, `fix(clipboard): …`).
- [ ] No telemetry, no new network calls and no new dependencies (or explained above).
