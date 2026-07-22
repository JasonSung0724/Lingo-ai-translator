import AppKit
import Vision

enum OCR {
    // A shelled-out `screencapture` never registers the app in the TCC list,
    // so Lingo was missing from Privacy & Security → Screen Recording with no
    // way to add it. Requesting access ourselves makes macOS list the app.
    static func ensureScreenPermission() -> Bool {
        if CGPreflightScreenCaptureAccess() { return true }
        let defaults = UserDefaults.standard
        // Re-request on every attempt: with ad-hoc signing the registration
        // can silently fail to add the app to the pane, so a single try could
        // leave the user stranded. Retrying is harmless — the system dialog
        // itself only ever appears once.
        CGRequestScreenCaptureAccess()
        if defaults.bool(forKey: "srPrompted") {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
                NSWorkspace.shared.open(url)
            }
        }
        defaults.set(true, forKey: "srPrompted")
        return false
    }

    static func captureAndRecognize(completion: @escaping (String?) -> Void) {
        let path = NSTemporaryDirectory() + "lingo-ocr.png"
        try? FileManager.default.removeItem(atPath: path)

        let capture = Process()
        capture.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        capture.arguments = ["-i", "-x", path]
        capture.terminationHandler = { _ in
            DispatchQueue.main.async {
                guard FileManager.default.fileExists(atPath: path),
                      let image = NSImage(contentsOfFile: path),
                      let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                    completion(nil); return
                }
                recognize(cgImage, completion: completion)
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        do { try capture.run() } catch { completion(nil) }
    }

    // Scanning all ten scripts costs time. When the user has fixed the source
    // language, narrow recognition to their languages (validated against what
    // Vision supports, falling back to the full list).
    private static let allLanguages = ["en-US", "zh-Hant", "zh-Hans", "ja-JP", "ko-KR",
                                       "fr-FR", "de-DE", "es-ES", "it-IT", "ru-RU"]

    private static func recognitionLanguages(for request: VNRecognizeTextRequest) -> [String] {
        guard Prefs.sourceCode != "auto",
              let supported = try? request.supportedRecognitionLanguages() else { return allLanguages }
        func match(_ code: String) -> String? {
            supported.first { $0 == code || $0.hasPrefix(code + "-") || code.hasPrefix($0) }
        }
        var seen = Set<String>()
        let narrowed = [Prefs.sourceCode, Prefs.targetCode, "en-US"]
            .compactMap(match)
            .filter { seen.insert($0).inserted }
        return narrowed.isEmpty ? allLanguages : narrowed
    }

    private static func recognize(_ image: CGImage, completion: @escaping (String?) -> Void) {
        let request = VNRecognizeTextRequest { request, _ in
            let lines = (request.results as? [VNRecognizedTextObservation])?
                .compactMap { $0.topCandidates(1).first?.string } ?? []
            let text = lines.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async { completion(text.isEmpty ? nil : text) }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = recognitionLanguages(for: request)
        let handler = VNImageRequestHandler(cgImage: image)
        DispatchQueue.global(qos: .userInitiated).async {
            do { try handler.perform([request]) }
            catch { DispatchQueue.main.async { completion(nil) } }   // surface as "no text found" instead of silence
        }
    }
}
