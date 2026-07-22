import SwiftUI
import AVFoundation
import ApplicationServices

struct ExplainTurn: Identifiable {
    let id = UUID()
    let isUser: Bool
    var text: String
}

final class TranslatorModel: ObservableObject {
    @Published var source = ""
    @Published var target = ""
    @Published var sourceCode = Prefs.sourceCode
    @Published var targetCode = Prefs.targetCode
    @Published var providerID = Prefs.providerID
    @Published var busy = false
    @Published var engineLabel = ""
    @Published var note = ""
    @Published var detectedCode = ""
    @Published var loginProvider: AIProvider?
    @Published var showingSettings = false { didSet { adjustForSettings() } }
    @Published var showingOnboarding = false
    @Published var stale = false
    private var savedFrame: NSRect?
    @Published var showExplain = false
    @Published var explainTurns: [ExplainTurn] = []
    @Published var explainInput = ""
    @Published var explainBusy = false
    private var explainContext = ""
    private var explainBuffer = ""
    private var explainTimer: Timer?
    @Published var history: [HistoryItem] = HistoryStore.load()
    @Published var themeID = Prefs.themeID
    @Published var engineMode = Prefs.engineMode
    @Published var toneID = Prefs.tone
    @Published var contextID = Prefs.contextID
    @Published var tones = ModifierStore.load(.tone)
    @Published var contexts = ModifierStore.load(.context)

    var directives: String {
        [ModifierStore.directive(.tone, id: toneID), ModifierStore.directive(.context, id: contextID)]
            .filter { !$0.isEmpty }.joined(separator: " ")
    }

    func reloadModifiers() {
        tones = ModifierStore.load(.tone)
        contexts = ModifierStore.load(.context)
        // The selected item may have been deleted in the editor — fall back cleanly.
        if !tones.contains(where: { $0.id == toneID }) {
            toneID = tones.first?.id ?? "default"; Prefs.tone = toneID
        }
        if !contexts.contains(where: { $0.id == contextID }) {
            contextID = contexts.first?.id ?? "none"; Prefs.contextID = contextID
        }
    }

    var accent: Color { Themes.theme(id: themeID).color }
    func setTheme(_ id: String) { themeID = id; Prefs.themeID = id }

    func setFloatOnTop(_ on: Bool) {
        Prefs.floatOnTop = on
        window?.level = on ? .floating : .normal
    }

    let offline = OfflineTranslator()
    weak var window: NSWindow?

    private var debounce: Timer?
    private var streamBuffer = ""
    private var streamTimer: Timer?
    private var slowTimer: Timer?
    // Last active use — gates the idle auto-install of downloaded updates.
    private(set) var lastActivity = Date()
    func touch() { lastActivity = Date() }
    private var aiGeneration = 0
    private var popupGeneration = 0
    private let speech = AVSpeechSynthesizer()

    var provider: AIProvider { Providers.provider(id: providerID) }

    // Whether the current AI provider is actually usable (installed + signed
    // in) — AI-only entry points fade out instead of failing on click.
    var aiReady: Bool {
        provider.isInstalled && (Prefs.providerOK(provider.id) || provider.isSignedIn)
    }


    func present() {
        // Any action that brings the translator forward supersedes the guide.
        dismissOnboarding()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    // grabSelection's ⌘C fallback polls the clipboard for up to 600 ms — off
    // the main thread so hotkeys never freeze the UI.
    private func grabInBackground(_ completion: @escaping (String) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let selection = grabSelection()
            DispatchQueue.main.async { completion(selection) }
        }
    }

    func startFromSelection() {
        grabInBackground { [weak self] selection in
            guard let self else { return }
            self.clear()
            self.present()
            guard !selection.isEmpty else {
                self.note = "Select text first, then press \(HotKeyAction.translate.combo) (or type above)."
                return
            }
            self.source = selection
            self.translate(record: true)
            if !AXIsProcessTrusted() {
                self.note = "Translated your clipboard — grant Accessibility in Settings so Lingo can grab the selection itself."
            }
        }
    }

    func translate(record: Bool = false) {
        touch()
        if engineMode == "ai" { translateAI(record: record) } else { translateOffline(record: record) }
    }

    func translateScreenshot() {
        guard OCR.ensureScreenPermission() else {
            present()
            note = "Screen Recording permission needed. In System Settings → Privacy & Security → Screen & System Audio Recording: if Lingo isn't listed, click + and add Lingo from Applications. Turn it on (macOS relaunches Lingo), then press \(HotKeyAction.screenshot.combo) again."
            return
        }
        OCR.captureAndRecognize { [weak self] text in
            guard let self else { return }
            self.present()
            if let text, !text.isEmpty { self.source = text; self.translate(record: true) }
            else { self.note = "No text found in the capture." }
        }
    }

    func translateDocument(url: URL) {
        present()
        note = "Translating \(url.lastPathComponent) with Claude…"; busy = true
        DocumentTranslator.translate(fileURL: url, targetName: Languages.name(for: targetCode), directives: directives) { [weak self] outputPath in
            guard let self else { return }
            self.busy = false
            if let outputPath {
                self.note = "Saved: \((outputPath as NSString).lastPathComponent)"
                NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: outputPath)])
            } else {
                self.note = "Document translation failed. Make sure Claude is installed and signed in."
            }
        }
    }

    // Last press wins for NEW content; identical retriggers keep the run
    // already in flight (see the in-flight-text guards). Generations make
    // stale completions exit silently.
    private var replaceGeneration = 0
    private var popupInFlightText: String?
    private var replaceInFlightText: String?

    func quickTranslatePopup() {
        // Anchor to the selection's real on-screen position; the mouse pointer
        // is only the fallback (keyboard selections can be far from it).
        let point = selectionAnchorPoint() ?? NSEvent.mouseLocation
        grabInBackground { [weak self] selection in
            self?.continuePopup(selection: selection, at: point)
        }
    }

    private func continuePopup(selection: String, at point: NSPoint) {
        guard !selection.isEmpty else {
            QuickPopup.shared.show(text: "No text detected. Select text (grant Accessibility in Settings for auto-grab, or press ⌘C first).", at: point)
            return
        }
        if popupInFlightText == selection { return }   // same request already running — don't reset it
        popupGeneration += 1
        let gen = popupGeneration
        popupInFlightText = selection
        QuickPopup.shared.show(text: "Translating…", at: point)
        let src = sourceCode == "auto" ? Languages.detect(selection) : sourceCode
        if src == targetCode { popupInFlightText = nil; QuickPopup.shared.update(text: selection); return }
        // The popup follows the default engine like every other hotkey — it
        // used to force offline-first, silently ignoring the user's AI choice.
        if engineMode == "ai" {
            var streamed = ""
            provider.translate(text: selection, sourceName: nil,   // AI auto-detects
                               targetName: Languages.name(for: targetCode), directives: directives,
                onDelta: { [weak self] piece in
                    guard let self, self.popupGeneration == gen else { return }
                    streamed += piece
                    QuickPopup.shared.update(text: streamed)
                },
                onDone: { [weak self] outcome in
                    guard let self, self.popupGeneration == gen else { return }
                    self.popupInFlightText = nil
                    switch outcome {
                    case .success(let text):
                        Prefs.setProviderOK(self.providerID, true)
                        QuickPopup.shared.update(text: text.isEmpty ? streamed : text)
                    case .needsLogin:
                        Prefs.setProviderOK(self.providerID, false)
                        QuickPopup.shared.update(text: "Sign in to \(self.provider.displayName) in Lingo's Setup to use AI translation.")
                    case .notInstalled:
                        QuickPopup.shared.update(text: "\(self.provider.displayName) CLI is not installed — see Lingo's Setup.")
                    case .failure(let message):
                        QuickPopup.shared.update(text: message)
                    }
                })
        } else {
            offline.translate(selection, source: src, target: targetCode) { [weak self] result in
                guard let self, self.popupGeneration == gen else { return }
                self.popupInFlightText = nil
                if let result, !result.isEmpty {
                    QuickPopup.shared.update(text: result)
                } else {
                    QuickPopup.shared.update(text: "Offline model unavailable — download it in Setup, or switch the default engine to AI.")
                }
            }
        }
    }

    func replaceSelection() {
        let point = selectionAnchorPoint() ?? NSEvent.mouseLocation
        grabInBackground { [weak self] selection in
            self?.continueReplace(selection: selection, at: point)
        }
    }

    // Feedback through the whole lifecycle — the hotkey used to be silent from
    // press to (maybe) replaced text, which read as "nothing happened".
    private func continueReplace(selection: String, at point: NSPoint) {
        guard !selection.isEmpty else {
            NSSound.beep()
            QuickPopup.shared.show(
                text: "Nothing selected — select text first, then press \(HotKeyAction.replace.combo).", at: point)
            QuickPopup.shared.closeSoon(after: 2.5)
            return
        }
        if replaceInFlightText == selection { return }   // same request already running — don't reset it
        replaceGeneration += 1
        let gen = replaceGeneration
        replaceInFlightText = selection
        QuickPopup.shared.show(text: "Translating & replacing…", at: point)
        translateSilently(selection) { [weak self] output in
            guard let self, self.replaceGeneration == gen else { return }   // superseded by a newer press
            self.replaceInFlightText = nil
            guard let output, !output.isEmpty else {
                NSSound.beep()
                QuickPopup.shared.update(
                    text: "Translate & Replace: no translation came back — check the engine in Lingo (AI sign-in, or offline model downloaded).")
                return
            }
            if pasteText(output) {
                QuickPopup.shared.update(text: "✓ Replaced")
                QuickPopup.shared.closeSoon()
            } else {
                QuickPopup.shared.update(
                    text: "Translate & Replace needs the Accessibility permission — grant it in Setup → General (macOS forgets it after an update), then try again.")
            }
        }
    }

    private func translateSilently(_ text: String, completion: @escaping (String?) -> Void) {
        if engineMode == "ai" {
            var full = ""
            provider.translate(text: text, sourceName: nil,   // AI auto-detects
                               targetName: Languages.name(for: targetCode), directives: directives,
                onDelta: { full += $0 },
                onDone: { outcome in
                    if case .success(let result) = outcome {
                        Prefs.setProviderOK(Prefs.providerID, true)
                        completion(result.isEmpty ? full : result)
                    } else {
                        if case .needsLogin = outcome { Prefs.setProviderOK(Prefs.providerID, false) }
                        completion(nil)
                    }
                })
        } else {
            let src = sourceCode == "auto" ? Languages.detect(text) : sourceCode
            guard src != targetCode else { completion(text); return }
            offline.translate(text, source: src, target: targetCode, completion: completion)
        }
    }

    func openEmpty() {
        clear()
        present()
    }

    private var savedGuideFrame: NSRect?

    func startOnboarding() {
        showingSettings = false
        showingOnboarding = true
        // Hotkeys stay live during the guide; only its Shortcuts step pauses
        // them (OnboardingView toggles setPaused per step).
        if let window {
            if savedGuideFrame == nil { savedGuideFrame = window.frame }
            var frame = window.frame
            let size = NSSize(width: 600, height: 660)   // matches OnboardingView's fixed frame
            frame.origin.y += frame.height - size.height
            frame.size = size
            window.setFrame(frame, display: true)
        }
        window?.makeKeyAndOrderFront(nil)   // not present() — it dismisses the guide
        NSApp.activate(ignoringOtherApps: true)
    }

    // Quiet dismissal: marks the guide done and re-arms hotkeys WITHOUT
    // presenting, so translation actions keep their grab-before-present order.
    func dismissOnboarding() {
        guard showingOnboarding else { return }
        showingOnboarding = false
        Prefs.onboardingDone = true
        Prefs.onboardingStep = 0   // a later reopen starts from the top
        HotKeyManager.shared.setPaused(false)
        if let saved = savedGuideFrame {
            window?.setFrame(saved, display: true, animate: true)
            savedGuideFrame = nil
        }
    }

    func finishOnboarding() {
        dismissOnboarding()
        openEmpty()
    }


    // Language detection (NaturalLanguage) is memoized per source string —
    // multiple call sites used to re-detect the same text on every access.
    private var detectionCache: (text: String, code: String)?
    var resolvedSource: String {
        guard sourceCode == "auto" else { return sourceCode }
        if let cached = detectionCache, cached.text == source { return cached.code }
        let code = Languages.detect(source)
        detectionCache = (source, code)
        return code
    }

    private var hasText: Bool { !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    func sourceEdited() {
        if !hasText {
            target = ""; engineLabel = ""; note = ""; stale = false
            debounce?.invalidate()
        } else if engineMode == "offline" {
            // Offline is free and on-device — translate live as the user types.
            stale = false
            debounce?.invalidate()
            debounce = Timer.scheduledTimer(withTimeInterval: 0.35, repeats: false) { [weak self] _ in
                self?.translateOffline()
            }
        } else {
            stale = true   // AI costs tokens — wait for an explicit ⌘↩
        }
    }

    func settingsChanged() {
        Prefs.sourceCode = sourceCode
        Prefs.targetCode = targetCode
        Prefs.providerID = providerID
        Prefs.engineMode = engineMode
        Prefs.tone = toneID; Prefs.contextID = contextID
        guard hasText else { stale = false; return }
        if engineMode == "offline" {
            translateOffline()   // free: language/engine changes retranslate instantly
        } else {
            stale = true         // AI: explicit trigger only
        }
    }

    func swap() {
        // AI mode is target-only: swapping makes the detected source the new
        // target and detection stays automatic.
        if engineMode == "ai" {
            let newTarget = resolvedSource
            sourceCode = "auto"
            if newTarget != targetCode { targetCode = newTarget }
            if !target.isEmpty { source = target; target = "" }
            settingsChanged()
            return
        }
        if sourceCode == "auto" { sourceCode = resolvedSource }
        (sourceCode, targetCode) = (targetCode, sourceCode)
        if !target.isEmpty { source = target; target = "" }
        settingsChanged()
    }


    func translateOffline(record: Bool = false) {
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { target = ""; engineLabel = ""; note = ""; return }
        // Cancel any in-flight AI stream so it can't interleave with this result.
        cancelAIStream()
        let src = resolvedSource
        guard src != targetCode else {
            target = text; engineLabel = ""; note = ""; busy = false; return
        }
        detectedCode = sourceCode == "auto" ? src : ""
        busy = true; note = ""; loginProvider = nil
        offline.translate(text, source: src, target: targetCode) { [weak self] result in
            guard let self else { return }
            self.busy = false
            if let output = result, !output.isEmpty {
                self.target = output
                self.engineLabel = "Offline"
                self.stale = false
                if Prefs.autoCopy { self.copyTarget() }
                if record { self.record(text, output) }
            } else {
                self.note = "Offline model unavailable (not downloaded, or timed out). Try “AI Translate”."
            }
        }
    }

    private func cancelAIStream() {
        aiGeneration += 1
        streamTimer?.invalidate(); streamTimer = nil
        slowTimer?.invalidate(); slowTimer = nil
        streamBuffer = ""
        AITask.cancel("translate")
    }


    // Manual stop for the window's in-flight AI run.
    func cancelTranslation() {
        cancelAIStream()
        busy = false
        engineLabel = ""
        note = ""
    }

    private var aiInFlightText = ""

    func translateAI(record: Bool = false) {
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        // Identical retrigger keeps the in-flight run — killing and respawning
        // the CLI on every press reset the cold-start clock and read as a hang.
        if busy, text == aiInFlightText { return }
        aiInFlightText = text
        cancelAIStream()   // different request: last press wins
        let src = resolvedSource
        guard src != targetCode else {
            target = text; engineLabel = ""; note = ""; stale = false; return
        }
        busy = true; note = ""; target = ""; engineLabel = provider.displayName; loginProvider = nil; stale = false
        detectedCode = src   // AI header shows "from X" feedback

        aiGeneration += 1
        let gen = aiGeneration
        streamBuffer = ""
        streamTimer?.invalidate()
        streamTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            guard let self, !self.streamBuffer.isEmpty else { return }
            if self.target.isEmpty { self.note = "" }   // first token clears the slow-response hint
            self.target += self.streamBuffer
            self.streamBuffer = ""
        }
        // Distinguish "slow" from "broken": say so if no token arrives promptly.
        slowTimer?.invalidate()
        slowTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: false) { [weak self] _ in
            guard let self, self.busy, self.aiGeneration == gen,
                  self.target.isEmpty, self.streamBuffer.isEmpty else { return }
            self.note = "\(self.provider.displayName) is slow to respond (busy or usage limit) — still waiting…"
        }

        // AI always auto-detects the source (the AI header is target-only).
        provider.translate(text: text, sourceName: nil, targetName: Languages.name(for: targetCode), directives: directives,
            onDelta: { [weak self] piece in
                guard let self, self.aiGeneration == gen else { return }
                self.streamBuffer += piece
            },
            onDone: { [weak self] outcome in
                guard let self, self.aiGeneration == gen else { return }
                self.streamTimer?.invalidate(); self.streamTimer = nil
                if !self.streamBuffer.isEmpty { self.target += self.streamBuffer; self.streamBuffer = "" }
                self.busy = false
                switch outcome {
                case .success(let result):
                    Prefs.setProviderOK(self.providerID, true)
                    if !result.isEmpty { self.target = result }
                    if Prefs.autoCopy { self.copyTarget() }
                    if record { self.record(text, self.target) }
                case .needsLogin:
                    Prefs.setProviderOK(self.providerID, false)
                    self.target = ""; self.engineLabel = ""; self.loginProvider = self.provider
                    self.note = "\(self.provider.displayName) needs sign-in."
                case .notInstalled:
                    self.target = ""; self.engineLabel = ""; self.note = "\(self.provider.displayName) CLI is not installed. See Setup."
                case .failure(let message):
                    self.engineLabel = ""
                    self.note = message
                }
            })
    }


    func copyTarget() {
        guard !target.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(target, forType: .string)
    }

    func clear() { source = ""; target = ""; note = ""; engineLabel = ""; detectedCode = ""; stale = false }

    private var explainSystem: String {
        Prefs.explainPrompt
            .replacingOccurrences(of: "{target}", with: Languages.name(for: targetCode))
            .replacingOccurrences(of: "{source}", with: Languages.name(for: resolvedSource))
    }

    func startExplainFromSelection() {
        grabInBackground { [weak self] selection in
            guard let self else { return }
            self.present()
            if !selection.isEmpty { self.source = selection }
            guard self.hasText else {
                self.note = "Select text first, then press \(HotKeyAction.explain.combo)."
                return
            }
            self.explain()
        }
    }

    func explain() {
        let text = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !explainBusy else { return }
        if !showExplain { widenWindow(by: 341) }
        showExplain = true
        explainTurns = []
        explainContext = ""
        sendExplain("Explain and teach: \(text)", display: "Explain “\(text)”")
    }

    private func adjustForSettings() {
        guard let window else { return }
        if showingSettings {
            // Re-opening settings while already open must not clobber the saved frame.
            if savedFrame == nil { savedFrame = window.frame }
            var frame = window.frame
            let width: CGFloat = 740
            let height: CGFloat = max(520, min(760, frame.height))
            frame.origin.y += frame.height - height
            frame.size = NSSize(width: width, height: height)
            window.setFrame(frame, display: true, animate: true)
        } else if let saved = savedFrame {
            window.setFrame(saved, display: true, animate: true)
            savedFrame = nil
        }
    }

    private func widenWindow(by delta: CGFloat) {
        guard let window else { return }
        var frame = window.frame
        frame.size.width += delta
        window.setFrame(frame, display: true, animate: true)
    }

    func askExplain() {
        let question = explainInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty, !explainBusy else { return }
        explainInput = ""
        sendExplain(question, display: question)
    }

    func closeExplain() {
        // Closing the panel cancels the in-flight request — otherwise the CLI
        // keeps running (and billing) for an answer nobody will see.
        AITask.cancel("ask")
        explainTimer?.invalidate(); explainTimer = nil
        explainBuffer = ""
        explainBusy = false
        if showExplain { widenWindow(by: -341) }
        showExplain = false
    }

    // Image explains work with any text question; Claude is the only provider
    // that can actually view the file (via its Read tool), so they route there.
    func explainImage(url: URL) {
        guard !explainBusy else { return }
        if !showExplain { widenWindow(by: 341); showExplain = true }
        let question = explainInput.trimmingCharacters(in: .whitespacesAndNewlines)
        explainInput = ""
        let instruction = "First use the Read tool to view the image at \"\(url.path)\". "
            + "Transcribe any text in it, then "
            + (question.isEmpty ? "explain and teach its content." : "answer this question about it: \(question)")
        let display = "🖼 \(url.lastPathComponent)" + (question.isEmpty ? "" : " — \(question)")
        sendExplain(instruction, display: display, imagePath: url.path)
    }

    private func sendExplain(_ instruction: String, display: String, imagePath: String? = nil) {
        explainTurns.append(ExplainTurn(isUser: true, text: display))
        explainTurns.append(ExplainTurn(isUser: false, text: ""))
        let idx = explainTurns.count - 1
        let prompt = explainContext.isEmpty ? instruction : explainContext + "\n\nFollow-up: " + instruction
        explainBusy = true
        explainBuffer = ""
        explainTimer?.invalidate()
        explainTimer = Timer.scheduledTimer(withTimeInterval: 0.06, repeats: true) { [weak self] _ in
            guard let self, !self.explainBuffer.isEmpty, idx < self.explainTurns.count else { return }
            self.explainTurns[idx].text += self.explainBuffer
            self.explainBuffer = ""
        }
        let asker = imagePath == nil ? provider : Providers.provider(id: "claude")
        asker.ask(prompt: prompt, system: explainSystem, imagePath: imagePath,
            onDelta: { [weak self] piece in self?.explainBuffer += piece },
            onDone: { [weak self] outcome in
                guard let self, idx < self.explainTurns.count else { return }
                self.explainTimer?.invalidate(); self.explainTimer = nil
                if !self.explainBuffer.isEmpty { self.explainTurns[idx].text += self.explainBuffer; self.explainBuffer = "" }
                self.explainBusy = false
                switch outcome {
                case .success(let answer):
                    Prefs.setProviderOK(asker.id, true)
                    if !answer.isEmpty { self.explainTurns[idx].text = answer }
                    self.explainContext += (self.explainContext.isEmpty ? "" : "\n") + "Q: \(instruction)\nA: \(self.explainTurns[idx].text)"
                case .needsLogin:
                    Prefs.setProviderOK(asker.id, false)
                    self.explainTurns[idx].text = "Sign in to \(asker.displayName) to use Explain."
                case .notInstalled: self.explainTurns[idx].text = "\(asker.displayName) CLI is not installed."
                case .failure(let message): self.explainTurns[idx].text = message
                }
            })
    }

    func record(_ src: String, _ tgt: String) {
        guard !src.isEmpty, !tgt.isEmpty else { return }
        history.removeAll { $0.source == src }
        history.insert(HistoryItem(source: src, target: tgt, sourceCode: resolvedSource, targetCode: targetCode), at: 0)
        if history.count > 20 { history = Array(history.prefix(20)) }
        HistoryStore.save(history)
    }

    func restore(_ item: HistoryItem) {
        source = item.source; target = item.target
        sourceCode = item.sourceCode; targetCode = item.targetCode
        engineLabel = ""; note = ""; loginProvider = nil
    }

    func clearHistory() { history = []; HistoryStore.save([]) }

    func speakSource() { speak(source, code: resolvedSource) }
    func speakTarget() { speak(target, code: targetCode) }

    private func speak(_ text: String, code: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        speech.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: trimmed)
        utterance.voice = AVSpeechSynthesisVoice(language: Languages.voice(for: code))
        speech.speak(utterance)
    }
}
