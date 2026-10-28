# Security policy

Menew reads your clipboard, asks for Accessibility permission and can store protected notes in the Keychain, so security reports matter a lot to us.

## Supported versions

Only the latest release gets security fixes. Menew updates itself through Sparkle (and `brew upgrade`), so everyone can be on the newest version within a day.

| Version | Supported |
|---|---|
| Latest release | ✅ |
| Older releases | ❌ |

## Reporting a vulnerability

**Please don't open a public issue.** Report it privately instead:

1. Go to the [Security tab](https://github.com/Quost/menew/security) of this repository.
2. Click **Report a vulnerability** and describe the problem, the steps to reproduce it, and the Menew and macOS versions.

What happens next:

- You'll get a reply within **7 days**.
- Once confirmed, we'll work on a fix and ship it as a new release, usually within 30 days depending on severity.
- We'll credit you in the release notes, unless you'd rather stay anonymous.

## Scope

Good examples of things to report:

- Clipboard content leaving your Mac, or being readable by other users or apps.
- Passwords from password managers ending up in the history even with "Ignore passwords" on.
- Protected notes readable without Touch ID or your password.
- Problems with update signing (Sparkle, Developer ID, notarization).

Menew has no servers and no accounts. The only network calls are the update check, the public-IP lookup and the speed test you start yourself.
