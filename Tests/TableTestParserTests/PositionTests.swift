import Testing
import TableTestParser

/// Positions are not part of the spec fixtures. The macro needs them to point at the row and the
/// cell in the source. A line is the 0-based index of the line in the input; a column is the
/// 0-based Unicode scalar offset on the line.
@Suite("Positions")
struct PositionTests {
    @Test("Places each row at its line in the input", arguments: [
        (scenario: "No blank or comment lines", input: ["a", "1", "2"], headerLine: 0, dataLines: [1, 2]),
        (scenario: "Blank and comment lines between rows",
         input: ["// intro", "", "a", "  ", "1", "// note", "2"], headerLine: 2, dataLines: [4, 6]),
    ])
    func placesEachRowAtItsLine(scenario: String, input: [String], headerLine: Int, dataLines: [Int]) throws {
        let table = try TableParser.parse(input.joined(separator: "\n"))

        #expect(table.header.line == headerLine)
        #expect(table.rows.map(\.line) == dataLines)
    }

    @Test("Places each cell at its first character that is not whitespace", arguments: [
        (scenario: "Spaced pipes", row: "a | b | c", columns: [0, 4, 8]),
        (scenario: "Indented row and unspaced pipe", row: "  a  |b", columns: [2, 6]),
        (scenario: "A quoted pipe in the first cell", row: "'x | y' | z", columns: [0, 10]),
        (scenario: "A blank first cell", row: "| a", columns: [0, 2]),
        (scenario: "A blank last cell", row: "a |", columns: [0, 3]),
        (scenario: "A decomposed accent counts two scalars", row: "e\u{301} | x", columns: [0, 5]),
        (scenario: "An emoji counts one scalar", row: "🍷 | x", columns: [0, 4]),
    ])
    func placesEachCellAtItsFirstCharacter(scenario: String, row: String, columns: [Int]) throws {
        let table = try TableParser.parse("Field\n" + row)

        #expect(table.rows[0].cells.map(\.column) == columns)
    }

    @Test("Places each error at the row and cell that cause it", arguments: [
        (scenario: "Only a comment line", input: ["// only"],
         kind: TableParseError.Kind.noRows, line: 0, column: 0),
        (scenario: "A blank middle header", input: ["a |  | c", "1 | 2 | 3"],
         kind: .blankHeader, line: 0, column: 5),
        (scenario: "An unclosed list after a blank line", input: ["a | b", "", "1 | [x"],
         kind: .malformed, line: 2, column: 4),
        (scenario: "Text after a quote, after a quoted pipe", input: ["a | b", "'x | y' | 'z'w"],
         kind: .malformed, line: 1, column: 10),
        (scenario: "A key repeated in a map", input: ["a", "[k: 1, k: 2]"],
         kind: .duplicateKey, line: 1, column: 7),
    ])
    func placesEachError(
        scenario: String,
        input: [String],
        kind: TableParseError.Kind,
        line: Int,
        column: Int
    ) throws {
        let error = try #require(parseError(of: input.joined(separator: "\n")))

        #expect(error.kind == kind)
        #expect(error.line == line)
        #expect(error.column == column)
    }

    @Test("Names the row as written when a row does not parse", arguments: [
        (scenario: "An unclosed list", row: "1 | [x"),
        (scenario: "A key repeated in a map", row: "[k: 1, k: 2] | 2"),
    ])
    func namesTheRowAsWritten(scenario: String, row: String) throws {
        let error = try #require(parseError(of: "a | b\n   " + row))

        #expect(error.message.contains("`\(row)`"))
    }

    private func parseError(of text: String) -> TableParseError? {
        do {
            _ = try TableParser.parse(text)
            return nil
        } catch {
            return error
        }
    }
}
