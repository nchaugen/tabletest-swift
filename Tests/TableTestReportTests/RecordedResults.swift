import Foundation
@testable import TableTestReport

/// The results of a bundle as `Fixtures/record.sh` recorded them.
struct RecordedResults: TestResults {
    let directory: URL
    /// The tests whose attachments the bundle leaves out, as when a run does not select them.
    var testsWithoutAttachments: Set<String> = []

    func exportManifests(to destination: URL) throws -> [AttachmentGroup] {
        try FileManager.default.copyItem(at: directory.appendingPathComponent("attachments"), to: destination)
        return try decode([AttachmentGroup].self, from: destination.appendingPathComponent("manifest.json"))
            .filter { !testsWithoutAttachments.contains($0.testIdentifier) }
    }

    func tests() throws -> TestReport {
        try decode(TestReport.self, from: directory.appendingPathComponent("tests.json"))
    }

    func testDetails(id: String) throws -> TestDetails {
        let name = String(id.unicodeScalars.map { Self.keepsInAFileName($0) ? Character($0) : "_" })
        return try decode(TestDetails.self, from: directory.appendingPathComponent("details/\(name).json"))
    }

    /// The characters that `record.sh` keeps when it names a details file after a test ID.
    private static func keepsInAFileName(_ scalar: Unicode.Scalar) -> Bool {
        ("a"..."z").contains(scalar) || ("A"..."Z").contains(scalar) || ("0"..."9").contains(scalar)
    }

    private func decode<Value: Decodable>(_ type: Value.Type, from file: URL) throws -> Value {
        try JSONDecoder().decode(type, from: Data(contentsOf: file))
    }
}
