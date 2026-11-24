import Foundation

enum ReportFiles {
    static func write(_ tables: [[TableAttempt]], devices: [Device], to output: URL) throws {
        let yaml = output.appendingPathComponent("yaml", isDirectory: true)
        try FileManager.default.createDirectory(at: yaml, withIntermediateDirectories: false)
        let deviceNames = Dictionary(grouping: devices, by: \.name)
        let suites = Dictionary(grouping: tables) { $0.first?.manifest.suite ?? [] }
        var receipts: [Receipt] = []
        var suiteSlugs: Set<String> = []
        let sortedSuites = suites.keys.sorted { $0.lexicographicallyPrecedes($1) }
        for suite in sortedSuites {
            let className = suite.joined(separator: ".")
            let suiteSlug = slug(for: className, reserved: &suiteSlugs)
            let directory = yaml.appendingPathComponent(suiteSlug, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false)
            var tableSlugs: Set<String> = [suiteSlug]
            var entries: [YAML] = []
            for attempts in suites[suite, default: []] {
                guard let first = attempts.first else { continue }
                receipts.append(Receipt(
                    title: first.manifest.title, suite: suite, methodName: first.manifest.methodName,
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
            try write([
                ("className", .text(className)), ("slug", .text(suiteSlug)),
                ("title", .text(suite.last ?? className)), ("tableTests", .sequence(entries))
            ], to: directory.appendingPathComponent("TABLETEST-\(suiteSlug).yaml"))
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var data = try encoder.encode(receipts)
        data.append(contentsOf: "\n".utf8)
        try data.write(to: output.appendingPathComponent("joined-results.json"), options: .atomic)
    }

    private struct Receipt: Encodable {
        let title: String
        let suite: [String]
        let methodName: String
        let cases: [CaseOutcome]
    }

    private static func title(for attempt: TableAttempt, multiple: Bool, deviceNames: [String: [Device]]) -> String {
        guard multiple else { return attempt.manifest.title }
        let device = attempt.device
        let name = deviceNames[device.name, default: []].count > 1 ? "\(device.name) (\(device.id))" : device.name
        return "\(attempt.manifest.title) — \(name) / \(attempt.configuration.name) / \(attempt.attemptName)"
    }

    private static func table(_ attempt: TableAttempt, title: String, slug: String) throws -> [(String, YAML)] {
        let manifest = attempt.manifest
        let outcomes = attempt.outcomes
        let byRow = Dictionary(grouping: outcomes, by: \.rowIndex)
        let notes = manifest.rows.compactMap(\.expansionError) + outcomes.filter { !$0.completed }.map { outcome in
            let prefix = "\(outcome.status): \(outcome.displayName)."
            return outcome.message.map { "\(prefix) \($0)" } ?? prefix
        }
        let rows = try manifest.rows.map { row in
            let cases = byRow[row.index, default: []]
            let roles: [String]
            if cases.contains(where: \.failed) {
                roles = ["failed"]
            } else if !cases.isEmpty && cases.allSatisfy(\.completed) {
                roles = ["passed"]
            } else {
                roles = []
            }
            return try YAML.sequence(row.cells.map { try cell($0, extraRoles: roles) })
        }
        let completed = outcomes.filter(\.completed).map { outcome in
            var fields: [(String, YAML)] = [
                ("rowIndex", .number(outcome.invocationIndex)),
                ("passed", .boolean(!outcome.failed)),
                ("displayName", .text(outcome.displayName))
            ]
            if let message = outcome.message { fields.append(("errorMessage", .text(message))) }
            return YAML.mapping(fields)
        }
        var fields: [(String, YAML)] = [
            ("methodName", .text(manifest.methodName)), ("slug", .text(slug)), ("title", .text(title))
        ]
        if !notes.isEmpty { fields.append(("description", .text(notes.joined(separator: "\n")))) }
        fields.append(("headers", try .sequence(manifest.headers.map { try cell($0) })))
        fields.append(("rows", .sequence(rows)))
        fields.append(("rowResults", .sequence(completed)))
        return fields
    }

    private static func cell(_ cell: ReportCell, extraRoles: [String] = []) throws -> YAML {
        try .mapping([
            ("value", value(cell.value)),
            ("roles", .sequence((cell.roles + extraRoles).map(YAML.text)))
        ])
    }

    private static func value(_ value: ReportValue) throws -> YAML {
        switch (value.kind, value.text, value.items, value.entries) {
        case (.null, _, _, _): return .null
        case (.string, let text?, _, _): return .text(text)
        case (.list, _, let items?, _): return try .sequence(items.map(Self.value))
        case (.set, _, let items?, _): return try .set(items.map(Self.value))
        case (.map, _, _, let entries?): return try .mapping(entries.map { ($0.key, try Self.value($0.value)) })
        default: throw ExportError("Missing data for manifest cell of kind \(value.kind.rawValue).")
        }
    }

    private static func slug(for text: String, reserved: inout Set<String>) -> String {
        let cleaned = text.lowercased().replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let base = cleaned.isEmpty ? "tabletest" : cleaned
        var candidate = base
        var number = 2
        while !reserved.insert(candidate).inserted {
            candidate = "\(base)-\(number)"
            number += 1
        }
        return candidate
    }

    private static func write(_ fields: [(String, YAML)], to file: URL) throws {
        let content = try fields.map { key, value in "\(key): \(try value.rendered())\n" }.joined()
        try content.write(to: file, atomically: true, encoding: .utf8)
    }

    private indirect enum YAML {
        case text(String), number(Int), boolean(Bool), null
        case sequence([YAML]), set([YAML]), mapping([(String, YAML)])

        func rendered() throws -> String {
            switch self {
            case .text(let text): return try Self.quoted(text)
            case .number(let number): return String(number)
            case .boolean(let flag): return String(flag)
            case .null: return "null"
            case .sequence(let items): return try "[" + items.map { try $0.rendered() }.joined(separator: ", ") + "]"
            case .set(let items): return try "!!set {" + items.map { "? \(try $0.rendered()) : null" }.joined(separator: ", ") + "}"
            case .mapping(let entries):
                return try "{" + entries.map { key, value in "\(try Self.quoted(key)): \(try value.rendered())" }
                    .joined(separator: ", ") + "}"
            }
        }

        private static func quoted(_ text: String) throws -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.withoutEscapingSlashes]
            return try String(decoding: encoder.encode(text), as: UTF8.self)
                .replacingOccurrences(of: "\u{85}", with: "\\u0085")
                .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
                .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
        }
    }
}
