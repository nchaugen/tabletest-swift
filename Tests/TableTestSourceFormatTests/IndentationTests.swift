import Foundation
import Testing
@testable import TableTestSourceFormat

/// Where a table in a `.swift` file takes its indent level from: `.editorconfig`, which Xcode 16
/// and the JVM formatter read; else the nearest `.swift-format`, the configuration of Apple's
/// swift-format; else 4 spaces. Each row writes its configuration files into a new temporary
/// directory, and asks for the file at the given path inside it.
@Suite("Indentation")
struct IndentationTests {
    @Test("Reads the indent level that .editorconfig sets for the file", arguments: [
        (scenario: "Spaces for every file", files: [".editorconfig": "[*]\nindent_style = space\nindent_size = 2"],
         file: "Sources/A.swift", indentation: Indentation(style: .spaces, size: 2)),
        (scenario: "A section for Swift files", files: [".editorconfig": "[*]\nindent_size = 8\n[*.swift]\nindent_size = 3"],
         file: "A.swift", indentation: Indentation(style: .spaces, size: 3)),
        (scenario: "A section for other files", files: [".editorconfig": "[*.java]\nindent_size = 2"],
         file: "A.swift", indentation: Indentation(style: .spaces, size: 4)),
        (scenario: "A glob over directories", files: [".editorconfig": "[Tests/**.swift]\nindent_size = 6"],
         file: "Tests/Unit/A.swift", indentation: Indentation(style: .spaces, size: 6)),
        (scenario: "A glob with a path matches from its own directory", files: [".editorconfig": "[Tests/*.swift]\nindent_size = 6"],
         file: "Other/Tests/A.swift", indentation: Indentation(style: .spaces, size: 4)),
        (scenario: "A choice of names", files: [".editorconfig": "[*.{kt,swift}]\nindent_size = 5"],
         file: "A.swift", indentation: Indentation(style: .spaces, size: 5)),
        (scenario: "Tabs with no size", files: [".editorconfig": "[*]\nindent_style = tab"],
         file: "A.swift", indentation: Indentation(style: .tabs, size: 1)),
        (scenario: "Tabs counted by size", files: [".editorconfig": "[*]\nindent_style = tab\nindent_size = 2"],
         file: "A.swift", indentation: Indentation(style: .tabs, size: 2)),
        (scenario: "A size of one tab width", files: [".editorconfig": "[*]\nindent_size = tab\ntab_width = 3"],
         file: "A.swift", indentation: Indentation(style: .spaces, size: 3)),
        (scenario: "A nearer file wins", files: [".editorconfig": "[*]\nindent_size = 2", "Sources/.editorconfig": "[*]\nindent_size = 6"],
         file: "Sources/A.swift", indentation: Indentation(style: .spaces, size: 6)),
        (scenario: "A root file stops the search", files: [".editorconfig": "[*]\nindent_style = tab", "Sources/.editorconfig": "root = true\n[*]\nindent_size = 6"],
         file: "Sources/A.swift", indentation: Indentation(style: .spaces, size: 6)),
        (scenario: "Comments and capitals", files: [".editorconfig": "# style\n; more\n[*]\nINDENT_STYLE = Space\nindent_size = 2"],
         file: "A.swift", indentation: Indentation(style: .spaces, size: 2)),
    ])
    func readsEditorConfig(scenario: String, files: [String: String], file: String, indentation: Indentation) throws {
        let directory = try TemporaryDirectory(files: files)

        #expect(Indentation.forSwiftFile(at: directory.url(of: file)) == indentation)
    }

    @Test("Reads the indent level of swift-format when .editorconfig sets none", arguments: [
        (scenario: "Spaces", files: [".swift-format": #"{"indentation": {"spaces": 2}}"#],
         indentation: Indentation(style: .spaces, size: 2)),
        (scenario: "Tabs", files: [".swift-format": #"{"version": 1, "indentation": {"tabs": 1}}"#],
         indentation: Indentation(style: .tabs, size: 1)),
        (scenario: "No indentation key: swift-format's default", files: [".swift-format": #"{"lineLength": 120}"#],
         indentation: Indentation(style: .spaces, size: 2)),
        (scenario: "An .editorconfig without indentation", files: [".editorconfig": "[*]\ncharset = utf-8", ".swift-format": #"{"indentation": {"spaces": 3}}"#],
         indentation: Indentation(style: .spaces, size: 3)),
        (scenario: "An .editorconfig with indentation comes first", files: [".editorconfig": "[*]\nindent_size = 6", ".swift-format": #"{"indentation": {"spaces": 3}}"#],
         indentation: Indentation(style: .spaces, size: 6)),
        (scenario: "A file that does not parse", files: [".swift-format": "{indentation"],
         indentation: Indentation(style: .spaces, size: 4)),
        (scenario: "No configuration at all", files: [:],
         indentation: Indentation(style: .spaces, size: 4)),
    ])
    func readsSwiftFormat(scenario: String, files: [String: String], indentation: Indentation) throws {
        let directory = try TemporaryDirectory(files: files)

        #expect(Indentation.forSwiftFile(at: directory.url(of: "Sources/A.swift")) == indentation)
    }
}

/// A new directory with the given files, removed when the value is released.
final class TemporaryDirectory {
    let root: URL

    init(files: [String: String]) throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("tabletest-\(UUID().uuidString)")
        for (path, content) in files {
            let url = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func url(of path: String) -> URL {
        root.appendingPathComponent(path)
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }
}
