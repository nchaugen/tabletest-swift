import Foundation
import TableTestManifest
import Testing
@testable import TableTestReport

@Suite("Test details fetched ahead")
struct PrefetchedResultsTests {
    @Test("Asks once for the details of each table test, before the export reads them")
    func asksOnceForEachTableTest() throws {
        let probe = try #require(Bundle.module.url(forResource: "probe", withExtension: nil))
        let counting = CountingResults(base: RecordedResults(directory: probe))
        let report = try counting.tests()
        let tableTests = report.testNodes.flatMap(\.descendants)
            .filter { $0.nodeIdentifier?.hasSuffix("/" + ReportManifest.tableTestFunction) == true }
            .compactMap(\.nodeIdentifierURL)

        let results = PrefetchedResults(counting, report: report)
        for id in tableTests + tableTests {
            _ = try results.testDetails(id: id)
        }

        #expect(!tableTests.isEmpty)
        #expect(counting.calls == Dictionary(uniqueKeysWithValues: tableTests.map { ($0, 1) }))
    }
}

/// Results that count the details calls by test, from any thread.
private final class CountingResults: TestResults, @unchecked Sendable {
    let base: RecordedResults
    private let lock = NSLock()
    private var counts: [String: Int] = [:]

    init(base: RecordedResults) {
        self.base = base
    }

    var calls: [String: Int] { lock.withLock { counts } }

    func exportManifests(to directory: URL) throws -> [AttachmentGroup] { try base.exportManifests(to: directory) }

    func tests() throws -> TestReport { try base.tests() }

    func testDetails(id: String) throws -> TestDetails {
        lock.withLock { counts[id, default: 0] += 1 }
        return try base.testDetails(id: id)
    }
}
