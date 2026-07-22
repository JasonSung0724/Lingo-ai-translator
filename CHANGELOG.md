# Changelog

## 0.1.23

- Document translation hardened against prompt injection: the AI's tools are now scoped to exactly the input file (read) and the output file (write) — verified that any other path is denied. No more blanket edit permission or writable working directory, the prompt explicitly treats file contents as data, and success now requires a non-empty output file
- Explain answers stream as plain text and render Markdown once complete — re-parsing the whole answer every 0.06 s made long answers stutter
- Language auto-detection results are cached per text instead of re-running on every access

## 0.1.22

- Offline mode is now fully live: it translates as you type (0.35 s debounce) and re-translates instantly when you change languages — no button, no Enter. The bottom "Translate" button is gone
- AI mode keeps the deliberate trigger (⌘↩ / AI Translate) since it costs tokens: typing or changing languages just marks the result as stale (orange dot) until you fire it
- The AI-only pickers (tone / context / provider) now hide in Offline mode, so each mode shows only what applies

## 0.1.21

- Fixed: silent updates never actually installed on a menu-bar app that's never quit — downloaded updates now install themselves (and relaunch) automatically once you've been idle for a while, so new versions really do arrive
- Retriggering the SAME text no longer kills and restarts the in-flight translation (which reset the CLI cold-start clock on every press and felt like a hang); a different text still cancels and takes over immediately

## 0.1.20

- Translate & Replace (⇧⌘R) now gives feedback through its whole lifecycle: a small popup at the selection shows "Translating & replacing…" the moment the hotkey fires, flashes "✓ Replaced" on success (auto-dismisses), and states the reason on failure (nothing selected / engine problem / missing permission) — no more guessing whether the hotkey even triggered

## 0.1.19

- The engine switcher is now a clean pill menu ("✨ AI" / "🖥 Offline") aligned with the rest of the header, replacing the lopsided caption + segmented control; the menu spells out what each engine means

## 0.1.18

- Redesigned header per engine. AI mode now only asks "Translate to [language]" — the source is always auto-detected by the AI (a subtle "from English ⇄" chip shows what was detected; click it or press ⌘S to translate the other way). Offline mode keeps the classic source ⇄ target pickers because the on-device engine needs an explicit source

## 0.1.17

- Quick popup now respects your default engine: AI mode streams the translation into the popup token by token (it used to always run offline first and ignore the AI setting, and never streamed)
- Quick popup position is stable: it anchors just below the actual on-screen selection (via Accessibility) instead of the mouse pointer, and streaming growth keeps the top edge fixed instead of jumping
- The engine toggle is now labeled "Auto-translate engine" so it's clear it sets the default for hotkeys/popup/auto-retranslate, while the two bottom buttons each force their own engine
- AI-only entry points (AI Translate, Explain) are disabled with an explanatory tooltip when no AI CLI is installed and signed in, instead of failing after the click

## 0.1.16

- Fully automatic updates: new versions now download and install silently in the background (applied when Lingo relaunches), instead of asking for a click every release. On by default; turn it off in Setup → General → "Install updates automatically" to go back to ask-first

## 0.1.15

- Fixed "CLI not installed" showing even though the claude/codex CLI works in the terminal: detection now also covers version-manager installs (nvm, volta, pnpm, asdf, mise, MacPorts) and, as a last resort, asks your login shell (`command -v`) with the same PATH your terminal uses. The resolved path is cached and warmed at launch, so nothing slows down

## 0.1.14

- "Sign In" now detects an already-signed-in CLI directly: Claude via an attributes-only Keychain probe (no secret is read, no permission prompt), Codex via its auth file — so a logged-in CLI shows "Signed in ✓" immediately, even before the first translation

## 0.1.13

- Setup → Providers no longer shows a perpetual "Sign In" for a CLI you're already signed in to. Lingo remembers whether each provider actually works (any successful translation or a Verify marks it "Signed in ✓"; a needs-login result clears it) — no extra test calls are spent

## 0.1.12

- ⌘S now swaps the source and target languages (was ⌘⇧S)
- Hotkeys no longer freeze the app: grabbing the selection (up to 600 ms in the ⌘C fallback) runs off the main thread
- Slow vs broken is now distinguishable: if the AI hasn't produced a token after 4 s, the status line says it's slow (busy or usage limit); genuine rate-limit/overload errors get their own message
- Closing the Explain panel cancels its in-flight request instead of letting the CLI run on
- Sparkle auto-updates only run in official releases — from-source builds are no longer overwritten by the update feed
- The onboarding guide pauses hotkeys only on its Shortcuts step, not for the whole guide
- Screenshot OCR narrows recognition to your chosen languages when the source isn't auto-detect (faster)

## 0.1.11

- Explain panel accepts images: click the photo button or drag an image in (screenshot, photo, handwriting) and the AI transcribes and teaches its content — type a question first to ask something specific about the image. Uses Claude's vision via its Read tool; complements the fast on-device OCR of ⇧⌘O for hard cases like handwriting and complex layouts

## 0.1.10

- Permissions finally stick: releases are now signed with a stable self-signed certificate instead of ad-hoc. Ad-hoc code hashes change on every build, so macOS silently dropped the Accessibility / Screen Recording grants after each update — the root cause behind "Translate & Replace stopped working again". After updating to 0.1.10 and re-granting once (remove Lingo from the Accessibility list, add it back), grants survive all future updates
- CI refuses to publish a release whose signature isn't the stable identity, so this can't silently regress

## 0.1.9

- Retriggering a translation now cancels the in-flight one immediately (last press wins) — mashing a hotkey or ⌘↩ no longer queues behind or locks onto the first run; superseded runs finish silently with no error popups
- New stop button next to the progress spinner to cancel the window's AI translation manually

## 0.1.8

- New hotkey: Explain selection (default ⇧⌘E) — select text anywhere and get the teaching/explain panel directly; also in the menu bar
- Every Translate & Replace failure now says why (popup): missing permission, or no translation returned (engine not set up)
- Screen Recording registration is retried on every screenshot attempt (ad-hoc-signed apps can fail to appear in the pane on the first try), and the in-app message explains the manual "+" fallback

## 0.1.7

- Translate & Replace no longer fails silently. The three quiet failure paths are fixed: a missing/lost Accessibility permission now shows a popup explaining what to grant (instead of doing nothing), an app that claims the text write succeeded without applying it is detected by reading the selection back (falling back to ⌘V), and a selection that collapsed while the translation ran falls back to pasting at the caret

## 0.1.6

- Fixed the "AI translation hangs forever" bug: newer Claude Code CLIs read stdin in `-p` mode, and the GUI-inherited stdin never ends — every translation silently waited out the 120 s watchdog. All spawned CLIs now get their stdin closed (`/dev/null`), so responses start immediately
- Mashing the popup / translate-and-replace hotkey no longer kills and respawns the CLI on every press (which stacked cold-start latency into a long apparent freeze and cancelled the main window's translation); extra presses during a run are ignored
- Screenshot OCR: Lingo now properly requests Screen Recording access, so it actually appears in System Settings → Privacy & Security → Screen Recording (a shelled-out capture never registered it); a clear in-app message explains the one-time setup
- Hang-proofing: CLI output is read without blocking, a stuck process gets SIGKILL 3 s after SIGTERM, and plain translations time out after 60 s instead of 120 s
- Spawned CLIs get a proper PATH (homebrew / ~/.local/bin / bun / npm), fixing "CLI installed but never responds" setups

## 0.1.5

- Fixed for real: granting Accessibility mid-session now works instantly, with no restart of any kind. Selection grabbing and Translate & Replace now use the Accessibility API directly (read/write the focused element's selected text) — synthetic ⌘C/⌘V is only a fallback for apps with poor AX support. The AX API honors a grant the moment it lands; only event posting doesn't, which is why every earlier approach still needed a restart
- Removed 0.1.4's self-relaunch — no longer needed
- As a bonus, AX-based grabbing never touches your clipboard at all in most apps
- The guide now explains how to fix a "stuck" permission (toggle ON but not detected): remove Lingo from the Accessibility list and add it again — macOS pins grants to the exact build

## 0.1.4

- Fixed: granting Accessibility mid-session now actually activates selection hotkeys. macOS keeps an already-running process blocked from posting the ⌘C/⌘V events even after the grant, so Lingo now detects that (CGPreflightPostEventAccess) and quietly restarts itself once; the Welcome Guide saves its step and resumes exactly where you were
- Guide copy updated to mention the brief self-restart

## 0.1.3

- Fixed: on a fresh install the Welcome Guide could open as an absurdly tall, squeezed window (the window sized itself to the content's ideal height). The guide now uses a fixed 600×660 window
- Fixed: if 0.1.2 already saved that deformed size, the window resets itself to the normal size on next launch

## 0.1.2

First-run experience release.

- New Welcome Guide on first launch: walks through the Accessibility grant, shows and lets you rebind every hotkey, and helps you install, sign in to, and verify your AI CLI (Claude / Codex) — rerun it any time from the menu bar → Welcome Guide…
- Fixed: granting Accessibility no longer requires an app restart — Lingo watches the permission and re-registers the hotkeys the moment it lands, so "the shortcut is set but nothing happens" on a fresh install is gone
- Permission status now updates live in Settings and the guide (revoking it is detected too)
- Providers step includes a one-click "Verify" that runs a tiny test translation to confirm your CLI sign-in actually works

## 0.1.1

Stability release — fixes from a full pre-launch audit.

- AI translation can no longer hang forever: stderr is drained (pipe-deadlock fix), every CLI call has a timeout, and a newer request cancels the previous one
- Fixed a Codex login-detection bug that discarded valid translations containing words like "login"
- Offline translation's timeout no longer fires stale errors over a newer result; offline and AI results can no longer interleave
- Shortcut recorder: no more "keyboard stops working" after leaving Settings mid-recording; duplicate shortcuts are rejected
- Clipboard protection now preserves images/files/rich text (not just plain text) and adapts to slow apps when grabbing the selection
- After a Sparkle update, Lingo detects the lost Accessibility permission and guides you to re-grant it; running from the DMG now warns that updates need /Applications
- Window position/size is actually remembered across launches
- Prompt edits save automatically; Settings statuses (Accessibility, CLI installed) refresh when you return to the app
- Releases are now universal (Apple Silicon + Intel), published atomically (assets verified before the release goes live), and the installer never deletes your old version before the new one is ready
- Many smaller fixes: OCR errors surface properly, stale document-translation output can't fake success, history survives corrupt data, deleted tones/contexts fall back cleanly

## 0.1.0

First public release.

- Global hotkeys default to ⇧⌘ T/P/O/R/L; menu bar and in-app hints show your actual (rebound) shortcuts

- In-app automatic updates via Sparkle ("Check for Updates…" in the menu bar and app menu)
- Releases include `Lingo.zip` and `Lingo.dmg` (drag-to-Applications install, no terminal needed)
- AI is the default translation engine; "Copy translation automatically" is on by default

- Offline, on-device translation (Apple Translation) for 20+ languages with auto-detect
- AI translation via your own Claude or GPT (Codex) CLI — no API keys
- Global hotkeys: translate selection, quick popup, OCR screenshot, translate & replace, open window
- Tone control and editable/custom Contexts
- Explain / teaching side panel with follow-up chat and Markdown rendering (incl. tables)
- Translation history, text-to-speech, one-click copy
- Color themes, Light/Dark/System, rebindable shortcuts (function keys supported)
- Launch at login; clipboard is preserved during grab/replace
- Single-instance, tabbed Settings with sidebar, custom app icon
