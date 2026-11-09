import Testing
import TableTestParser

/// The written form of a cell is not part of the spec fixtures. A formatter needs it, because a
/// formatter changes only whitespace (SPEC 4.1): it prints quotes, repeated set elements and map
/// keys as written, and only the space between them changes.
@Suite("Written form")
struct WrittenFormTests {
    @Test("Keeps a cell as written, apart from the whitespace around it", arguments: [
        (scenario: "Unquoted text", cell: "  a b  ", written: WrittenValue.text("a b")),
        (scenario: "Single-quoted text", cell: "' a '", written: .text("' a '")),
        (scenario: "Double-quoted text", cell: "\"x|y\"", written: .text("\"x|y\"")),
        (scenario: "Blank cell", cell: "   ", written: .blank),
        (scenario: "Empty string", cell: "''", written: .text("''")),
        (scenario: "Unmatched quote", cell: "'abc", written: .text("'abc")),
        (scenario: "List", cell: "[ a ,'b' ]", written: .list([.text("a"), .text("'b'")])),
        (scenario: "Set with a repeated element", cell: "{a, a, 'a'}", written: .set([.text("a"), .text("a"), .text("'a'")])),
        (scenario: "Empty collections", cell: "[[], {}, [:]]", written: .list([.list([]), .set([]), .map([])])),
        (scenario: "Map with quoted keys", cell: "[ 'k' : v, \"x\": [1] ]",
         written: .map([WrittenPair(key: "'k'", value: .text("v")), WrittenPair(key: "\"x\"", value: .list([.text("1")]))])),
        (scenario: "Nested set in a map", cell: "[a: {b, b}]", written: .map([WrittenPair(key: "a", value: .set([.text("b"), .text("b")]))])),
    ])
    func keepsACellAsWritten(scenario: String, cell: String, written: WrittenValue) throws {
        let table = try TableParser.parse("Value | End\n\(cell) | end")

        #expect(table.rows[0].cells[0].written == written)
    }
}
