import SwiftUI
import UniformTypeIdentifiers

struct TranslatorView: View {
    @ObservedObject var model: TranslatorModel
    var openSetup: () -> Void
    @State private var copied = false

    var body: some View {
        HStack(spacing: 0) {
            VStack(spacing: 0) {
                languageBar
                Divider()
                sourcePane
                Divider()
                targetPane
                if let provider = model.loginProvider { loginBanner(provider) }
                Divider()
                bottomBar
            }
            .frame(minWidth: 380)
            if model.showExplain {
                Divider()
                explainPanel.frame(width: 340)
            }
        }
        .tint(model.accent)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .background(TranslationDriver(translator: model.offline))
        .onExitCommand { model.window?.orderOut(nil) }
    }

    private var languageBar: some View {
        HStack(spacing: 6) {
            if model.engineMode == "ai" {
                // AI detects the source itself — the header only asks where to.
                Text("Translate to").font(.system(size: 13)).foregroundStyle(.secondary)
                LanguageMenuButton(title: Languages.name(for: model.targetCode), includeAuto: false) { model.targetCode = $0; model.settingsChanged() }
                if !model.detectedCode.isEmpty {
                    Button { model.swap() } label: {
                        HStack(spacing: 4) {
                            Text("from \(Languages.name(for: model.detectedCode))")
                            Image(systemName: "arrow.left.arrow.right").font(.system(size: 9, weight: .semibold))
                        }
                        .font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .help("Source is detected automatically — click to translate the other way (⌘S)")
                }
                Button("") { model.swap() }
                    .keyboardShortcut("s", modifiers: .command).opacity(0).frame(width: 0)
            } else {
                LanguageMenuButton(title: sourceLabel, includeAuto: true) { model.sourceCode = $0; model.settingsChanged() }
                Button { model.swap() } label: {
                    Image(systemName: "arrow.left.arrow.right").font(.system(size: 12, weight: .semibold))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .keyboardShortcut("s", modifiers: .command).help("Swap languages (⌘S)")
                LanguageMenuButton(title: Languages.name(for: model.targetCode), includeAuto: false) { model.targetCode = $0; model.settingsChanged() }
            }
            Spacer()
            engineMenu
            historyMenu
            Button(action: openSetup) { Image(systemName: "gearshape").font(.system(size: 13)) }
                .buttonStyle(.plain).foregroundStyle(.secondary).help("Settings")
            Button("") { model.clear() }
                .keyboardShortcut("k", modifiers: .command).opacity(0).frame(width: 0)
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    // Pill-style engine picker — same visual language as the provider/tone
    // menus, and it sits on the header baseline (the old caption+segmented
    // stack looked lopsided).
    private var engineMenu: some View {
        Menu {
            Button {
                model.engineMode = "offline"; model.settingsChanged()
            } label: {
                Label("Offline — on-device, private", systemImage: model.engineMode == "offline" ? "checkmark" : "desktopcomputer")
            }
            Button {
                model.engineMode = "ai"; model.settingsChanged()
            } label: {
                Label("AI — Claude / GPT quality", systemImage: model.engineMode == "ai" ? "checkmark" : "sparkles")
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: model.engineMode == "ai" ? "sparkles" : "desktopcomputer")
                    .font(.system(size: 10, weight: .semibold))
                Text(model.engineMode == "ai" ? "AI" : "Offline")
                    .font(.system(size: 12, weight: .semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 8, weight: .bold)).opacity(0.5)
            }
            .foregroundStyle(model.engineMode == "ai" ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.quaternary, in: Capsule())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help("Default translation engine — used by hotkeys, the quick popup, and automatic re-translation. The two buttons below each force their own engine for one run.")
    }

    private var historyMenu: some View {
        Menu {
            if model.history.isEmpty {
                Text("No history yet")
            } else {
                ForEach(model.history) { item in
                    Button(String(item.source.prefix(48))) { model.restore(item) }
                }
                Divider()
                Button("Clear History") { model.clearHistory() }
            }
        } label: {
            Image(systemName: "clock.arrow.circlepath").font(.system(size: 13))
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .foregroundStyle(.secondary).help("History")
    }

    private var sourceLabel: String {
        if model.sourceCode != "auto" { return Languages.name(for: model.sourceCode) }
        return model.detectedCode.isEmpty ? "Detect language" : "Detected: \(Languages.name(for: model.detectedCode))"
    }

    private var sourcePane: some View {
        ZStack(alignment: .topLeading) {
            TextEditor(text: $model.source)
                .font(.system(size: 16)).scrollContentBackground(.hidden)
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 30)
                .onChange(of: model.source) { _, _ in model.sourceEdited() }
            if model.source.isEmpty {
                // 19/12 mirrors the TextEditor's 14/12 padding plus NSTextView's 5pt container inset.
                Text("Type or paste text, or select anywhere and press \(HotKeyAction.translate.combo)")
                    .foregroundStyle(.tertiary).font(.system(size: 16))
                    .padding(.horizontal, 19).padding(.top, 12).allowsHitTesting(false)
            }
        }
        .frame(minHeight: 130)
        .onDrop(of: [UTType.fileURL], isTargeted: nil) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: URL.self) { url, _ in
                if let url { DispatchQueue.main.async { model.translateDocument(url: url) } }
            }
            return true
        }
        .overlay(alignment: .topTrailing) {
            if !model.source.isEmpty {
                Button { model.clear() } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                }
                .buttonStyle(.plain).foregroundStyle(.tertiary).help("Clear").padding(10)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if !model.source.isEmpty {
                HStack(spacing: 12) {
                    Text("\(model.source.count)").font(.caption).foregroundStyle(.tertiary)
                    Button { model.speakSource() } label: { Image(systemName: "speaker.wave.2") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Listen")
                }
                .padding(.horizontal, 14).padding(.bottom, 9)
            }
        }
    }

    private var targetPane: some View {
        ScrollView {
            Text(model.target.isEmpty ? (model.busy ? "Translating…" : "Translation") : model.target)
                .font(.system(size: 17))
                .foregroundStyle(model.target.isEmpty ? .tertiary : .primary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 14).padding(.top, 12).padding(.bottom, 34)
        }
        .frame(maxHeight: .infinity).frame(minHeight: 150)
        .background(model.accent.opacity(0.06))
        .overlay(alignment: .bottomLeading) {
            if !model.source.isEmpty {
                Button { model.explain() } label: {
                    Label("Explain", systemImage: "character.book.closed").font(.system(size: 12, weight: .medium))
                }
                .buttonStyle(.bordered).controlSize(.small).padding(10)
                .disabled(!model.aiReady)
                .help(model.aiReady ? "Explain and teach this word/phrase"
                                    : "Explain needs an AI CLI — install and sign in via Setup → Providers")
            }
        }
        .overlay(alignment: .topTrailing) {
            if !model.engineLabel.isEmpty {
                Text(model.engineLabel).font(.caption2.weight(.semibold))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill(Color.primary.opacity(0.08)))
                    .foregroundStyle(.secondary).padding(10)
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if !model.target.isEmpty {
                HStack(spacing: 14) {
                    Button { model.speakTarget() } label: { Image(systemName: "speaker.wave.2") }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Listen")
                    Button {
                        model.copyTarget(); copied = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { copied = false }
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(.plain).foregroundStyle(copied ? .green : .secondary)
                    .keyboardShortcut("c", modifiers: [.command, .shift]).help("Copy translation (⌘⇧C)")
                }
                .font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 14).padding(.bottom, 10)
            }
        }
    }

    private var explainPanel: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Explain", systemImage: "character.book.closed").font(.subheadline.weight(.semibold))
                Spacer()
                if model.explainBusy { ProgressView().controlSize(.small) }
                Button { model.closeExplain() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(model.explainTurns) { turn in explainBubble(turn) }
                        Color.clear.frame(height: 1).id("EB")
                    }
                    .padding(12)
                }
                .onChange(of: model.explainTurns.last?.text) { _, _ in proxy.scrollTo("EB", anchor: .bottom) }
            }
            .frame(maxHeight: .infinity)
            Divider()
            HStack(spacing: 8) {
                Button { pickExplainImage() } label: { Image(systemName: "photo.badge.plus") }
                    .buttonStyle(.plain).foregroundStyle(.secondary)
                    .disabled(model.explainBusy)
                    .help("Explain an image — screenshot, photo, handwriting (uses Claude; type a question first to ask about the image)")
                TextField("Ask a follow-up (e.g. more examples, when to use it)…", text: $model.explainInput)
                    .textFieldStyle(.roundedBorder).onSubmit { model.askExplain() }
                Button("Send") { model.askExplain() }
                    .disabled(model.explainInput.isEmpty || model.explainBusy)
            }
            .padding(10)
        }
        .onDrop(of: [.fileURL], isTargeted: nil) { providers in
            guard let item = providers.first else { return false }
            _ = item.loadObject(ofClass: URL.self) { url, _ in
                guard let url, ["png", "jpg", "jpeg", "heic", "tiff", "gif", "webp", "bmp"]
                    .contains(url.pathExtension.lowercased()) else { return }
                DispatchQueue.main.async { model.explainImage(url: url) }
            }
            return true
        }
    }

    private func pickExplainImage() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.png, .jpeg, .heic, .tiff, .gif, .webP, .bmp, .image]
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        if panel.runModal() == .OK, let url = panel.url { model.explainImage(url: url) }
    }

    private func explainBubble(_ turn: ExplainTurn) -> some View {
        HStack {
            if turn.isUser { Spacer(minLength: 32) }
            Group {
                if turn.isUser {
                    Text(turn.text).font(.system(size: 13)).foregroundStyle(.white)
                } else if model.explainBusy && turn.id == model.explainTurns.last?.id {
                    // Streaming: plain text — re-parsing the whole Markdown
                    // every 0.06 s tick made long answers stutter.
                    Text(turn.text.isEmpty ? "…" : turn.text)
                        .font(.system(size: 13)).foregroundStyle(.primary)
                } else {
                    MarkdownText(text: turn.text.isEmpty ? "…" : turn.text).foregroundStyle(.primary)
                }
            }
            .textSelection(.enabled)
            .padding(.horizontal, 11).padding(.vertical, 8)
            .background(turn.isUser ? model.accent : Color.primary.opacity(0.07),
                        in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            if !turn.isUser { Spacer(minLength: 20) }
        }
    }

    private func loginBanner(_ provider: AIProvider) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.exclamationmark").foregroundStyle(.orange)
            Text("Sign in to \(provider.displayName) to use AI translation").font(.callout)
            Spacer()
            Button("Sign In") { runInTerminal(provider.loginCommand) }
                .buttonStyle(.borderedProminent).controlSize(.small)
        }
        .padding(.horizontal, 14).padding(.vertical, 9)
        .background(Color.orange.opacity(0.12))
    }

    private var bottomBar: some View {
        HStack(spacing: 10) {
            if !model.note.isEmpty {
                Text(model.note).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if model.busy {
                ProgressView().controlSize(.small)
                Button { model.cancelTranslation() } label: {
                    Image(systemName: "stop.circle.fill").font(.system(size: 15))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Stop this translation")
            }
            if model.engineMode == "ai" {
                contextMenu
                toneMenu
                providerMenu
            }
            if model.stale {
                Circle().fill(.orange).frame(width: 7, height: 7)
                    .help("Changes not translated yet — press AI Translate (⌘↩)")
            }
            Button { model.translateAI(record: true) } label: {
                HStack(spacing: 6) {
                    Text("AI Translate").fontWeight(.semibold)
                    Text("⌘↩").font(.caption).opacity(0.75)
                }
                .padding(.horizontal, 4)
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .keyboardShortcut(.return, modifiers: .command)
            .disabled(model.source.isEmpty || model.busy || !model.aiReady)
            .help(model.aiReady ? "AI Translate (⌘↩)"
                                : "\(model.provider.displayName) isn't ready — install and sign in via Setup → Providers")
        }
        .padding(.horizontal, 14).padding(.vertical, 11)
    }

    private var toneMenu: some View {
        modifierMenu(items: model.tones, selected: model.toneID, fallback: "Tone") { id in
            model.toneID = id; model.settingsChanged()
        }
    }

    private var contextMenu: some View {
        modifierMenu(items: model.contexts, selected: model.contextID, fallback: "Context") { id in
            model.contextID = id; model.settingsChanged()
        }
    }

    private func modifierMenu(items: [PromptModifier], selected: String, fallback: String,
                              pick: @escaping (String) -> Void) -> some View {
        let name = items.first { $0.id == selected }?.name ?? fallback
        return Menu {
            ForEach(items) { item in Button(item.name) { pick(item.id) } }
            Divider()
            Button("Customize…") { model.showingSettings = true }
        } label: {
            HStack(spacing: 5) {
                Text(name).font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.5)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.quaternary, in: Capsule())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().help("AI only")
    }

    private var providerMenu: some View {
        Menu {
            ForEach(Providers.all, id: \.id) { provider in
                Button(provider.displayName) { model.providerID = provider.id; model.settingsChanged() }
            }
        } label: {
            HStack(spacing: 5) {
                Text(model.provider.displayName).font(.system(size: 12, weight: .medium))
                Image(systemName: "chevron.up.chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.5)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(.quaternary, in: Capsule())
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
    }
}

func runInTerminal(_ command: String) {
    let script = """
    tell application "Terminal"
        activate
        do script "\(command.replacingOccurrences(of: "\"", with: "\\\""))"
    end tell
    """
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
    process.arguments = ["-e", script]
    try? process.run()
}
