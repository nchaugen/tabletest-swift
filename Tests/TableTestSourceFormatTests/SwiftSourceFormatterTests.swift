import Testing
import TableTestSourceFormat

/// Formats each `@TableTest` table in Swift source as the JVM formatter does in Java: each table
/// line is trimmed and formatted, then the rows, the comment lines and the closing `"""` are
/// indented one level past the line where `@TableTest` starts. Blank lines stay empty. A table
/// that is not a table, and a literal whose source text is not its value, stay as written.
@Suite("Swift source")
struct SwiftSourceFormatterTests {
    @Test("Indents a table one level past its @TableTest line", arguments: [
        (scenario: "An indented table, four spaces", indentation: Indentation(style: .spaces, size: 4),
         source: #"""
            struct T {
                @TableTest("""
                a|b
                        x|y
                  """)
                func f(a: Int, b: Int) {}
            }
            """#,
         formatted: #"""
            struct T {
                @TableTest("""
                    a | b
                    x | y
                    """)
                func f(a: Int, b: Int) {}
            }
            """#),
        (scenario: "A title and traits", indentation: Indentation(style: .spaces, size: 4),
         source: #"""
                @TableTest("Leap years", .tags(.calendar), table: """
                Year|Leap?
                2024|true
                """)
            """#,
         formatted: #"""
                @TableTest("Leap years", .tags(.calendar), table: """
                    Year | Leap?
                    2024 | true
                    """)
            """#),
        (scenario: "A tab before the @TableTest line stays a tab", indentation: Indentation(style: .spaces, size: 2),
         source: "\t@TableTest(\"\"\"\n\ta|b\n\t\"\"\")\n",
         formatted: "\t@TableTest(\"\"\"\n\t  a | b\n\t  \"\"\")\n"),
        (scenario: "Tab style", indentation: Indentation(style: .tabs, size: 1),
         source: "    @TableTest(\"\"\"\n    a|b\n    \"\"\")\n",
         formatted: "    @TableTest(\"\"\"\n    \ta | b\n    \t\"\"\")\n"),
        (scenario: "Indent size zero", indentation: Indentation(style: .spaces, size: 0),
         source: "    @TableTest(\"\"\"\n        a|b\n        \"\"\")\n",
         formatted: "    @TableTest(\"\"\"\n    a | b\n    \"\"\")\n"),
        (scenario: "A raw string", indentation: Indentation(style: .spaces, size: 4),
         source: "    @TableTest(#\"\"\"\n    a|b\n    \"\"\"#)\n",
         formatted: "    @TableTest(#\"\"\"\n        a | b\n        \"\"\"#)\n"),
        (scenario: "Comment and blank lines", indentation: Indentation(style: .spaces, size: 4),
         source: #"""
                @TableTest("""
                a|b
                  // note

                x|y
                """)
            """#,
         formatted: #"""
                @TableTest("""
                    a | b
                    // note

                    x | y
                    """)
            """#),
        (scenario: "Two tables", indentation: Indentation(style: .spaces, size: 4),
         source: #"""
                @TableTest("""
                a|b
                """)
                func f(a: Int, b: Int) {}
                @TableTest("""
                long|c
                """)
                func g(long: Int, c: Int) {}
            """#,
         formatted: #"""
                @TableTest("""
                    a | b
                    """)
                func f(a: Int, b: Int) {}
                @TableTest("""
                    long | c
                    """)
                func g(long: Int, c: Int) {}
            """#),
        (scenario: "CRLF line endings", indentation: Indentation(style: .spaces, size: 4),
         source: "@TableTest(\"\"\"\r\na|b\r\nx|yy\r\n\"\"\")\r\nfunc f() {}\r\n",
         formatted: "@TableTest(\"\"\"\r\n    a | b\r\n    x | yy\r\n    \"\"\")\r\nfunc f() {}\r\n"),
    ])
    func indentsATable(scenario: String, indentation: Indentation, source: String, formatted: String) {
        #expect(SwiftSourceFormatter.format(source, indentation: indentation) == formatted)
    }

    @Test("Leaves source unchanged where it is not a plain table literal", arguments: [
        (scenario: "Already formatted", source: #"""
                @TableTest("""
                    a | b
                    x | y
                    """)
            """#),
        (scenario: "A table that does not parse", source: #"""
                @TableTest("""
                  a|b
                x|y|z
                """)
            """#),
        (scenario: "An interpolation", source: #"""
                @TableTest("""
                a|\(b)
                """)
            """#),
        (scenario: "An escape", source: #"""
                @TableTest("""
                a|b\tc
                """)
            """#),
        (scenario: "A one-line literal", source: #"""
                @TableTest("a|b\nx|y")
            """#),
        (scenario: "Another attribute", source: #"""
                @Test("""
                a|b
                """)
            """#),
        (scenario: "Source that does not parse as Swift around the table", source: #"""
                let x = """
                a|b
                """
            """#),
    ])
    func leavesSourceUnchanged(scenario: String, source: String) {
        #expect(SwiftSourceFormatter.format(source, indentation: Indentation(style: .spaces, size: 4)) == source)
    }
}
