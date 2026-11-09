import Testing

/// Where a table literal is in the source, so that a row can point at its own line.
public struct TableSource: Sendable {
    public let fileID: String
    public let filePath: String
    /// The line of the literal's opening quote.
    public let line: Int
    /// The column of the literal's opening quote.
    public let column: Int
    /// The number of scalars that the literal removes from the start of each line: the
    /// indentation of the closing quote of a multiline literal.
    public let indentation: Int
    /// Whether the literal is a multiline literal, whose lines map one to one to the source.
    public let isMultiline: Bool

    public init(fileID: String, filePath: String, line: Int, column: Int, indentation: Int, isMultiline: Bool) {
        self.fileID = fileID
        self.filePath = filePath
        self.line = line
        self.column = column
        self.indentation = indentation
        self.isMultiline = isMultiline
    }

    /// The source location of a position in the table text. A single-line literal maps
    /// every position to the literal itself, because its escapes break the mapping.
    func location(line tableLine: Int, column tableColumn: Int) -> SourceLocation {
        isMultiline
            ? SourceLocation(
                fileID: fileID,
                filePath: filePath,
                line: line + 1 + tableLine,
                column: indentation + tableColumn + 1
            )
            : SourceLocation(fileID: fileID, filePath: filePath, line: line, column: column)
    }
}

/// One parameter of the function that a table is attached to.
public struct TableParameter: Sendable {
    /// Whether the parameter takes a whole set cell, rather than one test case for each element.
    let takesSet: Bool

    /// The parameter of a type. It takes a set when its type is a `SetAlgebra` type, such as
    /// `Set` or an `OptionSet`, or ``TableValue``, or an optional of one (SPEC 3.6).
    public init<T>(_ type: T.Type) {
        takesSet = Self.holdsASet(T.self)
    }

    init(takesSet: Bool) {
        self.takesSet = takesSet
    }

    private static func holdsASet(_ type: Any.Type) -> Bool {
        if type is any SetAlgebra.Type || type == TableValue.self {
            return true
        }
        if let optional = type as? any OptionalType.Type {
            return holdsASet(optional.wrappedType)
        }
        return false
    }
}

/// An optional type, so that a parameter of type `Set<Int>?` still takes a set.
private protocol OptionalType {
    static var wrappedType: Any.Type { get }
}

extension Optional: OptionalType {
    fileprivate static var wrappedType: Any.Type {
        Wrapped.self
    }
}

/// A table that does not fit the function it is attached to.
public struct TableTestError: Error, CustomStringConvertible, Sendable {
    /// The run error classes of the spec's run fixtures.
    public enum Kind: Sendable, Equatable {
        /// The table has two or more columns more than the function has parameters, or fewer.
        case columnCount
        /// A data row has another number of cells than the header row.
        case rowWidth
        /// A value set in the column of a parameter that does not take a set has no elements.
        case emptyValueSet
    }

    public let kind: Kind
    public let description: String
}

/// Builds the test cases of a table.
public enum TableTestRows {
    /// The suite instance that runs a row. The expansion writes `try await` before it, which a
    /// suite `init` that neither throws nor suspends would otherwise warn about; a suite `init`
    /// that throws fails the row, as it fails a Swift Testing test.
    public static func suite<Suite>(_ suite: consuming Suite,
                                    isolation: isolated (any Actor)? = #isolation) async throws -> Suite {
        suite
    }

    /// The test cases of a table: one for each data row, or one for each combination of the
    /// row's value sets.
    ///
    /// When the table has one more column than the function has parameters, the first column
    /// is the scenario name of each row. Otherwise every column maps to a parameter, in order.
    /// A set cell in the column of a parameter that does not take a set is a value set: the row
    /// gives one test case for each element, and the first column changes slowest (SPEC 3.5).
    public static func make(table: String, parameters: [TableParameter], source: TableSource) throws -> [TableTestRow] {
        let parsed = try TableParser.parse(table)
        let layout: ColumnLayout
        do {
            layout = try parsed.columnLayout(parameterCount: parameters.count)
        } catch {
            throw TableTestError(kind: error.kind == .columnCount ? .columnCount : .rowWidth, description: error.message)
        }
        let leading = layout.leadingColumns
        let headers = parsed.headers.dropFirst(leading).map(\.tableText)
        return try parsed.rows.enumerated().flatMap { offset, row in
            let cells = row.cells.dropFirst(leading).map { cell in
                TableTestRow.Cell(value: cell.value, location: source.location(line: row.line, column: cell.column))
            }
            let choices = try cells.enumerated().map { column, cell in
                try choicesOf(cell, parameter: parameters[column], header: headers[column], row: offset + 1)
            }
            return combinations(of: choices).enumerated().map { caseOffset, combination in
                TableTestRow(
                    index: offset + 1,
                    caseNumber: caseOffset + 1,
                    scenario: layout == .scenarioFirst ? row.cells[0].value.scenarioName : nil,
                    headers: headers,
                    cells: combination.map(\.cell),
                    expandedValues: zip(headers, combination)
                        .filter { $1.isExpanded }
                        .map { header, choice in "\(header) = \(choice.cell.value.tableText)" }
                )
            }
        }
    }

    /// One choice of a cell in a test case: the cell itself, or one element of its value set.
    private struct Choice {
        let cell: TableTestRow.Cell
        let isExpanded: Bool
    }

    private static func choicesOf(
        _ cell: TableTestRow.Cell,
        parameter: TableParameter,
        header: String,
        row: Int
    ) throws -> [Choice] {
        guard case .set(let elements) = cell.value, !parameter.takesSet else {
            return [Choice(cell: cell, isExpanded: false)]
        }
        guard !elements.isEmpty else {
            throw TableTestError(
                kind: .emptyValueSet,
                description: "Row \(row), column '\(header)': the value set is empty, so the row would give no "
                    + "test case. A value set needs at least one value; use a blank cell for null"
            )
        }
        return elements.map { Choice(cell: TableTestRow.Cell(value: $0, location: cell.location), isExpanded: true) }
    }

    /// Every combination of one choice from each column, with the first column changing slowest.
    private static func combinations(of choices: [[Choice]]) -> [[Choice]] {
        choices.reduce([[]]) { partial, column in
            partial.flatMap { prefix in column.map { prefix + [$0] } }
        }
    }
}

/// One data row of a table: one test case of the generated Swift Testing test.
public struct TableTestRow: Sendable, CustomTestStringConvertible, CustomTestArgumentEncodable {
    struct Cell: Sendable {
        let value: TableValue
        let location: SourceLocation
    }

    /// The 1-based number of the row among the data rows.
    public let index: Int
    /// The 1-based number of the test case among the cases of its row.
    public let caseNumber: Int
    let scenario: String?
    let headers: [String]
    let cells: [Cell]
    /// `header = element` for each column whose value set gave this case an element.
    let expandedValues: [String]

    /// The scenario name, followed by the expanded values in parentheses, or the cells of the
    /// case when the table has no scenario column (SPEC 3.4).
    public var testDescription: String {
        guard let scenario else {
            return cells.map(\.value.tableText).joined(separator: " | ")
        }
        return expandedValues.isEmpty ? scenario : "\(scenario) (\(expandedValues.joined(separator: ", ")))"
    }

    /// The row number and the case number, which identify the case when Xcode reruns it.
    public func encodeTestArgument(to encoder: some Encoder) throws {
        var container = encoder.unkeyedContainer()
        try container.encode(index)
        try container.encode(caseNumber)
    }

    /// The source location of the row's first parameter cell.
    public var sourceLocation: SourceLocation? {
        cells.first?.location
    }

    public func decode<T: Decodable>(_ column: Int, as type: T.Type) throws(TableCellError) -> T {
        try converting(column) { try TableValueDecoding.decode($0, as: T.self) }
    }

    /// Converts a cell to a raw-value enum, an enum with no raw value, or a collection of them.
    public func decode<T>(_ column: Int, as type: T.Type) throws(TableCellError) -> T {
        try converting(column) { try TableValueDecoding.convert($0, to: T.self) }
    }

    public func decode<T: TableValueDecodable>(_ column: Int, as type: T.Type) throws(TableCellError) -> T {
        try converting(column) { try TableValueDecoding.decode($0, as: T.self) }
    }

    public func decode<T: Decodable & TableValueDecodable>(_ column: Int, as type: T.Type) throws(TableCellError) -> T {
        try converting(column) { try TableValueDecoding.decode($0, as: T.self) }
    }

    private func converting<T>(_ column: Int, _ conversion: (TableValue) throws -> T) throws(TableCellError) -> T {
        do {
            return try conversion(cells[column].value)
        } catch {
            throw TableCellError(
                column: headers[column],
                row: index,
                reason: TableValueDecoding.message(of: error),
                sourceLocation: cells[column].location
            )
        }
    }
}

/// A cell that does not convert to the type of its parameter.
public struct TableCellError: Error, CustomStringConvertible, Sendable {
    /// The header of the cell's column.
    public let column: String
    /// The 1-based number of the cell's row among the data rows.
    public let row: Int
    public let reason: String
    /// Where the cell is in the source.
    public let sourceLocation: SourceLocation

    public var description: String {
        "Row \(row), column '\(column)': \(reason)"
    }
}

extension TableValue {
    /// The text of a scenario cell, or `nil` for a blank one.
    fileprivate var scenarioName: String? {
        self == .null ? nil : tableText
    }
}
