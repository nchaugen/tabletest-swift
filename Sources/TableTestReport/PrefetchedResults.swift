import Foundation
import TableTestManifest

/// Results that fetch the details of every table test of a run at once, in parallel. Each fetch
/// is its own `xcresulttool` call of about 40 ms, so a run with a thousand tables spent over a
/// minute on them one after another.
struct PrefetchedResults<Base: TestResults>: TestResults {
    private let base: Base
    private let details: [String: Result<TestDetails, any Error>]

    init(_ base: Base, report: TestReport) {
        self.base = base
        let ids = report.testNodes.flatMap(\.descendants)
            .filter { $0.kind == .test && $0.nodeIdentifier?.hasSuffix("/" + ReportManifest.tableTestFunction) == true }
            .compactMap(\.nodeIdentifierURL)
        let fetched = Fetched(count: ids.count)
        DispatchQueue.concurrentPerform(iterations: ids.count) { index in
            fetched.store(Result { try base.testDetails(id: ids[index]) }, at: index)
        }
        details = Dictionary(zip(ids, fetched.results), uniquingKeysWith: { first, _ in first })
    }

    func exportManifests(to directory: URL) throws -> [AttachmentGroup] {
        try base.exportManifests(to: directory)
    }

    func tests() throws -> TestReport {
        try base.tests()
    }

    func testDetails(id: String) throws -> TestDetails {
        guard let fetched = details[id] else { return try base.testDetails(id: id) }
        return try fetched.get()
    }
}

/// The fetched details by position, written from many threads.
private final class Fetched: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [Result<TestDetails, any Error>?]

    init(count: Int) {
        stored = Array(repeating: nil, count: count)
    }

    var results: [Result<TestDetails, any Error>] {
        lock.withLock { stored.map { $0 ?? .failure(ExportError("The details of a table test were not fetched.")) } }
    }

    func store(_ result: Result<TestDetails, any Error>, at index: Int) {
        lock.withLock { stored[index] = result }
    }
}
