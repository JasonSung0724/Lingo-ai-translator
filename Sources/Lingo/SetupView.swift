import SwiftUI
import ApplicationServices

enum SettingsTab: String, CaseIterable, Identifiable {
    case general = "General"
    case shortcuts = "Shortcuts"
    case providers = "Providers"
    case prompts = "Prompts"
    case customize = "Tones & Contexts"
    var id: String { rawValue }

    var icon: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        case .providers: return "sparkles"
        case .prompts: return "text.alignleft"
        case .customize: return "slider.horizontal.3"
        }
    }
}

struct SetupView: View {
    @ObservedObject var model: TranslatorModel
    var onClose: () -> Void

    @State private var tab: SettingsTab = .general
    @State private var prompt = Prefs.systemPrompt
    @State private var explainPrompt = Prefs.explainPrompt
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var autoCopy = Prefs.autoCopy
    @State private var autoUpdate = Prefs.autoUpdate
    @State private var floatOnTop = Prefs.floatOnTop
    @State private var appearance = Prefs.appearance
    @ObservedObject private var ax = AXWatcher.shared
    @State private var installed: [String: Bool] = [:]

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(spacing: 0) {
                HStack {
                    Text(tab.rawValue).font(.headline)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 4)
                Form { tabContent }.formStyle(.grouped)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 700, minHeight: 500)
        .tint(model.accent)
        .onAppear(perform: refresh)
        // Returning from System Settings / a terminal re-activates the app —
        // refresh so "Grant Accessibility" and CLI install states update live.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            refresh()
        }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            Button { onClose() } label: {
                Label("Translator", systemImage: "chevron.left")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
            }
            .buttonStyle(.plain).keyboardShortcut(.cancelAction)
            .padding(.horizontal, 10).padding(.top, 12).padding(.bottom, 10)

            ForEach(SettingsTab.allCases) { item in
                Button { tab = item } label: {
                    Label(item.rawValue, systemImage: item.icon)
                        .font(.system(size: 13, weight: tab == item ? .semibold : .regular))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .background(tab == item ? AnyShapeStyle(.tint.opacity(0.15)) : AnyShapeStyle(.clear),
                                    in: RoundedRectangle(cornerRadius: 7))
                        .foregroundStyle(tab == item ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
        .padding(.horizontal, 8)
        .frame(width: 190)
        .background(Color.primary.opacity(0.03))
    }

    @ViewBuilder
    private var tabContent: some View {
        switch tab {
        case .general:
            appearanceSection
            behaviorSection
        case .shortcuts:
            shortcutsSection
        case .providers:
            providersSection
        case .prompts:
            promptSection
            explainPromptSection
        case .customize:
            ModifierEditor(kind: .tone, title: "Tones", onChange: { model.reloadModifiers() })
            ModifierEditor(kind: .context, title: "Contexts", onChange: { model.reloadModifiers() })
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            HStack(spacing: 10) {
                ForEach(Themes.all) { theme in
                    Circle().fill(theme.color).frame(width: 20, height: 20)
                        .overlay(Circle().strokeBorder(.primary, lineWidth: model.themeID == theme.id ? 2 : 0))
                        .onTapGesture { model.setTheme(theme.id) }
                        .help(theme.name)
                }
            }
            Picker("Mode", selection: $appearance) {
                Text("System").tag("system"); Text("Light").tag("light"); Text("Dark").tag("dark")
            }
            .pickerStyle(.segmented)
            .onChange(of: appearance) { _, value in Prefs.appearance = value; Appearance.apply(value) }
        }
    }

    private var behaviorSection: some View {
        Section("Behavior") {
            Toggle("Launch Lingo at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, value in
                    if !LaunchAtLogin.set(value) { launchAtLogin = LaunchAtLogin.isEnabled }  // revert on failure
                }
            Toggle("Copy translation automatically", isOn: $autoCopy)
                .onChange(of: autoCopy) { _, value in Prefs.autoCopy = value }
            if AppDelegate.isOfficialBuild {
                Toggle("Install updates automatically", isOn: $autoUpdate)
                    .onChange(of: autoUpdate) { _, value in
                        Prefs.autoUpdate = value
                        AppDelegate.shared?.setAutoUpdate(value)
                    }
            }
            Toggle("Keep window on top", isOn: $floatOnTop)
                .onChange(of: floatOnTop) { _, value in model.setFloatOnTop(value) }
            LabeledContent("Auto-copy selection") {
                if ax.trusted { Label("Enabled", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
                else { Button("Grant Accessibility") { requestAccessibility() } }
            }
        }
    }

    private var shortcutsSection: some View {
        Section("Keyboard shortcuts") {
            ForEach(HotKeyAction.allCases) { action in KeyRecorder(action: action) }
            Text("Click a shortcut, press a new combination (with a modifier). Esc cancels.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var providersSection: some View {
        Section("AI providers") {
            ForEach(Providers.all, id: \.id) { provider in
                LabeledContent(provider.displayName) {
                    if installed[provider.id] != true {
                        ProviderInstallButton(provider: provider)
                    } else if Prefs.providerOK(provider.id) || provider.isSignedIn {
                        Label("Signed in", systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                    } else {
                        Button("Sign In") { runInTerminal(provider.loginCommand) }
                    }
                }
            }
            Text("Offline translation needs no provider. Language models download on first use.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var promptSection: some View {
        Section("Translation prompt") {
            TextEditor(text: $prompt).font(.system(size: 12, design: .monospaced)).frame(height: 130)
                .onChange(of: prompt) { _, value in Prefs.systemPrompt = value }
            HStack {
                Button("Reset") { prompt = Prefs.defaultSystemPrompt; Prefs.systemPrompt = prompt }
                Spacer()
                Text("Saved automatically").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var explainPromptSection: some View {
        Section("Explain / teaching prompt") {
            TextEditor(text: $explainPrompt).font(.system(size: 12, design: .monospaced)).frame(height: 130)
                .onChange(of: explainPrompt) { _, value in Prefs.explainPrompt = value }
            Text("Use {source} and {target} as placeholders for the languages.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Reset") { explainPrompt = Prefs.defaultExplainPrompt; Prefs.explainPrompt = explainPrompt }
                Spacer()
                Text("Saved automatically").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func refresh() {
        Providers.detectInstalled { installed = $0 }
    }
}

// "Get…" / "Copy install command" for a CLI that isn't installed yet — shared
// by Setup and the onboarding guide.
struct ProviderInstallButton: View {
    let provider: AIProvider
    @State private var copied = false

    var body: some View {
        if let url = provider.installURL {
            Button("Get…") { NSWorkspace.shared.open(url) }
                .help("Opens \(url.absoluteString)")
        } else {
            Button(copied ? "Copied ✓" : "Copy install command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(provider.installCommand, forType: .string)
                copied = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = false }
            }.help("Copies: \(provider.installCommand)")
        }
    }
}
