import SwiftUI

struct MarkdownText: View {
    let text: String

    private enum Block: Identifiable {
        case line(Int, String)
        case table(Int, [[String]])
        var id: Int { switch self { case .line(let i, _): return i; case .table(let i, _): return i } }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(blocks()) { block in
                switch block {
                case .line(_, let line): lineView(line)
                case .table(_, let rows): tableView(rows)
                }
            }
        }
    }

    // MARK: Parsing

    private func blocks() -> [Block] {
        let lines = text.components(separatedBy: "\n")
        var result: [Block] = []
        var i = 0
        while i < lines.count {
            if i + 1 < lines.count, isTableRow(lines[i]), isSeparator(lines[i + 1]) {
                var rows = [cells(lines[i])]
                i += 2
                while i < lines.count, isTableRow(lines[i]) { rows.append(cells(lines[i])); i += 1 }
                let cols = rows.map(\.count).max() ?? 0
                let padded = rows.map { $0 + Array(repeating: "", count: max(0, cols - $0.count)) }
                result.append(.table(result.count, padded))
            } else {
                result.append(.line(result.count, lines[i])); i += 1
            }
        }
        return result
    }

    private func isTableRow(_ line: String) -> Bool {
        line.trimmingCharacters(in: .whitespaces).hasPrefix("|") && line.contains("|")
    }

    private func isSeparator(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("|") else { return false }
        for cell in cells(line) {
            let c = cell.trimmingCharacters(in: .whitespaces)
            if c.isEmpty || !c.allSatisfy({ $0 == "-" || $0 == ":" }) { return false }
        }
        return true
    }

    private func cells(_ line: String) -> [String] {
        var t = line.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("|") { t.removeFirst() }
        if t.hasSuffix("|") { t.removeLast() }
        return t.components(separatedBy: "|").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    // MARK: Rendering

    @ViewBuilder
    private func tableView(_ rows: [[String]]) -> some View {
        let cols = rows.first?.count ?? 0
        Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
            ForEach(rows.indices, id: \.self) { r in
                GridRow {
                    ForEach(0..<cols, id: \.self) { c in
                        Text(inline(rows[r][c]))
                            .font(.system(size: 12, weight: r == 0 ? .semibold : .regular))
                    }
                }
                if r == 0 { Divider().gridCellColumns(cols) }
            }
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.primary.opacity(0.04)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.primary.opacity(0.08)))
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private func lineView(_ line: String) -> some View {
        if line.hasPrefix("### ") {
            Text(inline(String(line.dropFirst(4)))).font(.system(size: 13, weight: .semibold)).padding(.top, 2)
        } else if line.hasPrefix("## ") {
            Text(inline(String(line.dropFirst(3)))).font(.system(size: 14, weight: .bold)).padding(.top, 3)
        } else if line.hasPrefix("# ") {
            Text(inline(String(line.dropFirst(2)))).font(.system(size: 15, weight: .bold)).padding(.top, 3)
        } else if let item = bullet(line) {
            HStack(alignment: .top, spacing: 6) {
                Text("•").font(.system(size: 13))
                Text(inline(item)).font(.system(size: 13))
            }
        } else if line.trimmingCharacters(in: .whitespaces).isEmpty {
            Color.clear.frame(height: 3)
        } else {
            Text(inline(line)).font(.system(size: 13))
        }
    }

    private func bullet(_ line: String) -> String? {
        for prefix in ["- ", "* ", "• "] where line.hasPrefix(prefix) { return String(line.dropFirst(prefix.count)) }
        return nil
    }

    private func inline(_ string: String) -> AttributedString {
        (try? AttributedString(markdown: string,
                               options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(string)
    }
}
