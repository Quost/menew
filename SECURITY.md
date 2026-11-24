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
- The MCP servers (stdio and HTTP) answering without permission, or the HTTP server's key being guessable or reachable from outside `127.0.0.1`.

Menew has no servers and no accounts. The only network calls are:

- the update check;
- the public-IP lookup;
- the speed test you start yourself;
- the currency rate, fetched when you press ↩ on a conversion in the command palette;
- the Claude plan limits (`api.anthropic.com`), only if you turn them on (off by default).

Ollama and LM Studio models are read on `127.0.0.1` only. The optional MCP-over-HTTP server (for agents in Docker) listens on `127.0.0.1` only, answers only requests with its key, and is off by default.
