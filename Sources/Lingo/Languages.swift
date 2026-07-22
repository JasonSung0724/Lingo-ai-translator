import Foundation
import NaturalLanguage

struct Language: Identifiable, Hashable {
    let code: String
    let name: String
    var id: String { code }
}

enum Languages {
    static let all: [Language] = [
        .init(code: "ar", name: "Arabic"),
        .init(code: "zh-Hans", name: "Chinese (Simplified)"),
        .init(code: "zh-Hant", name: "Chinese (Traditional)"),
        .init(code: "nl", name: "Dutch"),
        .init(code: "en", name: "English"),
        .init(code: "fr", name: "French"),
        .init(code: "de", name: "German"),
        .init(code: "hi", name: "Hindi"),
        .init(code: "id", name: "Indonesian"),
        .init(code: "it", name: "Italian"),
        .init(code: "ja", name: "Japanese"),
        .init(code: "ko", name: "Korean"),
        .init(code: "pl", name: "Polish"),
        .init(code: "pt-BR", name: "Portuguese (Brazil)"),
        .init(code: "ru", name: "Russian"),
        .init(code: "es", name: "Spanish"),
        .init(code: "th", name: "Thai"),
        .init(code: "tr", name: "Turkish"),
        .init(code: "uk", name: "Ukrainian"),
        .init(code: "vi", name: "Vietnamese"),
    ]

    static func language(for code: String) -> Language {
        all.first { $0.code == code } ?? all.first { $0.code == "en" }!
    }

    static func name(for code: String) -> String { language(for: code).name }

    static func voice(for code: String) -> String {
        switch code {
        case "en": return "en-US"
        case "zh-Hant": return "zh-TW"
        case "zh-Hans": return "zh-CN"
        default: return code
        }
    }

    static func detect(_ text: String) -> String {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        guard let lang = recognizer.dominantLanguage?.rawValue else { return "en" }
        if lang.hasPrefix("zh") { return "zh-Hant" }
        if all.contains(where: { $0.code == lang }) { return lang }
        if let match = all.first(where: { $0.code.hasPrefix(lang + "-") }) { return match.code }
        return "en"
    }
}
