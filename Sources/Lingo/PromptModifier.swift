import Foundation

struct PromptModifier: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var directive: String
}

enum ModifierKind: String { case tone, context }

enum ModifierStore {
    static let defaultTones: [PromptModifier] = [
        .init(id: "default", name: "Default", directive: ""),
        .init(id: "formal", name: "Formal", directive: "Use a formal, polite register."),
        .init(id: "casual", name: "Casual", directive: "Use a casual, conversational tone."),
        .init(id: "professional", name: "Professional", directive: "Use a professional business tone."),
        .init(id: "friendly", name: "Friendly", directive: "Use a warm, friendly tone."),
        .init(id: "concise", name: "Concise", directive: "Be concise and direct; prefer shorter phrasing."),
    ]

    static let defaultContexts: [PromptModifier] = [
        .init(id: "none", name: "None", directive: ""),
        .init(id: "email", name: "Email", directive: "The text is email correspondence; translate it appropriately."),
        .init(id: "chat", name: "Chat message", directive: "The text is an instant-message chat; keep it natural and conversational."),
        .init(id: "technical", name: "Technical", directive: "The text is technical documentation; keep terminology precise and consistent."),
        .init(id: "marketing", name: "Marketing", directive: "The text is marketing copy; make it engaging and persuasive."),
    ]

    private static func key(_ kind: ModifierKind) -> String { "modifiers.\(kind.rawValue)" }

    static func load(_ kind: ModifierKind) -> [PromptModifier] {
        if let data = UserDefaults.standard.data(forKey: key(kind)),
           let items = try? JSONDecoder().decode([PromptModifier].self, from: data), !items.isEmpty {
            return items
        }
        return kind == .tone ? defaultTones : defaultContexts
    }

    static func save(_ kind: ModifierKind, _ items: [PromptModifier]) {
        if let data = try? JSONEncoder().encode(items) { UserDefaults.standard.set(data, forKey: key(kind)) }
    }

    static func reset(_ kind: ModifierKind) {
        UserDefaults.standard.removeObject(forKey: key(kind))
    }

    static func directive(_ kind: ModifierKind, id: String) -> String {
        load(kind).first { $0.id == id }?.directive ?? ""
    }
}
