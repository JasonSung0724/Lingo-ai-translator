# Lingo — macOS Menu-Bar Translator (Offline + AI)

**Lingo** is a fast, native **translation app for macOS** that lives in your menu bar. Select text in **any** app, press a global hotkey, and get an instant translation — **offline and on-device** by default, or one click away from **AI translation** with **Claude** or **GPT**. Think Google Translate / DeepL, but system-wide and private.

![platform](https://img.shields.io/badge/platform-macOS%2015%2B-black?logo=apple)
![swift](https://img.shields.io/badge/Swift-SwiftUI-orange?logo=swift)
![license](https://img.shields.io/badge/license-MIT-blue)
![release](https://img.shields.io/github/v/release/JasonSung0724/Lingo-ai-translator?sort=semver)

**Website:** [jasonsung0724.github.io/Lingo-ai-translator](https://jasonsung0724.github.io/Lingo-ai-translator/)

A free, open-source, private alternative to Google Translate, DeepL, Bob, and Easydict — with offline translation, screenshot OCR, and AI powered by your own Claude/GPT login (no API keys).

> **macOS only.** Lingo is a tiny (~1 MB) native menu-bar app; offline language models are downloaded and managed by macOS, so the app stays small.

## Features

- **20+ languages** with auto-detection, and a **searchable** language picker
- **Offline & instant** by default (Apple on-device Translation) — private, no network
- **Engine toggle** — Offline or AI, per your needs
- **AI translation** via your own **Claude** (`claude`) or **GPT** (OpenAI **Codex**) CLI — no API keys
- **Tone control** and **Contexts** (Formal / Casual / Email / Technical …) — fully editable, add your own
- **Quick popup** (`⇧⌘P`) — select text, get a small translation bubble by the cursor
- **OCR screenshot translation** (`⇧⌘O`) — translate text in images / PDFs / any region
- **Translate & replace in place** (`⇧⌘R`) — swap a selection for its translation
- **Document translation** — drag a file in; Claude translates it to a new file, preserving formatting
- **Explain / teach** — a side panel that explains a word with examples and lets you ask follow-ups (renders Markdown, incl. tables)
- **History**, **Listen** (text-to-speech), one-click **Copy**
- **Color themes** + Light / Dark / System, **rebindable shortcuts** (function keys supported)
- **Launch at login**, and your clipboard is never disturbed
- **100% local** — nothing leaves your Mac except to the AI CLI you choose

## Requirements

| | |
| --- | --- |
| **macOS** | 15 (Sequoia) or later — required by Apple's Translation framework |
| **Chip** | Apple Silicon (prebuilt). Intel Macs can build from source. |
| **AI (optional)** | [Claude Code CLI](https://claude.com/claude-code) (`claude`) and/or [OpenAI Codex CLI](https://github.com/openai/codex) (`codex`), signed in |

Offline translation works with **no** CLI and no account.

## Install (macOS 15+)

**One line** — download the latest release and install it:

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/JasonSung0724/Lingo-ai-translator/main/scripts/install.sh)"
```

It checks you're on macOS 15+, installs `Lingo.app` to `/Applications`, clears the quarantine flag, and launches it. (The installer refuses to run on non-macOS systems.)

**No terminal** — download `Lingo.dmg` from [Releases](https://github.com/JasonSung0724/Lingo-ai-translator/releases/latest), open it, and drag **Lingo** into **Applications**. The app isn't notarized, so the first launch is blocked: open **System Settings → Privacy & Security**, scroll down, and click **Open Anyway**. (Only needed once — the one-line installer above skips this step.)

**Homebrew**:

```bash
brew tap JasonSung0724/tap
brew install --cask --no-quarantine lingo-ai-translator
```

**Updating** — Lingo updates itself automatically in the background (Sparkle); turn silent installs off in Setup → General if you prefer to be asked. You can also trigger a check from the menu bar icon → **Check for Updates…**

**From source**:

```bash
git clone https://github.com/JasonSung0724/Lingo-ai-translator.git
cd Lingo-ai-translator && make        # builds & installs to ~/Applications
```

## Usage

Global hotkeys (work in any app):

| Action | Shortcut |
| --- | --- |
| Translate selection (opens window) | `⇧⌘T` |
| Quick popup translation | `⇧⌘P` |
| Translate a screenshot (OCR) | `⇧⌘O` |
| Translate & replace in place | `⇧⌘R` |
| Open the translator window | `⇧⌘L` |

In the window:

| Action | Shortcut |
| --- | --- |
| AI translate | `⌘↩` |
| Swap languages | `⌘⇧S` |
| Copy translation | `⌘⇧C` |
| Clear | `⌘K` |
| Close window | `⌘W` / `Esc` |

All hotkeys are rebindable in **Settings → Shortcuts**.

## Permissions

- **Accessibility** (optional) lets Lingo grab your selection automatically (so you can skip ⌘C). The first-run guide walks you through granting it, and Lingo detects the grant instantly — no restart needed. You can also grant it later in **Settings → General**, or *System Settings → Privacy & Security → Accessibility*. Without it, copy first, then use the hotkey.

On first launch a short **Welcome Guide** walks through the Accessibility grant, your hotkeys, and AI sign-in (with a one-click "Verify" test). Rerun it any time from the menu bar icon → **Welcome Guide…**

## AI providers

Lingo shells out to a CLI you've installed and signed into — it never stores keys.

| Provider | CLI | Sign in |
| --- | --- | --- |
| Claude | `claude` | run `claude`, then `/login` |
| GPT | `codex` | `codex login` (Sign in with ChatGPT) |

The **Settings → Providers** tab shows status and quick actions.

## Privacy

- Offline translation is fully on-device.
- AI translation sends only the text you translate to the CLI/provider you selected.
- No analytics, no accounts, no data leaves your machine otherwise.

## Architecture

Plain Swift + SwiftUI + AppKit, built with SwiftPM (no Xcode project needed).

```
Sources/Lingo/
  main.swift            Entry point
  AppDelegate.swift     Menu bar, windows, single-instance, Edit menu
  RootView.swift        Translator ⇄ Settings paging
  TranslatorModel.swift Observable state / orchestration
  TranslatorView.swift  Main translator UI
  OnboardingView.swift  Tabbed Settings (sidebar)
  Providers.swift       AIProvider protocol + Claude & Codex
  OfflineTranslator.swift  Apple Translation wrapper
  Selection.swift       Grab selection / paste (clipboard-preserving)
  OCR.swift             Screenshot capture + Vision OCR
  DocumentTranslator.swift  File translation via Claude's file tools
  QuickPopup.swift      Cursor-anchored translation bubble
  MarkdownText.swift    Lightweight Markdown renderer (incl. tables)
  Languages.swift, Theme.swift, Tones/PromptModifier.swift, HotKeys.swift,
  Settings.swift, HistoryStore.swift, LaunchAtLogin.swift, LanguagePicker.swift, ModifierEditor.swift
```

## Contributing

Issues and PRs welcome — see [CONTRIBUTING.md](CONTRIBUTING.md).

## Keywords

macOS translator · menu bar translation app · offline translation Mac · on-device translation · AI translator · Claude translator · GPT / ChatGPT translator · translate selection anywhere · screenshot OCR translation · popup translate · 划词翻译 · 選字翻譯 · 螢幕翻譯 · Google Translate alternative · DeepL alternative · Bob alternative · Easydict alternative · SwiftUI translation app · free open-source translator for Mac.

> **Repo topics** (set these on GitHub for search): `macos`, `translator`, `translation`, `menubar`, `swift`, `swiftui`, `offline`, `ocr`, `claude`, `openai`, `productivity`.

## License

[MIT](LICENSE) © 2026 Jason Sung
