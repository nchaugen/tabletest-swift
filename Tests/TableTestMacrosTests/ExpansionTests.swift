import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import Testing
@testable import TableTestMacros

/// The code that `@TableTest` generates, as `swift-syntax` expands it in a test module named
/// `TestModule` and a file named `test.swift`.
@Suite("Expansion")
struct ExpansionTests {
    @Test("Names the nested test type after the function")
    func callsAnInstanceFunction() {
        assertTableTestExpansion(
            """
            struct YearTests {
                @TableTest(\"\"\"
                    Year | Leap?
                    2004 | true
                    \"\"\")
                func knowsALeapYear(year: Int, leap: Bool) {}
            }
            """,
            expandedSource: #"""
            struct YearTests {
                func knowsALeapYear(year: Int, leap: Bool) {}

                struct knowsALeapYear {
                    @Test("knowsALeapYear", arguments: try TableTestRows.make(
                    table: "Year | Leap?\n2004 | true",
                    parameters: [TableParameter((Int).self), TableParameter((Bool).self)],
                    source: TableSource(fileID: "TestModule/test.swift", filePath: "test.swift", line: 2, column: 16, indentation: 8, isMultiline: true)
                    ))
                    func scenarios(_ row: TableTestRow) async throws {
                        let suite = try await TableTestRows.suite(YearTests())
                        do throws(TableCellError) {
                            try suite.knowsALeapYear(year: row.decode(0, as: (Int).self), leap: row.decode(1, as: (Bool).self))
                        } catch {
                            Issue.record(error, sourceLocation: error.sourceLocation)
                        }
                    }
                }
            }
            """#
        )
    }

    @Test("Copies the title, traits, effects and global actor of the function")
    func copiesTitleTraitsEffectsAndActor() {
        assertTableTestExpansion(
            """
            @MainActor
            struct YearTests {
                @TableTest("Leap years", .tags(.calendar), table: \"\"\"
                    Year | Leap?
                    2004 | true
                    \"\"\")
                static func knowsALeapYear(_ year: Int, _ leap: Bool) async throws {}
            }
            """,
            expandedSource: #"""
            @MainActor
            struct YearTests {
                static func knowsALeapYear(_ year: Int, _ leap: Bool) async throws {}

                @MainActor struct __tabletest_knowsALeapYear {
                    @Test("Leap years", .tags(.calendar), arguments: try TableTestRows.make(
                    table: "Year | Leap?\n2004 | true",
                    parameters: [TableParameter((Int).self), TableParameter((Bool).self)],
                    source: TableSource(fileID: "TestModule/test.swift", filePath: "test.swift", line: 3, column: 55, indentation: 8, isMultiline: true)
                    ))
                    func scenarios(_ row: TableTestRow) async throws {
                        do {
                            try await YearTests.knowsALeapYear(row.decode(0, as: (Int).self), row.decode(1, as: (Bool).self))
                        } catch let error as TableCellError {
                            Issue.record(error, sourceLocation: error.sourceLocation)
                        }
                    }
                }
            }
            """#
        )
    }

    @Test("Names the nested test type after the title")
    func namesTheTypeAfterTheTitle() {
        assertTableTestExpansion(
            """
            struct YearTests {
                @TableTest("Leap years, by rule", table: \"\"\"
                    Year | Leap?
                    2004 | true
                    \"\"\")
                func knowsALeapYear(year: Int, leap: Bool) {}
            }
            """,
            expandedSource: #"""
            struct YearTests {
                func knowsALeapYear(year: Int, leap: Bool) {}

                struct `Leap years, by rule` {
                    @Test("Leap years, by rule", arguments: try TableTestRows.make(
                    table: "Year | Leap?\n2004 | true",
                    parameters: [TableParameter((Int).self), TableParameter((Bool).self)],
                    source: TableSource(fileID: "TestModule/test.swift", filePath: "test.swift", line: 2, column: 46, indentation: 8, isMultiline: true)
                    ))
                    func scenarios(_ row: TableTestRow) async throws {
                        let suite = try await TableTestRows.suite(YearTests())
                        do throws(TableCellError) {
                            try suite.knowsALeapYear(year: row.decode(0, as: (Int).self), leap: row.decode(1, as: (Bool).self))
                        } catch {
                            Issue.record(error, sourceLocation: error.sourceLocation)
                        }
                    }
                }
            }
            """#
        )
    }

    @Test("Names the type after the function when a type name cannot hold the title")
    func fallsBackToTheFunctionName() {
        assertTableTestExpansion(
            """
            struct YearTests {
                @TableTest("Leap years by `year`", table: \"\"\"
                    Year | Leap?
                    2004 | true
                    \"\"\")
                func knowsALeapYear(year: Int, leap: Bool) {}
            }
            """,
            expandedSource: #"""
            struct YearTests {
                func knowsALeapYear(year: Int, leap: Bool) {}

                struct knowsALeapYear {
                    @Test("Leap years by `year`", arguments: try TableTestRows.make(
                    table: "Year | Leap?\n2004 | true",
                    parameters: [TableParameter((Int).self), TableParameter((Bool).self)],
                    source: TableSource(fileID: "TestModule/test.swift", filePath: "test.swift", line: 2, column: 47, indentation: 8, isMultiline: true)
                    ))
                    func scenarios(_ row: TableTestRow) async throws {
                        let suite = try await TableTestRows.suite(YearTests())
                        do throws(TableCellError) {
                            try suite.knowsALeapYear(year: row.decode(0, as: (Int).self), leap: row.decode(1, as: (Bool).self))
                        } catch {
                            Issue.record(error, sourceLocation: error.sourceLocation)
                        }
                    }
                }
            }
            """#
        )
    }

    @Test("Takes the title from a raw identifier")
    func takesTheTitleFromARawIdentifier() {
        assertTableTestExpansion(
            """
            extension YearTests {
                @TableTest(\"\"\"
                    Year | Leap?
                    2004 | true
                    \"\"\")
                func `knows a leap year`(year: Int, leap: Bool) {}
            }
            """,
            expandedSource: #"""
            extension YearTests {
                func `knows a leap year`(year: Int, leap: Bool) {}

                struct `knows a leap year` {
                    @Test("knows a leap year", arguments: try TableTestRows.make(
                    table: "Year | Leap?\n2004 | true",
                    parameters: [TableParameter((Int).self), TableParameter((Bool).self)],
                    source: TableSource(fileID: "TestModule/test.swift", filePath: "test.swift", line: 2, column: 16, indentation: 8, isMultiline: true)
                    ))
                    func scenarios(_ row: TableTestRow) async throws {
                        let suite = try await TableTestRows.suite(YearTests())
                        do throws(TableCellError) {
                            try suite.`knows a leap year`(year: row.decode(0, as: (Int).self), leap: row.decode(1, as: (Bool).self))
                        } catch {
                            Issue.record(error, sourceLocation: error.sourceLocation)
                        }
                    }
                }
            }
            """#
        )
    }
}

func assertTableTestExpansion(
    _ originalSource: String,
    expandedSource: String,
    diagnostics: [DiagnosticSpec] = [],
    sourceLocation: SourceLocation = #_sourceLocation
) {
    assertMacroExpansion(
        originalSource,
        expandedSource: expandedSource,
        diagnostics: diagnostics,
        macroSpecs: ["TableTest": MacroSpec(type: TableTestMacro.self)],
        failureHandler: { failure in
            Issue.record(Comment(rawValue: failure.message), sourceLocation: sourceLocation)
        }
    )
}
