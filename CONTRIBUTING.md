# Contributing to Lingo

Thanks for your interest! Lingo is a small, native macOS app in plain Swift.

## Build

```bash
make          # build + install to ~/Applications
make run      # build, install, and launch
make clean    # remove build artifacts
```

Requirements: macOS 15+ and the Swift toolchain (Xcode Command Line Tools). No Xcode project — it's SwiftPM.

## Project layout

See the Architecture section in the [README](README.md). In short: one SwiftPM executable target under `Sources/Lingo/`, assembled into `Lingo.app` by `scripts/build.sh`.

## Guidelines

- Keep it native and dependency-free (Apple frameworks only).
- Match the existing style: small files by concern, minimal comments, English throughout.
- UI changes: test in both Light and Dark mode.
- Don't add analytics, telemetry, or anything that sends data off the machine beyond the user-selected AI CLI.

## Adding an AI provider

Implement `AIProvider` in `Providers.swift` (`translate` + `ask`), then add it to `Providers.all`. Providers shell out to a locally installed CLI and must never store credentials.

## Submitting changes

1. Fork and branch.
2. Make focused commits.
3. Ensure `make` builds cleanly.
4. Open a PR describing the change and how you tested it.
