import TableTestParser

/// Formats TableTest table text, as `tabletest-spec` SPEC.md chapter 4 defines it.
///
/// A formatter changes only whitespace (SPEC 4.1): each cell prints as written, columns line up,
/// and comment lines, blank lines and line endings stay as they are.
public enum TableFormatter {
    /// The table text with its columns lined up, or the text unchanged when it is not a table
    /// (SPEC 4.2).
    public static func format(_ text: String) -> String {
        formattedTable(text) ?? text
    }

    /// The table text with its columns lined up, or `nil` when the text does not parse or a data
    /// row has another number of cells than the header row.
    package static func formattedTable(_ text: String) -> String? {
        guard let table = try? TableParser.parse(text) else {
            return nil
        }
        let rows = [table.header] + table.rows
        guard rows.allSatisfy({ $0.cells.count == table.header.cells.count }) else {
            return nil
        }
        let printedRows = rows.map { $0.cells.map(\.written.cellText) }
        let widths = table.header.cells.indices.map { column in
            printedRows.map { DisplayWidth.of($0[column]) }.max() ?? 0
        }
        let formattedRows = Dictionary(uniqueKeysWithValues: zip(rows.map(\.line), printedRows.map {
            layout(of: $0, columnWidths: widths)
        }))
        return text.unicodeScalars
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { index, line in
                let original = String(String.UnicodeScalarView(line))
                guard let formatted = formattedRows[index] else {
                    return original
                }
                return line.last == "\r" ? formatted + "\r" : formatted
            }
            .joined(separator: "\n")
    }

    /// One row: cells separated by `|`, each but the first after one space, each but the last
    /// padded to its column width and one space more (SPEC 4.3).
    private static func layout(of cells: [String], columnWidths: [Int]) -> String {
        guard cells.count > 1 else {
            return cells.first ?? ""
        }
        return cells.indices.map { column in
            let cell = cells[column]
            if column == cells.count - 1 {
                return cell.isEmpty ? "" : " " + cell
            }
            let padded = cell + String(repeating: " ", count: columnWidths[column] - DisplayWidth.of(cell) + 1)
            return column == 0 ? padded : " " + padded
        }
        .joined(separator: "|")
    }
}

extension WrittenValue {
    /// The cell as a formatter prints it: as written, with `, ` and `: ` in a list, a set or a
    /// map, and no space just inside a bracket or a brace (SPEC 4.5).
    var cellText: String {
        switch self {
        case .blank:
            ""
        case let .text(text):
            text
        case let .list(elements):
            "[" + elements.map(\.cellText).joined(separator: ", ") + "]"
        case let .set(elements):
            "{" + elements.map(\.cellText).joined(separator: ", ") + "}"
        case let .map(pairs) where pairs.isEmpty:
            "[:]"
        case let .map(pairs):
            "[" + pairs.map { "\($0.key): \($0.value.cellText)" }.joined(separator: ", ") + "]"
        }
    }
}
