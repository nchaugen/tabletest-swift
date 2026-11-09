/// Reads one row of a table by recursive descent over the scalars of its line.
///
/// Each grammar function returns `nil` when the text at the cursor does not match it, and
/// ``attempt(_:)`` then puts the cursor back. That is the backtracking of the JVM parser's
/// `either`. An error that no other reading can repair, such as a duplicate map key, throws.
struct RowReader {
    private let line: SourceLine
    private var position = 0

    private init(_ line: SourceLine) {
        self.line = line
    }

    /// The row on a line that holds a row, or the reason it does not parse.
    static func read(_ line: SourceLine) throws(TableParseError) -> Row {
        var reader = RowReader(line)
        return try reader.row()
    }

    // MARK: Row and cells (SPEC 1.6, 1.7)

    private mutating func row() throws(TableParseError) -> Row {
        var cells: [Cell] = []
        while true {
            skipWhitespace()
            let column = position
            guard let value = try cellValue() else {
                throw malformed(at: column)
            }
            cells.append(Cell(value: value, column: column))
            skipWhitespace()
            if isAtEnd {
                return Row(line: line.index, cells: cells)
            }
            guard consume("|") else {
                throw malformed(at: column)
            }
        }
    }

    private mutating func cellValue() throws(TableParseError) -> TableValue? {
        if let collection = try collection() {
            return collection
        }
        if let quoted = try attempt({ $0.quotedString() }) {
            return .string(quoted)
        }
        return unquotedCellValue()
    }

    /// The text up to the next `|` or the line end. A blank cell holds null (SPEC 1.6, 2.1).
    private mutating func unquotedCellValue() -> TableValue? {
        guard let first = current else {
            return .null
        }
        switch first {
        case "|": return .null
        case "[", "{": return nil
        default: return .string(trimmedText(while: { $0 != "|" }))
        }
    }

    // MARK: Strings (SPEC 2.2, 2.4)

    /// The text between two equal quote characters, or `nil` when there is no closing quote.
    private mutating func quotedString() -> String? {
        guard let quote = current, quote == "'" || quote == "\"" else {
            return nil
        }
        let start = position + 1
        guard let end = line.scalars[start...].firstIndex(of: quote) else {
            return nil
        }
        position = end + 1
        return text(from: start, to: end)
    }

    // MARK: Lists, sets and maps (SPEC 2.5–2.11)

    private mutating func collection() throws(TableParseError) -> TableValue? {
        nil
    }

    // MARK: Cursor

    private var isAtEnd: Bool {
        position >= line.scalars.count
    }

    private var current: Unicode.Scalar? {
        isAtEnd ? nil : line.scalars[position]
    }

    private mutating func consume(_ scalar: Unicode.Scalar) -> Bool {
        guard current == scalar else {
            return false
        }
        position += 1
        return true
    }

    private mutating func skipWhitespace() {
        while let scalar = current, scalar.isTableWhitespace {
            position += 1
        }
    }

    /// Runs a grammar function, and puts the cursor back when it does not match.
    private mutating func attempt<Value>(
        _ parse: (inout RowReader) throws(TableParseError) -> Value?
    ) throws(TableParseError) -> Value? {
        let start = position
        if let value = try parse(&self) {
            return value
        }
        position = start
        return nil
    }

    /// The text from the cursor while the scalars match, without whitespace at its end.
    private mutating func trimmedText(while matches: (Unicode.Scalar) -> Bool) -> String {
        let start = position
        while let scalar = current, matches(scalar) {
            position += 1
        }
        var end = position
        while end > start, line.scalars[end - 1].isTableWhitespace {
            end -= 1
        }
        return text(from: start, to: end)
    }

    private func text(from start: Int, to end: Int) -> String {
        String(String.UnicodeScalarView(line.scalars[start..<end]))
    }

    // MARK: Errors

    private func malformed(at column: Int) -> TableParseError {
        let rest = text(from: column, to: line.scalars.count)
        let row = line.text.trimmingTableWhitespace()
        return TableParseError(
            kind: .malformed,
            line: line.index,
            column: column,
            message: "Failed to parse `\(rest)` in row `\(row)`"
        )
    }
}

extension String {
    func trimmingTableWhitespace() -> String {
        let scalars = unicodeScalars.drop(while: \.isTableWhitespace)
        let end = scalars.lastIndex { !$0.isTableWhitespace }.map { scalars.index(after: $0) } ?? scalars.startIndex
        return String(String.UnicodeScalarView(scalars[scalars.startIndex..<end]))
    }
}
