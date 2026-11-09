import Testing
import TableTestFormat

/// The source formatter must leave a table that does not parse exactly as it is, also its
/// indentation, so it needs to know when the text is not a table.
@Suite("Text that is not a table")
struct NotATableTests {
    @Test("Gives no formatted table for text that is not a table", arguments: [
        (scenario: "A row that does not parse", text: "a|b\n[x|y"),
        (scenario: "A row of another width", text: "a|b\nx|y|z"),
        (scenario: "Only a comment", text: "// note"),
        (scenario: "Empty text", text: ""),
    ])
    func givesNoTable(scenario: String, text: String) {
        #expect(TableFormatter.formattedTable(text) == nil)
    }

    @Test("Gives the formatted table, also when it is already formatted", arguments: [
        (text: "a|b\nx|y", formatted: "a | b\nx | y"),
        (text: "a | b\nx | y", formatted: "a | b\nx | y"),
    ])
    func givesTheTable(text: String, formatted: String) {
        #expect(TableFormatter.formattedTable(text) == formatted)
    }
}
