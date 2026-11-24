import Foundation
import Testing
@testable import TableTestReport

@Suite("Export of a result bundle")
struct ResultBundleExportTests {
    /// The bundle comes from the examples' check-report-export.sh, recorded with `Fixtures/record.sh`.
    /// Set `TABLETEST_RECORD_EXPORT` to write the export into `Fixtures/probe-export` instead.
    @Test("Writes the YAML and outcomes of the recorded probe bundle")
    func writesTheRecordedExport() throws {
        let recorded = try #require(Bundle.module.url(forResource: "probe", withExtension: nil))
        let output = FileManager.default.temporaryDirectory
            .appendingPathComponent("tabletest-export-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: output) }

        try ResultBundleExport.run(results: RecordedResults(directory: recorded), output: output)

        if ProcessInfo.processInfo.environment["TABLETEST_RECORD_EXPORT"] != nil {
            let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
                .appendingPathComponent("Fixtures/probe-export", isDirectory: true)
            try? FileManager.default.removeItem(at: source)
            try FileManager.default.copyItem(at: output, to: source)
            Issue.record("Recorded the export in \(source.path). Unset TABLETEST_RECORD_EXPORT to compare.")
            return
        }
        let expected = try #require(Bundle.module.url(forResource: "probe-export", withExtension: nil))
        #expect(try Self.files(in: output) == Self.files(in: expected))
    }

    /// The text of each file below the directory, by its path relative to the directory.
    private static func files(in directory: URL) throws -> [String: String] {
        let root = directory.resolvingSymlinksInPath().path + "/"
        let paths = FileManager.default.enumerator(atPath: root)?.compactMap { $0 as? String } ?? []
        return try Dictionary(uniqueKeysWithValues: paths.compactMap { path in
            let file = URL(fileURLWithPath: root + path)
            guard (try file.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true else { return nil }
            return (path, try String(contentsOf: file, encoding: .utf8))
        })
    }
}
