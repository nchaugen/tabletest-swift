/// Parses TableTest table text into a ``Table``, as `tabletest-spec` SPEC.md defines it.
public enum TableParser {
    /// The table that the text holds, or the reason the text is not a table.
    public static func parse(_ text: String) throws(TableParseError) -> Table {
        let rows = try SourceLine.all(in: text)
            .filter(\.isRow)
            .map { line throws(TableParseError) in try RowReader.read(line) }
        guard let header = rows.first else {
            throw TableParseError(
                kind: .noRows,
                line: 0,
                column: 0,
                message: "Table has no rows: the input is empty or holds only blank lines and comments"
            )
        }
        try refuseBlankHeaderCells(in: header)
        return Table(header: header, rows: Array(rows.dropFirst()))
    }

    /// A header cell names a column, so it cannot be blank (SPEC 1.5).
    private static func refuseBlankHeaderCells(in header: Row) throws(TableParseError) {
        guard let blank = header.cells.firstIndex(where: { $0.value == .null }) else {
            return
        }
        throw TableParseError(
            kind: .blankHeader,
            line: header.line,
            column: header.cells[blank].column,
            message: "Header cell in column \(blank + 1) is blank"
        )
    }
}
