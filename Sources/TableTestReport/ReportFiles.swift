import Foundation
import TableTestManifest

enum ReportFiles {
    static func write(_ tables: [[TableAttempt]], devices: [Device], to output: URL) throws {
        let yaml = output.appendingPathComponent("yaml", isDirectory: true)
        try FileManager.default.createDirectory(at: yaml, withIntermediateDirectories: false)
        let deviceNames = Dictionary(grouping: devices, by: \.name)
        let suites = Dictionary(grouping: tables) { $0.first.map(reportPath) ?? [] }
        var tableOutcomes: [TableOutcomes] = []
        var suiteSlugs: Set<String> = []
        let sortedSuites = suites.keys.sorted { $0.lexicographicallyPrecedes($1) }
        for suite in sortedSuites {
            let className = suite.joined(separator: ".")
            let suiteTitle = title(of: suite, in: suites[suite, default: []]) ?? className
            let suiteSlug = slug(for: suiteTitle, reserved: &suiteSlugs)
            let directory = yaml.appendingPathComponent(suiteSlug, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            var tableSlugs: Set<String> = [suiteSlug]
            var entries: [YAMLValue] = []
            for attempts in suites[suite, default: []] {
                guard let first = attempts.first else { continue }
                tableOutcomes.append(TableOutcomes(
                    title: first.manifest.title, suite: first.manifest.suite, methodName: first.manifest.methodName,
                    cases: attempts.flatMap(\.outcomes)
                ))
                for attempt in attempts {
                    let title = title(for: attempt, multiple: attempts.count > 1, deviceNames: deviceNames)
                    let tableSlug = slug(for: title, reserved: &tableSlugs)
                    let filename = "TABLETEST-\(tableSlug).yaml"
                    try write(table(attempt, title: title, slug: tableSlug), to: directory.appendingPathComponent(filename))
                    entries.append(.mapping([
                        ("path", .text(filename)), ("methodName", .text(attempt.manifest.methodName)), ("slug", .text(tableSlug))
                    ]))
                }
            }
            var suiteFields: [(String, YAMLValue)] = [
                ("className", .text(className)), ("slug", .text(suiteSlug)), ("title", .text(suiteTitle))
            ]
            if let description = description(of: suites[suite, default: []]) {
                suiteFields.append(("description", .text(description)))
            }
            suiteFields.append(("tableTests", .sequence(entries)))
            try write(suiteFields, to: directory.appendingPathComponent("TABLETEST-\(suiteSlug).yaml"))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(tableOutcomes)
        data.append(contentsOf: "\n".utf8)
        try data.write(to: output.appendingPathComponent("joined-results.json"), options: .atomic)
    }

    /// The outcomes of the cases of one table, as `joined-results.json` lists them.
    private struct TableOutcomes: Encodable {
        let title: String
        let suite: [String]
        let methodName: String
        let cases: [CaseOutcome]
    }

    /// Where a table's suite sits in the report: its module, the folders of its file, and its
    /// types. The reporter makes a level of each.
    private static func reportPath(of attempt: TableAttempt) -> [String] {
        let suite = attempt.manifest.suite
        return Array(suite.prefix(1)) + attempt.manifest.folders + suite.dropFirst()
    }

    private static func title(of suite: [String], in tables: [[TableAttempt]]) -> String? {
        tables.lazy.compactMap { $0.first?.suiteTitle }.first ?? suite.last
    }

    /// The doc comment of a suite, from the first of its tables that sits in the type itself.
    private static func description(of tables: [[TableAttempt]]) -> String? {
        tables.lazy.compactMap { $0.first?.manifest.suiteDescription }.first
    }

    private static func title(for attempt: TableAttempt, multiple: Bool, deviceNames: [String: [Device]]) -> String {
        guard multiple else { return attempt.manifest.title }
        let device = attempt.device
        let name = deviceNames[device.name, default: []].count > 1 ? "\(device.name) (\(device.id))" : device.name
        return "\(attempt.manifest.title) — \(name) / \(attempt.configuration.name) / \(attempt.attemptName)"
    }

    private static func table(_ attempt: TableAttempt, title: String, slug: String) throws -> [(String, YAMLValue)] {
        let manifest = attempt.manifest
        let outcomes = attempt.outcomes
        let byRow = Dictionary(grouping: outcomes, by: \.rowIndex)
        let notes = manifest.rows.compactMap(\.expansionError) + outcomes.filter { !$0.completed }.map { outcome in
            let prefix = "\(outcome.status.rawValue): \(outcome.displayName)."
            return outcome.message.map { "\(prefix) \($0)" } ?? prefix
        }
        let rows = manifest.rows.map { row in
            let cases = byRow[row.index, default: []]
            let roles: [String]
            if cases.contains(where: \.failed) {
                roles = ["failed"]
            } else if !cases.isEmpty && cases.allSatisfy(\.completed) {
                roles = ["passed"]
            } else {
                roles = []
            }
            return YAMLValue.sequence(row.cells.map { cell($0, extraRoles: roles) })
        }
        let completed = outcomes.filter(\.completed).map { outcome in
            var fields: [(String, YAMLValue)] = [
                ("rowIndex", .number(outcome.invocationIndex)),
                ("passed", .boolean(!outcome.failed)),
                ("displayName", .text(outcome.displayName))
            ]
            if let message = outcome.message { fields.append(("errorMessage", .text(message))) }
            return YAMLValue.mapping(fields)
        }
        var fields: [(String, YAMLValue)] = [
            ("methodName", .text(manifest.methodName)), ("slug", .text(slug)), ("title", .text(title))
        ]
        let description = [manifest.description, notes.isEmpty ? nil : notes.joined(separator: "\n")]
            .compactMap { $0 }.joined(separator: "\n\n")
        if !description.isEmpty { fields.append(("description", .text(description))) }
        fields.append(("headers", .sequence(manifest.headers.map { cell($0) })))
        fields.append(("rows", .sequence(rows)))
        fields.append(("rowResults", .sequence(completed)))
        return fields
    }

    private static func cell(_ cell: ReportCell, extraRoles: [String] = []) -> YAMLValue {
        .mapping([
            ("value", value(cell.value)),
            ("roles", .sequence((cell.roles + extraRoles).map(YAMLValue.text)))
        ])
    }

    private static func value(_ value: ReportValue) -> YAMLValue {
        switch value {
        case .null: .null
        case .string(let text): .text(text)
        case .list(let items): .sequence(items.map(Self.value))
        case .set(let items): .set(items.map(Self.value))
        case .map(let entries): .mapping(entries.map { ($0.key, Self.value($0.value)) })
        }
    }

    private static func slug(for text: String, reserved: inout Set<String>) -> String {
        let slug = Slug.of(text)
        let base = slug.isEmpty ? "tabletest" : slug
        var candidate = base
        var number = 2
        while !reserved.insert(candidate).inserted {
            candidate = "\(base)-\(number)"
            number += 1
        }
        return candidate
    }

    private static func write(_ fields: [(String, YAMLValue)], to file: URL) throws {
        let content = try fields.map { key, value in "\(key): \(try value.rendered())\n" }.joined()
        try content.write(to: file, atomically: true, encoding: .utf8)
    }
}
