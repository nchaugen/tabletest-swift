import Testing

/// Runs the parse fixtures of `tabletest-spec` against ``TableParser``.
@Suite("Spec parse fixtures")
struct ParseFixtureTests {
    /// Fixture files whose rules the parser does not implement yet. Their cases run as known
    /// issues until the parser passes them.
    private static let pendingFiles: Set<String> = [
        "cells.json", "elements.json", "lists.json", "maps.json", "real-tables.json",
        "sets.json", "single-values.json", "table-structure.json",
    ]

    @Test("Finds the vendored fixture cases")
    func findsVendoredFixtureCases() throws {
        #expect(try ParseFixture.all().count > 0)
    }

    @Test("Gives the result that each fixture states", arguments: try ParseFixture.all())
    func givesTheStatedResult(_ fixture: ParseFixture) {
        withKnownIssue("The parser does not implement \(fixture.file) yet", isIntermittent: true) {
            #expect(ParseOutcome.of(fixture.inputText) == fixture.expect, "rule \(fixture.rule)")
        } when: {
            Self.pendingFiles.contains(fixture.file)
        }
    }
}
