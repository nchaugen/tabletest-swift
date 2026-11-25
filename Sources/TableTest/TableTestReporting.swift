import Foundation
import TableTestManifest
import Testing

/// Builds the companion attachment that report exporters read in a reporting build.
public enum TableTestReporting {
    /// Records the source table and planned cases without running the test body or its traits.
    public static func recordManifest(
        table: String, parameters: [TableParameter], source: TableSource, methodName: String, title: String,
        description: String? = nil, suiteDescription: String? = nil
    ) throws {
        let test = try #require(Test.current)
        let manifest = try manifest(
            table: table, parameters: parameters, source: source,
            suite: [test.id.moduleName] + test.id.nameComponents.dropLast(2),
            folders: folders(ofFile: source.filePath, module: test.id.moduleName), methodName: methodName, title: title,
            description: description, suiteDescription: suiteDescription
        )
        let data = try JSONEncoder().encode(manifest)
        Attachment.record(String(decoding: data, as: UTF8.self), named: "tabletest-manifest.json")
    }

    /// The folders between the test target's folder and the file: those after the last folder
    /// that has the module's name, which SwiftPM and the Xcode templates give the target's folder.
    /// None when no folder has that name. A dot in a folder name would part it into two report
    /// levels, so it becomes a hyphen.
    static func folders(ofFile filePath: String, module: String) -> [String] {
        let folders = filePath.split(separator: "/").dropLast()
        guard let target = folders.lastIndex(where: { $0 == module }) else { return [] }
        return folders[(target + 1)...].map { $0.replacingOccurrences(of: ".", with: "-") }
    }

    /// The manifest of a table: its cells with their roles, and the planned cases of each row. A
    /// row that does not expand has its error in place of its cases.
    static func manifest(
        table: String, parameters: [TableParameter], source: TableSource,
        suite: [String], folders: [String] = [], methodName: String, title: String, description: String? = nil,
        suiteDescription: String? = nil
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
            suite: suite, folders: folders, methodName: methodName, title: title, description: description,
            suiteDescription: suiteDescription, testFunction: ReportManifest.tableTestFunction,
            headers: zip(parsed.headers, columnRoles).map { ReportCell(value: $0, roles: $1) }, rows: rows
        )
    }
}
