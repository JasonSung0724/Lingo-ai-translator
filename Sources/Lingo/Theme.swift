import SwiftUI

struct Theme: Identifiable {
    let id: String
    let name: String
    let color: Color
}

enum Themes {
    static let all: [Theme] = [
        Theme(id: "blue", name: "Blue", color: .blue),
        Theme(id: "indigo", name: "Indigo", color: .indigo),
        Theme(id: "purple", name: "Purple", color: .purple),
        Theme(id: "pink", name: "Pink", color: .pink),
        Theme(id: "red", name: "Red", color: .red),
        Theme(id: "orange", name: "Orange", color: .orange),
        Theme(id: "green", name: "Green", color: .green),
        Theme(id: "teal", name: "Teal", color: .teal),
        Theme(id: "graphite", name: "Graphite", color: Color(nsColor: .systemGray)),
    ]

    static func theme(id: String) -> Theme { all.first { $0.id == id } ?? all[0] }
}

enum Appearance {
    static func apply(_ name: String) {
        switch name {
        case "light": NSApp.appearance = NSAppearance(named: .aqua)
        case "dark": NSApp.appearance = NSAppearance(named: .darkAqua)
        default: NSApp.appearance = nil
        }
    }
}
