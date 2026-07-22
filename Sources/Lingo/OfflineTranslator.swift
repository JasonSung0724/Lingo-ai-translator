import SwiftUI
import Translation

final class OfflineTranslator: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?

    private var pendingText: String?
    private var completion: ((String?) -> Void)?
    private var lastPair = ""
    private var generation = 0

    func translate(_ text: String, source: String, target: String,
                   completion: @escaping (String?) -> Void) {
        var fired = false
        let once: (String?) -> Void = { result in
            if fired { return }
            fired = true
            DispatchQueue.main.async { completion(result) }
        }

        pendingText = text
        self.completion = once
        generation += 1
        let gen = generation

        let pair = "\(source)>\(target)"
        if configuration == nil || pair != lastPair {
            lastPair = pair
            configuration = TranslationSession.Configuration(
                source: Locale.Language(identifier: source),
                target: Locale.Language(identifier: target))
        } else {
            configuration?.invalidate()
        }

        // The timeout only applies to the request that is still current — a
        // superseded request's timer must not fire an error over a newer result.
        DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
            guard let self, self.generation == gen else { return }
            once(nil)
        }
    }

    func run(_ session: TranslationSession) async {
        guard let text = pendingText, let done = completion else { return }
        pendingText = nil
        completion = nil
        do {
            try await session.prepareTranslation()
            let responses = try await session.translations(from: [.init(sourceText: text)])
            done(responses.first?.targetText)
        } catch {
            done(nil)
        }
    }
}

struct TranslationDriver: View {
    @ObservedObject var translator: OfflineTranslator
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .translationTask(translator.configuration) { session in
                await translator.run(session)
            }
    }
}
