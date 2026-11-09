import Foundation
import Testing
@testable import TableTest

/// The rows that a table gives to the generated test. Every table here is a multiline literal
/// whose opening quote is on line 10 at column 20, indented by 4 spaces, unless a case says
/// otherwise.
@Suite("Rows of a table")
struct TableTestRowsTests {
    private static let source = TableSource(
        fileID: "Module/YearTests.swift", filePath: "/src/YearTests.swift",
        line: 10, column: 20, indentation: 4, isMultiline: true
    )

    @Test("Reads the first column as the scenario when it has no parameter", arguments: [
        (scenario: "One column more than parameters", table: ["Scenario | Year", "Leap | 2004", "Common | 2001"],
         parameters: 1, names: ["Leap", "Common"], cells: [["2004"], ["2001"]]),
        (scenario: "As many columns as parameters", table: ["Year | Leap?", "2004 | true"],
         parameters: 2, names: ["2004 | true"], cells: [["2004", "true"]]),
        (scenario: "A blank scenario cell", table: ["Scenario | Year", " | 2004"],
         parameters: 1, names: ["2004"], cells: [["2004"]]),
        (scenario: "Collections and a blank cell", table: ["Values | Note | Size?", "[1, 2] |  | 2"],
         parameters: 3, names: ["[1, 2] |  | 2"], cells: [["[1, 2]", "", "2"]]),
    ])
    func readsTheScenarioColumn(
        scenario: String,
        table: [String],
        parameters: Int,
        names: [String],
        cells: [[String]]
    ) throws {
        let rows = try TableTestRows.make(table: table.joined(separator: "\n"), parameters: .values(parameters), source: Self.source)

        #expect(rows.map(\.testDescription) == names)
        #expect(rows.map { $0.cells.map(\.value.tableText) } == cells)
    }

    @Test("Places each parameter cell at its line and column in the source", arguments: [
        (scenario: "Multiline literal", isMultiline: true,
         table: ["Scenario | Year", "Leap | 2004", "", "  Common  | 2001"],
         locations: [[Position(line: 12, column: 12)], [Position(line: 14, column: 17)]]),
        (scenario: "Single-line literal", isMultiline: false,
         table: ["Scenario | Year", "Leap | 2004", "", "  Common  | 2001"],
         locations: [[Position(line: 10, column: 20)], [Position(line: 10, column: 20)]]),
    ])
    func placesEachCell(scenario: String, isMultiline: Bool, table: [String], locations: [[Position]]) throws {
        let source = TableSource(
            fileID: "Module/YearTests.swift", filePath: "/src/YearTests.swift",
            line: 10, column: 20, indentation: 4, isMultiline: isMultiline
        )

        let rows = try TableTestRows.make(table: table.joined(separator: "\n"), parameters: .values(1), source: source)

        #expect(rows.map { $0.cells.map { Position($0.location) } } == locations)
    }

    @Test("Encodes the row number as the test argument")
    func encodesTheRowNumber() throws {
        let rows = try TableTestRows.make(table: "Year\n2004\n2001\n2000", parameters: .values(1), source: Self.source)

        let encoded = try rows.map { String(decoding: try JSONEncoder().encode(EncodedArgument(row: $0)), as: UTF8.self) }

        #expect(encoded == ["1", "2", "3"])
    }

    @Test("Refuses a table that does not fit the function", arguments: [
        (scenario: "Two columns more than parameters", table: ["a | b | c", "1 | 2 | 3"], parameters: 1,
         kind: TableTestError.Kind.columnCount, message: "The table has 3 columns, but the function has 1 parameter: give it one parameter for each column, or for each column after a scenario column"),
        (scenario: "Fewer columns than parameters", table: ["a", "1"], parameters: 2,
         kind: .columnCount, message: "The table has 1 column, but the function has 2 parameters: give it one parameter for each column, or for each column after a scenario column"),
        (scenario: "A row with a missing cell", table: ["a | b", "1 | 2", "3"], parameters: 2,
         kind: .rowWidth, message: "Row 2 has 1 cell, but the header has 2"),
    ])
    func refusesATableThatDoesNotFit(
        scenario: String,
        table: [String],
        parameters: Int,
        kind: TableTestError.Kind,
        message: String
    ) {
        let error = #expect(throws: TableTestError.self) {
            try TableTestRows.make(table: table.joined(separator: "\n"), parameters: .values(parameters), source: Self.source)
        }

        #expect(error?.kind == kind)
        #expect(error?.description == message)
    }

    @Test("Reports a cell that does not convert by its row, column and position")
    func reportsACellThatDoesNotConvert() throws {
        let rows = try TableTestRows.make(table: "Scenario | Year\nLeap | 2004\nTypo | 200x", parameters: .values(1), source: Self.source)

        let error = #expect(throws: TableCellError.self) { try rows[1].decode(0, as: Int.self) }

        #expect(error?.description == "Row 2, column 'Year': Cannot convert `200x` to Int")
        #expect(error.map { Position($0.sourceLocation) } == Position(line: 13, column: 12))
    }
}

/// A line and a column, compared without the file.
struct Position: Equatable, Sendable, CustomStringConvertible {
    let line: Int
    let column: Int

    init(line: Int, column: Int) {
        self.line = line
        self.column = column
    }

    init(_ location: SourceLocation) {
        self.init(line: location.line, column: location.column)
    }

    var description: String { "\(line):\(column)" }
}

/// Encodes a row the way Swift Testing does when it identifies a test case.
struct EncodedArgument: Encodable {
    let row: TableTestRow

    func encode(to encoder: any Encoder) throws {
        try row.encodeTestArgument(to: encoder)
    }
}


extension Array where Element == TableParameter {
    /// Parameters that do not take a set.
    static func values(_ count: Int) -> [TableParameter] {
        Array(repeating: TableParameter(takesSet: false), count: count)
    }
}
