import SwiftUI

struct LanguageMenuButton: View {
    let title: String
    let includeAuto: Bool
    let onPick: (String) -> Void
    @State private var showing = false

    var body: some View {
        Button { showing = true } label: {
            HStack(spacing: 5) {
                Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.5)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 11).padding(.vertical, 6)
            .background(.quaternary, in: Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showing, arrowEdge: .bottom) {
            LanguageSearchList(includeAuto: includeAuto) { code in showing = false; onPick(code) }
        }
    }
}

struct LanguageSearchList: View {
    let includeAuto: Bool
    let onChoose: (String) -> Void
    @State private var query = ""
    @FocusState private var focused: Bool

    private var matches: [Language] {
        query.isEmpty ? Languages.all
            : Languages.all.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
    private var showAuto: Bool {
        includeAuto && (query.isEmpty || "detect language".localizedCaseInsensitiveContains(query))
    }

    var body: some View {
        VStack(spacing: 0) {
            TextField("Search language", text: $query)
                .textFieldStyle(.roundedBorder).focused($focused)
                .onSubmit(submit)
                .padding(8)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 1) {
                    if showAuto { LanguageRow(name: "Detect language") { onChoose("auto") } }
                    ForEach(matches) { lang in LanguageRow(name: lang.name) { onChoose(lang.code) } }
                    if matches.isEmpty && !showAuto {
                        Text("No matches").foregroundStyle(.secondary).padding(8)
                    }
                }
                .padding(4)
            }
            .frame(height: 260)
        }
        .frame(width: 230)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        }
    }

    private func submit() {
        if let first = matches.first { onChoose(first.code) }
        else if showAuto { onChoose("auto") }
    }
}

struct LanguageRow: View {
    let name: String
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            Text(name).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(hovering ? Color.accentColor.opacity(0.18) : Color.clear,
                    in: RoundedRectangle(cornerRadius: 6))
        .onHover { hovering = $0 }
    }
}
