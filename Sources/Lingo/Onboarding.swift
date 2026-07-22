import SwiftUI
import ApplicationServices

// First-run wizard: Welcome → Accessibility → Shortcuts → AI engine → Done.
// Reopenable any time from the menu bar ("Welcome Guide…"). Global hotkeys are
// paused while it shows (see HotKeyManager.setPaused) and re-armed on dismissal.
struct OnboardingView: View {
    @ObservedObject var model: TranslatorModel
    var onFinish: () -> Void

    @State private var step = min(max(Prefs.onboardingStep, 0), 4)   // resume after a self-relaunch
    @ObservedObject private var ax = AXWatcher.shared
    @State private var installed: [String: Bool] = [:]
    @State private var verifying = ""
    @State private var verified: [String: Bool] = [:]
    @State private var verifyNote: [String: String] = [:]

    private let stepCount = 5
    private let aiStep = 3

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                if step < stepCount - 1 {
                    Button("Skip Setup") { onFinish() }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(.tertiary)
                }
            }
            .padding(.horizontal, 16).padding(.top, 12)

            Group {
                switch step {
                case 0: welcome
                case 1: accessibility
                case 2: shortcuts
                case aiStep: aiEngine
                default: done
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 40)

            footer
        }
        // Fixed size: without it NSHostingView drives the window to the
        // content's ideal height (thousands of points on first launch).
        .frame(width: 600, height: 660)
        .tint(model.accent)
        .onChange(of: step) { _, value in
            Prefs.onboardingStep = value
            // Pause global hotkeys only while the recorder is on screen — a
            // combo that's already registered would fire instead of recording.
            HotKeyManager.shared.setPaused(value == 2)
            if value == aiStep { refreshInstalled() }
        }
        .onAppear {
            HotKeyManager.shared.setPaused(step == 2)
            if step == aiStep { refreshInstalled() }
        }
        // Returning from a terminal (install / sign-in) re-activates the app.
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if step == aiStep { refreshInstalled() }
        }
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 14) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 84, height: 84)
            Text("Welcome to Lingo").font(.largeTitle.bold())
            Text("Translate anything on your Mac — instantly, from any app.")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                feature("keyboard", "Global hotkeys",
                        "Select text anywhere and press \(HotKeyAction.translate.combo) to translate it.")
                feature("bubble.left.and.bubble.right", "Quick popup",
                        "\(HotKeyAction.popup.combo) shows the translation right next to your cursor.")
                feature("camera.viewfinder", "Screenshot OCR",
                        "\(HotKeyAction.screenshot.combo) captures part of the screen and translates the text in it.")
                feature("arrow.2.squarepath", "Translate & replace",
                        "\(HotKeyAction.replace.combo) rewrites the selected text in place.")
            }
            .padding(.top, 8)
        }
    }

    private var accessibility: some View {
        VStack(spacing: 14) {
            stepHeader("hand.raised", "Allow Lingo to read your selection",
                       "Grabbing selected text and replacing it needs the macOS Accessibility permission. Lingo uses it only to copy and paste on your behalf — nothing is logged or sent anywhere.")
            if ax.trusted {
                statusCard(icon: "checkmark.circle.fill", color: .green,
                           title: "Accessibility enabled",
                           detail: "Lingo reads your selection directly — hotkeys go live the moment you finish this guide.")
            } else {
                statusCard(icon: "exclamationmark.circle.fill", color: .orange,
                           title: "Not granted yet",
                           detail: "Click below, then turn on Lingo in System Settings → Privacy & Security → Accessibility. Lingo detects the change instantly — no restart needed.")
                Button("Grant Accessibility") { requestAccessibility() }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                Text("Toggle already ON but still not detected? macOS pinned an older copy of Lingo — remove Lingo from the list (−), then add it again (+).")
                    .font(.caption2).foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center).frame(maxWidth: 430)
            }
            Text("You can skip this — the translator window and screenshot OCR work without it.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var shortcuts: some View {
        VStack(spacing: 14) {
            stepHeader("keyboard", "Your shortcuts",
                       "These will work system-wide. Click one to record a different combination.")
            VStack(spacing: 6) {
                ForEach(HotKeyAction.allCases) { action in KeyRecorder(action: action) }
            }
            .padding(.vertical, 10).padding(.horizontal, 16)
            .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
            Text("Esc cancels a recording. Shortcuts are paused only while on this step; change them any time in Setup → Shortcuts.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var aiEngine: some View {
        VStack(spacing: 14) {
            stepHeader("sparkles", "Choose your translation engine",
                       "Offline translation works out of the box — on-device, private, no account. For higher quality, Lingo can use an AI CLI you already pay for. No API keys are ever stored.")
            VStack(spacing: 10) {
                ForEach(Providers.all, id: \.id) { provider in providerRow(provider) }
            }
            Text("Sign-in happens in your terminal, in your own account. You can set this up later in Setup → Providers.")
                .font(.caption).foregroundStyle(.tertiary)
        }
    }

    private var done: some View {
        VStack(spacing: 14) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 56)).foregroundStyle(.green)
            Text("You're all set").font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 12) {
                feature("menubar.arrow.up.rectangle", "Lingo lives in your menu bar",
                        "Look for the speech-bubble icon — every action and Setup is there.")
                feature("keyboard", "Try it after this guide",
                        "Click “Start Using Lingo”, select text in any app, and press \(HotKeyAction.translate.combo).")
                feature("arrow.counterclockwise", "See this guide again",
                        "Menu bar icon → Welcome Guide…")
            }
            .padding(.top, 8)
        }
    }

    // MARK: Pieces

    private func feature(_ icon: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 17)).foregroundStyle(.tint)
                .frame(width: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: 400, alignment: .leading)
    }

    private func stepHeader(_ icon: String, _ title: String, _ detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon).font(.system(size: 34)).foregroundStyle(.tint)
            Text(title).font(.title2.bold()).multilineTextAlignment(.center)
            Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 430)
        }
    }

    private func statusCard(icon: String, color: Color, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 20)).foregroundStyle(color)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 13, weight: .semibold))
                Text(detail).font(.system(size: 12)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: 430)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
    }

    private func providerRow(_ provider: AIProvider) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(provider.displayName).font(.system(size: 13, weight: .semibold))
                    Text(providerStatus(provider)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                if installed[provider.id] != true {
                    ProviderInstallButton(provider: provider)
                } else if verified[provider.id] ?? (Prefs.providerOK(provider.id) || provider.isSignedIn) {
                    Label("Ready", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(.green).font(.system(size: 12, weight: .medium))
                } else {
                    Button("Sign In") { runInTerminal(provider.loginCommand) }
                        .help("Opens the sign-in flow in Terminal")
                    if verifying == provider.id {
                        ProgressView().controlSize(.small)
                    } else {
                        Button("Verify") { verify(provider) }
                            .disabled(!verifying.isEmpty)
                            .help("Runs a one-word test translation to confirm you're signed in")
                    }
                }
            }
            if let note = verifyNote[provider.id], verifying != provider.id {
                Text(note).font(.system(size: 10)).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .frame(maxWidth: 430)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
    }

    private func providerStatus(_ provider: AIProvider) -> String {
        if installed[provider.id] != true { return "CLI not installed" }
        if verified[provider.id] ?? (Prefs.providerOK(provider.id) || provider.isSignedIn) { return "Signed in and working" }
        return "CLI installed — sign in with your own account"
    }

    private var footer: some View {
        HStack {
            Button("Back") { step -= 1 }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .opacity(step > 0 ? 1 : 0).disabled(step == 0)
            Spacer()
            HStack(spacing: 7) {
                ForEach(0..<stepCount, id: \.self) { index in
                    Circle()
                        .fill(index == step ? AnyShapeStyle(.tint) : AnyShapeStyle(.quaternary))
                        .frame(width: 7, height: 7)
                }
            }
            Spacer()
            Button(step == stepCount - 1 ? "Start Using Lingo" : "Continue") {
                if step == stepCount - 1 { onFinish() } else { step += 1 }
            }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.horizontal, 24).padding(.bottom, 20)
    }

    // MARK: Actions

    private func refreshInstalled() {
        Providers.detectInstalled { installed = $0 }
    }

    // One verify at a time — providers share one AITask slot, so a second
    // in-flight check would kill the first and misreport "not signed in".
    private func verify(_ provider: AIProvider) {
        guard verifying.isEmpty else { return }
        verifying = provider.id
        provider.translate(text: "Hello", sourceName: "English",
                           targetName: Languages.name(for: Prefs.targetCode), directives: "",
                           onDelta: { _ in },
                           onDone: { outcome in
            verifying = ""
            switch outcome {
            case .success:
                verified[provider.id] = true
                Prefs.setProviderOK(provider.id, true)
                verifyNote[provider.id] = nil
            case .needsLogin:
                verified[provider.id] = false
                Prefs.setProviderOK(provider.id, false)
                verifyNote[provider.id] = "Not signed in yet — click Sign In, finish in Terminal, then Verify again."
            case .notInstalled:
                installed[provider.id] = false
                verifyNote[provider.id] = nil
            case .failure:
                verified[provider.id] = false
                verifyNote[provider.id] = "Couldn't verify — the CLI didn't respond. Check your connection and try again."
            }
        })
    }
}
