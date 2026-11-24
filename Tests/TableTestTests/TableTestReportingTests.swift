import Foundation
import TableTestManifest
import TableTestParser
import Testing
@testable import TableTest

/// The manifest that the companion test attaches in a reporting build.
@Suite("Manifest of a table")
struct TableTestReportingTests {
    private static let source = TableSource(
        fileID: "Module/YearTests.swift", filePath: "/src/YearTests.swift",
        line: 10, column: 20, indentation: 4, isMultiline: true
    )

    @Test("Gives each cell the roles that its column and its value have")
    func givesEachCellItsRoles() throws {
        let manifest = try TableTestReporting.manifest(
            table: """
                Scenario | Year         | Leap?
                Check    | {2004, 1900} | true
                Check    | {2004}       | false
                """,
            parameters: [TableParameter(Int.self), TableParameter(Bool.self)],
            source: Self.source, suite: ["Module", "YearTests"], methodName: "knowsALeapYear", title: "Leap years"
        )

        #expect(manifest == ReportManifest(
            suite: ["Module", "YearTests"], methodName: "knowsALeapYear", title: "Leap years",
            testFunction: "scenarios(_:)",
            headers: [
                ReportCell(value: .string("Scenario"), roles: ["scenario"]),
                ReportCell(value: .string("Year"), roles: []),
                ReportCell(value: .string("Leap?"), roles: ["expectation"]),
            ],
            rows: [
                ReportRow(index: 1, cells: [
                    ReportCell(value: .string("Check"), roles: ["scenario"]),
                    ReportCell(value: .set([.string("2004"), .string("1900")]), roles: ["value-set"]),
                    ReportCell(value: .string("true"), roles: ["expectation"]),
                ], cases: [
                    ReportCase(number: 1, displayName: "Check (Year = 2004) [1.1]"),
                    ReportCase(number: 2, displayName: "Check (Year = 1900)"),
                ]),
                ReportRow(index: 2, cells: [
                    ReportCell(value: .string("Check"), roles: ["scenario"]),
                    ReportCell(value: .set([.string("2004")]), roles: ["value-set"]),
                    ReportCell(value: .string("false"), roles: ["expectation"]),
                ], cases: [
                    ReportCase(number: 1, displayName: "Check (Year = 2004) [2.1]"),
                ]),
            ]
        ))
    }

    @Test("Keeps a set whole for a parameter that takes a set")
    func keepsASetWhole() throws {
        let manifest = try TableTestReporting.manifest(
            table: "Years\n{2004, 1900}",
            parameters: [TableParameter(Set<Int>.self)],
            source: Self.source, suite: ["Module", "YearTests"], methodName: "readsYears", title: "readsYears"
        )

        #expect(manifest.rows.map(\.cells) == [[ReportCell(value: .set([.string("2004"), .string("1900")]), roles: [])]])
        #expect(manifest.rows.map(\.cases) == [[ReportCase(number: 1, displayName: "{2004, 1900}")]])
    }

    @Test("Puts the error of a row that does not expand in place of its cases")
    func recordsARowThatDoesNotExpand() throws {
        let manifest = try TableTestReporting.manifest(
            table: "Year\n2004\n{}",
            parameters: [TableParameter(Int.self)],
            source: Self.source, suite: ["Module", "YearTests"], methodName: "knowsALeapYear", title: "knowsALeapYear"
        )

        #expect(manifest.rows.map(\.cases) == [[ReportCase(number: 1, displayName: "2004")], []])
        #expect(manifest.rows.map { $0.expansionError != nil } == [false, true])
    }
}
