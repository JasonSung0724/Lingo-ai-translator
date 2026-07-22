import Foundation

struct HistoryItem: Codable, Identifiable {
    var id = UUID()
    let source: String
    let target: String
    let sourceCode: String
    let targetCode: String
}

enum HistoryStore {
    private static let key = "history"

    static func load() -> [HistoryItem] {
        guard let data = UserDefaults.standard.data(forKey: key) else { return [] }
        guard let items = try? JSONDecoder().decode([HistoryItem].self, from: data) else {
            // Keep the undecodable blob instead of silently overwriting it on next save.
            UserDefaults.standard.set(data, forKey: key + ".corrupt")
            return []
        }
        return items
    }

    static func save(_ items: [HistoryItem]) {
        if let data = try? JSONEncoder().encode(items) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}
