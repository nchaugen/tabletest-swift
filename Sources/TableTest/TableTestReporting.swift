import Foundation
import TableTestManifest
import Testing

/// Builds the companion attachment that report exporters read in a reporting build.
public enum TableTestReporting {
    /// The name of the generated test function that runs the cases of a table.
    static let testFunction = "scenarios(_:)"

    /// Records the source table and planned cases without running the test body or its traits.
    public static func recordManifest(
        table: String, parameters: [TableParameter], source: TableSource, methodName: String, title: String
    ) throws {
        let test = try #require(Test.current)
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
        let manifest = ReportManifest(
            suite: [test.id.moduleName] + test.id.nameComponents.dropLast(2), methodName: methodName, title: title,
            testFunction: testFunction,
            headers: zip(parsed.headers, columnRoles).map { ReportCell(value: $0, roles: $1) }, rows: rows
        )
        let data = try JSONEncoder().encode(manifest)
        Attachment.record(String(decoding: data, as: UTF8.self), named: "tabletest-manifest.json")
    }
}
