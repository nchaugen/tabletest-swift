import Foundation
import TableTestManifest
import Testing

/// Builds the companion attachment that report exporters read in a reporting build.
public enum TableTestReporting {
    /// Records the source table and planned cases without running the test body or its traits.
    public static func recordManifest(
        table: String, parameters: [TableParameter], source: TableSource, methodName: String, title: String,
        description: String? = nil
    ) throws {
        let test = try #require(Test.current)
        let manifest = try manifest(
            table: table, parameters: parameters, source: source,
            suite: [test.id.moduleName] + test.id.nameComponents.dropLast(2), methodName: methodName, title: title,
            description: description
        )
        let data = try JSONEncoder().encode(manifest)
        Attachment.record(String(decoding: data, as: UTF8.self), named: "tabletest-manifest.json")
    }

    /// The manifest of a table: its cells with their roles, and the planned cases of each row. A
    /// row that does not expand has its error in place of its cases.
    static func manifest(
        table: String, parameters: [TableParameter], source: TableSource,
        suite: [String], methodName: String, title: String, description: String? = nil
    ) throws -> ReportManifest {
        let parsed = try TableParser.parse(table)
        let layout = try parsed.columnLayout(parameterCount: parameters.count)
        let leading = layout.leadingColumns
        let columnRoles = parsed.headers.enumerated().map { index, value -> [String] in
            if index < leading { return ["scenario"] }
            return value.tableText.hasSuffix("?") ? ["expectation"] : []
        }
        let parameterHeaders = parsed.headers.dropFirst(leading).map(\.tableText)
        let expansions = parsed.rows.enumerated().map { offset, row in
            Result {
                try TableTestRows.expand(
                    row, index: offset + 1, layout: layout, headers: parameterHeaders, parameters: parameters, source: source
                )
            }
        }
        let cases = TableTestRows.withUniqueNames(expansions.flatMap { (try? $0.get()) ?? [] })
        let casesByRow = Dictionary(grouping: cases, by: \.index)
        let rows = zip(parsed.rows, expansions).enumerated().map { offset, entry in
            let (row, expansion) = entry
            let index = offset + 1
            let cells = row.cells.enumerated().map { column, cell in
                var roles = columnRoles[column]
                if column >= leading, case .set = cell.value, !parameters[column - leading].takesSet {
                    roles.append("value-set")
                }
                return ReportCell(value: cell.value, roles: roles)
            }
            if case .failure(let error) = expansion {
                return ReportRow(index: index, cells: cells, cases: [], expansionError: String(describing: error))
            }
            return ReportRow(index: index, cells: cells, cases: casesByRow[index, default: []].map {
                ReportCase(number: $0.caseNumber, displayName: $0.testDescription)
            })
        }
        return ReportManifest(
            suite: suite, methodName: methodName, title: title, description: description, testFunction: ReportManifest.tableTestFunction,
            headers: zip(parsed.headers, columnRoles).map { ReportCell(value: $0, roles: $1) }, rows: rows
        )
    }
}
