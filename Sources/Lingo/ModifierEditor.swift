import SwiftUI

struct ModifierEditor: View {
    let kind: ModifierKind
    let title: String
    var onChange: () -> Void
    @State private var items: [PromptModifier] = []

    var body: some View {
        Section(title) {
            ForEach($items) { $item in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        TextField("Name", text: $item.name)
                            .textFieldStyle(.roundedBorder).labelsHidden()
                            .font(.system(size: 13, weight: .medium))
                        Button { delete(item) } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain).foregroundStyle(.secondary).help("Delete")
                    }
                    TextField("Instruction for the AI (leave blank for no change)",
                              text: $item.directive, axis: .vertical)
                        .textFieldStyle(.roundedBorder).labelsHidden()
                        .lineLimit(2...5).font(.system(size: 12))
                }
                .padding(.vertical, 6)
            }
            HStack {
                Button { add() } label: { Label("Add", systemImage: "plus") }
                Spacer()
                Button("Reset to defaults") { ModifierStore.reset(kind); load(); onChange() }
            }
        }
        .onAppear(perform: load)
        // Only persist real user edits — loading (and Reset) must not re-write the
        // store, or shipped default improvements would never reach existing users.
        .onChange(of: items) { _, value in
            if value != ModifierStore.load(kind) { persist() }
        }
    }

    private func load() { items = ModifierStore.load(kind) }
    private func persist() { ModifierStore.save(kind, items); onChange() }
    private func add() { items.append(PromptModifier(id: UUID().uuidString, name: "New", directive: "")) }
    private func delete(_ item: PromptModifier) {
        items.removeAll { $0.id == item.id }
        // Deleting the last one falls back to the defaults (an empty list would
        // silently mean "defaults" in the store anyway — keep the UI honest).
        if items.isEmpty {
            items = kind == .tone ? ModifierStore.defaultTones : ModifierStore.defaultContexts
        }
    }
}
