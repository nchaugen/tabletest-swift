import Foundation
import Testing

/// Keeps the README's Swift examples true: each one must be a copy of code in
/// `ReadmeExamples.swift`, which compiles and runs.
struct ReadmeSyncTests {
    @Test("Finds each line of a README example in the examples file", arguments: ReadmeExample.all)
    func findsEachLine(example: ReadmeExample) throws {
        let examples = try ReadmeExample.examplesFile()
        let lines = Set(examples.split(separator: "\n").map(trimmed))
        let missing = example.lines.filter { !lines.contains($0) }

        #expect(missing.isEmpty, "README lines not in ReadmeExamples.swift: \(missing)")
    }

    @Test("Finds each README table, unbroken, in the examples file", arguments: ReadmeExample.all)
    func findsEachTable(example: ReadmeExample) throws {
        let examples = try ReadmeExample.examplesFile()
            .split(separator: "\n", omittingEmptySubsequences: false).map(trimmed).joined(separator: "\n")

        for table in example.tables {
            #expect(examples.contains(table), "README table not in ReadmeExamples.swift:\n\(table)")
        }
    }
}

/// A Swift code block of the README that declares a test or a type.
struct ReadmeExample: CustomTestStringConvertible, Sendable {
    let text: String

    var testDescription: String {
        lines.first { $0.hasPrefix("func ") || $0.hasPrefix("enum ") || $0.hasPrefix("struct ") } ?? lines[0]
    }

    /// The lines of the block, without their indentation, and without blank lines.
    var lines: [String] {
        text.split(separator: "\n").map(trimmed).filter { !$0.isEmpty }
    }

    /// The text of each table literal in the block, one line for each row.
    var tables: [String] {
        let rows = text.split(separator: "\n", omittingEmptySubsequences: false).map(trimmed)
        var tables: [String] = []
        var current: [String]?
        for row in rows {
            if row.hasPrefix("@TableTest") || row.hasSuffix("table: \"\"\"") {
                current = []
            } else if row.hasPrefix("\"\"\""), let table = current {
                tables.append(table.joined(separator: "\n"))
                current = nil
            } else {
                current?.append(row)
            }
        }
        return tables
    }

    static let all: [ReadmeExample] = {
        guard let readme = try? String(contentsOf: repository.appendingPathComponent("README.md"), encoding: .utf8) else {
            return []
        }
        return readme.components(separatedBy: "```swift\n").dropFirst()
            .map { ReadmeExample(text: $0.components(separatedBy: "```").first ?? "") }
            .filter { example in ["@TableTest", "struct ", "enum ", "extension "].contains { example.text.contains($0) } }
    }()

    static func examplesFile() throws -> String {
        try String(
            contentsOf: repository.appendingPathComponent("Tests/ReadmeExamples/ReadmeExamples.swift"),
            encoding: .utf8
        )
    }

    private static let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
}

private func trimmed(_ line: Substring) -> String {
    line.trimmingCharacters(in: .whitespaces)
}
