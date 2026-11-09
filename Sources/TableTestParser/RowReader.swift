/// Reads one row of a table by recursive descent over the scalars of its line.
///
/// Each grammar function returns `nil` when the text at the cursor does not match it, and then
/// leaves the cursor where it found it. A caller can therefore try another reading, as the JVM
/// parser's `either` does. An error that no other reading can repair, such as a duplicate map
/// key, throws.
///
/// The functions restore the cursor themselves, with no closure-based helper, because nesting
/// recurses through them: fewer frames for each level of nesting keep deep input inside the
/// small stack of a test thread.
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
            guard let cell = try cellValue() else {
                throw malformed(at: column)
            }
            cells.append(Cell(value: cell.value, written: cell.written, column: column))
            skipWhitespace()
            if isAtEnd {
                return Row(line: line.index, cells: cells)
            }
            guard consume("|") else {
                throw malformed(at: column)
            }
        }
    }

    private mutating func cellValue() throws(TableParseError) -> ReadValue? {
        if let collection = try collection() {
            return collection
        }
        if let quoted = quotedString() {
            return quoted
        }
        return unquotedCellValue()
    }

    /// The text up to the next `|` or the line end. A blank cell holds null (SPEC 1.6, 2.1).
    private mutating func unquotedCellValue() -> ReadValue? {
        guard let first = current else {
            return .blank
        }
        switch first {
        case "|": return .blank
        case "[", "{": return nil
        default: return .text(trimmedText(while: { $0 != "|" }))
        }
    }

    // MARK: Strings (SPEC 2.2, 2.4)

    /// The text between two equal quote characters, or `nil` when there is no closing quote.
    private mutating func quotedString() -> ReadValue? {
        guard let quote = current, quote == "'" || quote == "\"" else {
            return nil
        }
        let start = position
        guard let end = line.scalars[(start + 1)...].firstIndex(of: quote) else {
            return nil
        }
        position = end + 1
        return ReadValue(value: .string(text(from: start + 1, to: end)), written: .text(text(from: start, to: position)))
    }

    // MARK: Lists, sets and maps (SPEC 2.5–2.11)

    /// A list, a set, or a map at the cursor. A `[` is read as a map first, and as a list when
    /// its content is not pairs.
    private mutating func collection() throws(TableParseError) -> ReadValue? {
        switch current {
        case "[":
            if let map = try map() {
                return map
            }
            return try list()
        case "{":
            return try set()
        default:
            return nil
        }
    }

    private mutating func list() throws(TableParseError) -> ReadValue? {
        let start = position
        guard consume("[") else {
            return nil
        }
        let elements = try elements() ?? []
        guard consume("]") else {
            return backtrack(to: start)
        }
        return ReadValue(value: .list(elements.map(\.value)), written: .list(elements.map(\.written)))
    }

    /// A set holds each value once; its written form keeps a repeated element.
    private mutating func set() throws(TableParseError) -> ReadValue? {
        let start = position
        guard consume("{") else {
            return nil
        }
        let elements = try elements() ?? []
        guard consume("}") else {
            return backtrack(to: start)
        }
        return ReadValue(value: .set(elements.map(\.value).withoutDuplicates()), written: .set(elements.map(\.written)))
    }

    private mutating func map() throws(TableParseError) -> ReadValue? {
        let start = position
        guard consume("[") else {
            return nil
        }
        let pairs: [KeyedPair]
        if emptyMapContent() {
            pairs = []
        } else if let read = try self.pairs() {
            pairs = read
        } else {
            return backtrack(to: start)
        }
        let entries = try entriesWithUniqueKeys(pairs, mapStart: start)
        guard consume("]") else {
            return backtrack(to: start)
        }
        return ReadValue(
            value: .map(entries),
            written: .map(pairs.map { WrittenPair(key: $0.writtenKey, value: $0.value.written) })
        )
    }

    /// Reads the `:` of `[:]`, with any whitespace around it.
    private mutating func emptyMapContent() -> Bool {
        let start = position
        skipWhitespace()
        guard consume(":") else {
            position = start
            return false
        }
        skipWhitespace()
        return true
    }

    private mutating func elements() throws(TableParseError) -> [ReadValue]? {
        guard let first = try element() else {
            return nil
        }
        var elements = [first]
        while let next = try nextElement() {
            elements.append(next)
        }
        return elements
    }

    /// A `,` and the element after it.
    private mutating func nextElement() throws(TableParseError) -> ReadValue? {
        let start = position
        guard consume(","), let element = try element() else {
            return backtrack(to: start)
        }
        return element
    }

    /// One element, with the whitespace around it (SPEC 2.8).
    private mutating func element() throws(TableParseError) -> ReadValue? {
        let start = position
        skipWhitespace()
        let element: ReadValue
        if let collection = try collection() {
            element = collection
        } else if let quoted = quotedString() {
            element = quoted
        } else if let unquoted = unquotedText(endingBefore: Self.elementEndings) {
            element = .text(unquoted)
        } else {
            return backtrack(to: start)
        }
        skipWhitespace()
        return element
    }

    private mutating func pairs() throws(TableParseError) -> [KeyedPair]? {
        guard let first = try pair() else {
            return nil
        }
        var pairs = [first]
        while let next = try nextPair() {
            pairs.append(next)
        }
        return pairs
    }

    /// A `,` and the pair after it.
    private mutating func nextPair() throws(TableParseError) -> KeyedPair? {
        let start = position
        guard consume(","), let pair = try pair() else {
            return backtrack(to: start)
        }
        return pair
    }

    private mutating func pair() throws(TableParseError) -> KeyedPair? {
        let start = position
        skipWhitespace()
        let column = position
        guard let key = quotedString() ?? unquotedText(endingBefore: Self.keyEndings).map(ReadValue.text) else {
            return backtrack(to: start)
        }
        skipWhitespace()
        guard consume(":"), let value = try element() else {
            return backtrack(to: start)
        }
        guard case .string(let keyText) = key.value, case .text(let writtenKey) = key.written else {
            return backtrack(to: start)
        }
        return KeyedPair(key: keyText, writtenKey: writtenKey, column: column, value: value)
    }

    /// The scalars that cannot start an unquoted element or key (SPEC 2.8, 2.9).
    private static let unquotedStartExclusions = Set(",:|[]{}'\"".unicodeScalars)
    /// The scalars that end an unquoted element: inside one, `[` and `{` are text.
    private static let elementEndings = Set(",:|]}".unicodeScalars)
    /// The scalars that end an unquoted key: inside one, `{` and `}` are text.
    private static let keyEndings = Set(",:|[]".unicodeScalars)

    /// The text from the cursor to the first ending scalar, without whitespace at its end, or
    /// `nil` when the first scalar cannot start an unquoted element or key.
    private mutating func unquotedText(endingBefore endings: Set<Unicode.Scalar>) -> String? {
        guard let first = current, !Self.unquotedStartExclusions.contains(first) else {
            return nil
        }
        return trimmedText(while: { !endings.contains($0) })
    }

    /// A map pair, with the column of its key for a duplicate-key error.
    private struct KeyedPair {
        let key: String
        let writtenKey: String
        let column: Int
        let value: ReadValue
    }

    /// The value of a cell or an element, and how it is written.
    private struct ReadValue {
        let value: TableValue
        let written: WrittenValue

        static let blank = ReadValue(value: .null, written: .blank)

        /// Unquoted text: its value and its written form are the same text.
        static func text(_ text: String) -> ReadValue {
            ReadValue(value: .string(text), written: .text(text))
        }
    }

    /// The pairs as map entries, refusing a key that occurs twice (SPEC 2.10).
    private func entriesWithUniqueKeys(
        _ pairs: [KeyedPair],
        mapStart: Int
    ) throws(TableParseError) -> [TableMapEntry] {
        let duplicate = pairs.indices.first { index in
            pairs[..<index].contains { $0.key.hasSameScalars(as: pairs[index].key) }
        }
        if let duplicate {
            let map = text(from: mapStart + 1, to: position).trimmingTableWhitespace()
            throw TableParseError(
                kind: .duplicateKey,
                line: line.index,
                column: pairs[duplicate].column,
                message: "Duplicate key `\(pairs[duplicate].key)` in map `[\(map)]` in row `\(rowText)`"
            )
        }
        return pairs.map { TableMapEntry(key: $0.key, value: $0.value.value) }
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

    /// Puts the cursor back to where a grammar function started, and reports no match.
    private mutating func backtrack<Value>(to start: Int) -> Value? {
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

    /// The row as written, for an error message: every error names its row (SPEC 1.7).
    private var rowText: String {
        line.text.trimmingTableWhitespace()
    }

    private func malformed(at column: Int) -> TableParseError {
        let rest = text(from: column, to: line.scalars.count)
        return TableParseError(
            kind: .malformed,
            line: line.index,
            column: column,
            message: "Failed to parse `\(rest)` in row `\(rowText)`"
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
