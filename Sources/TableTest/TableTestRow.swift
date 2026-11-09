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

/// A table that does not fit the function it is attached to.
public struct TableTestError: Error, CustomStringConvertible, Sendable {
    public let description: String
}

/// Builds the test cases of a table.
public enum TableTestRows {
    /// One row for each data row of the table.
    ///
    /// When the table has one more column than the function has parameters, the first column
    /// is the scenario name of each row. Otherwise every column maps to a parameter, in order.
    public static func make(table: String, parameterCount: Int, source: TableSource) throws -> [TableTestRow] {
        let parsed = try TableParser.parse(table)
        let hasScenario = try hasScenarioColumn(parsed, parameterCount: parameterCount)
        try refuseRowsOfAnotherWidth(parsed)
        let parameterHeaders = parsed.headers.dropFirst(hasScenario ? 1 : 0).map(\.tableText)
        return parsed.rows.enumerated().map { offset, row in
            TableTestRow(
                index: offset + 1,
                scenario: hasScenario ? row.cells[0].value.scenarioName : nil,
                headers: parameterHeaders,
                cells: Array(row.cells.dropFirst(hasScenario ? 1 : 0)).map { cell in
                    TableTestRow.Cell(
                        value: cell.value,
                        location: source.location(line: row.line, column: cell.column)
                    )
                }
            )
        }
    }

    private static func hasScenarioColumn(_ table: Table, parameterCount: Int) throws -> Bool {
        switch table.header.cells.count {
        case parameterCount: return false
        case parameterCount + 1: return true
        default:
            throw TableTestError(
                description: "The table has \(table.header.cells.count) columns, but the function has "
                    + "\(parameterCount) parameters: give it one parameter for each column, or for each "
                    + "column after a scenario column"
            )
        }
    }

    private static func refuseRowsOfAnotherWidth(_ table: Table) throws {
        let width = table.header.cells.count
        guard let offset = table.rows.firstIndex(where: { $0.cells.count != width }) else {
            return
        }
        throw TableTestError(
            description: "Row \(offset + 1) has \(table.rows[offset].cells.count) cells, but the header has \(width)"
        )
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
    let scenario: String?
    let headers: [String]
    let cells: [Cell]

    /// The scenario name, or the cells of the row when the table has no scenario column.
    public var testDescription: String {
        scenario ?? cells.map(\.value.tableText).joined(separator: " | ")
    }

    /// The row number, which identifies the row when Xcode reruns one test case.
    public func encodeTestArgument(to encoder: some Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(index)
    }

    /// The source location of the row's first parameter cell.
    public var sourceLocation: SourceLocation? {
        cells.first?.location
    }

    public func decode<T: Decodable>(_ column: Int, as type: T.Type) throws(TableCellError) -> T {
        try converting(column) { try TableValueDecoding.decode($0, as: T.self) }
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
