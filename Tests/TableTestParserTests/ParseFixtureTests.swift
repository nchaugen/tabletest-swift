import Testing

/// Runs the parse fixtures of `tabletest-spec` against ``TableParser``.
@Suite("Spec parse fixtures")
struct ParseFixtureTests {
    @Test("Finds the vendored fixture cases")
    func findsVendoredFixtureCases() throws {
        #expect(try ParseFixture.all().count > 0)
    }

    @Test("Gives the result that each fixture states", arguments: try ParseFixture.all())
    func givesTheStatedResult(_ fixture: ParseFixture) {
        #expect(ParseOutcome.of(fixture.inputText) == fixture.expect, "rule \(fixture.rule)")
    }
}
