import SwiftSyntaxMacrosGenericTestSupport
import Testing
@testable import TableTestMacros

/// The compile-time errors of `@TableTest`. An error in the table points at the start of the row
/// that causes it: the compiler places a macro diagnostic at the start of a syntax node, and a
/// line of a multiline literal is the smallest node inside the table. The message names the
/// cell.
@Suite("Diagnostics")
struct DiagnosticTests {
    @Test("Reports an error at the cause in the source", arguments: [
        (scenario: "Attached to a property",
         source: """
            struct YearTests {
                @TableTest(\"\"\"
                    Year
                    2004
                    \"\"\")
                var year = 2004
            }
            """,
         expanded: """
            struct YearTests {
                var year = 2004
            }
            """,
         message: "@TableTest applies only to a function", line: 2, column: 5),
        (scenario: "A function at file scope",
         source: """
            @TableTest(\"\"\"
                Year
                2004
                \"\"\")
            func knowsALeapYear(year: Int) {}
            """,
         expanded: """
            func knowsALeapYear(year: Int) {}
            """,
         message: "@TableTest applies only to a function inside a type: the generated test calls it through the type",
         line: 1, column: 1),
        (scenario: "A table that is not a literal",
         source: """
            struct YearTests {
                @TableTest(yearTable)
                func knowsALeapYear(year: Int) {}
            }
            """,
         expanded: """
            struct YearTests {
                func knowsALeapYear(year: Int) {}
            }
            """,
         message: "@TableTest needs the table as a string literal, so that it can check the table at compile time",
         line: 2, column: 16),
        (scenario: "A table with interpolation",
         source: """
            struct YearTests {
                @TableTest(\"\"\"
                    Year
                    \\(year)
                    \"\"\")
                func knowsALeapYear(year: Int) {}
            }
            """,
         expanded: """
            struct YearTests {
                func knowsALeapYear(year: Int) {}
            }
            """,
         message: "@TableTest needs a table without string interpolation", line: 4, column: 9),
        (scenario: "A cell that does not parse, after a comment line",
         source: """
            struct IslandTests {
                @TableTest(\"\"\"
                    Island | Leap?
                    // Danish islands
                    Ærø    | [true
                    \"\"\")
                func knowsAnIsland(island: String, leap: Bool) {}
            }
            """,
         expanded: """
            struct IslandTests {
                func knowsAnIsland(island: String, leap: Bool) {}
            }
            """,
         message: "Failed to parse `[true` in row `Ærø    | [true`", line: 5, column: 9),
        (scenario: "More columns than parameters and a scenario column",
         source: """
            struct YearTests {
                @TableTest(\"\"\"
                    Year | Leap? | Note
                    2004 | true  | common
                    \"\"\")
                func knowsALeapYear(year: Int) {}
            }
            """,
         expanded: """
            struct YearTests {
                func knowsALeapYear(year: Int) {}
            }
            """,
         message: "The table has 3 columns, but the function has 1 parameter: give it one parameter for each column, or for each column after a scenario column",
         line: 3, column: 9),
        (scenario: "A row with a missing cell",
         source: """
            struct YearTests {
                @TableTest(\"\"\"
                    Year | Leap?
                    2004 | true
                    2001
                    \"\"\")
                func knowsALeapYear(year: Int, leap: Bool) {}
            }
            """,
         expanded: """
            struct YearTests {
                func knowsALeapYear(year: Int, leap: Bool) {}
            }
            """,
         message: "Row 2 has 1 cell, but the header has 2", line: 5, column: 9),
    ])
    func reportsAnErrorAtItsCause(
        scenario: String,
        source: String,
        expanded: String,
        message: String,
        line: Int,
        column: Int
    ) {
        assertTableTestExpansion(
            source,
            expandedSource: expanded,
            diagnostics: [DiagnosticSpec(message: message, line: line, column: column)]
        )
    }
}
