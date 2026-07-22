import SwiftUI

struct RootView: View {
    @ObservedObject var model: TranslatorModel

    var body: some View {
        Group {
            if model.showingOnboarding {
                OnboardingView(model: model, onFinish: { model.finishOnboarding() })
            } else if model.showingSettings {
                SetupView(model: model, onClose: { model.showingSettings = false })
            } else {
                TranslatorView(model: model, openSetup: { model.showingSettings = true })
            }
        }
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .background(
            Button("") {
                model.dismissOnboarding()   // closing the window mid-guide counts as skipping
                model.window?.orderOut(nil)
            }
                .keyboardShortcut("w", modifiers: .command)
                .hidden()
        )
    }
}
