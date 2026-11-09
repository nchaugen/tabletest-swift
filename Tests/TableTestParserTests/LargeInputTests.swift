import Testing
import TableTestParser

/// The JVM parser once overflowed its stack on values and comments of about 15 000 characters
/// (tabletest 1.2.2). These tests hold the Swift parser to input past that size, and to deep
/// nesting, which is the one place where it recurses.
@Suite("Large input")
struct LargeInputTests {
    @Test("Parses a value of 20 000 scalars")
    func parsesALongValue() throws {
        let value = String(repeating: "x", count: 20_000)

        let table = try TableParser.parse("a\n" + value)

        #expect(table.rows[0].values == [.string(value)])
    }

    @Test("Ignores a comment line of 20 000 scalars")
    func ignoresALongComment() throws {
        let comment = "// " + String(repeating: "x", count: 20_000)

        let table = try TableParser.parse("a\n\(comment)\n1")

        #expect(table.rows.map(\.values) == [[.string("1")]])
    }

    @Test("Parses lists nested 200 levels deep")
    func parsesDeepNesting() throws {
        let depth = 200
        let cell = String(repeating: "[", count: depth) + "x" + String(repeating: "]", count: depth)
        let expected = (0..<depth).reduce(TableValue.string("x")) { inner, _ in .list([inner]) }

        let table = try TableParser.parse("a\n" + cell)

        #expect(table.rows[0].values == [expected])
    }
}
