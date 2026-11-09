/// Parses TableTest table text into a ``Table``, as `tabletest-spec` SPEC.md defines it.
public enum TableParser {
    /// The table that the text holds, or the reason the text is not a table.
    public static func parse(_ text: String) throws(TableParseError) -> Table {
        throw TableParseError(kind: .malformed, line: 0, column: 0, message: "Not implemented")
    }
}
