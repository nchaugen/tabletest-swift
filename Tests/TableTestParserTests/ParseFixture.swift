import Foundation
import Testing

/// One parse fixture case of `tabletest-spec`: the table text and the result the parser must give.
struct ParseFixture: Sendable, Decodable, CustomTestStringConvertible {
    /// The fixture file the case comes from, set after decoding.
    var file = ""
    let name: String
    let rule: String
    let input: [String]
    let expect: ParseOutcome

    private enum CodingKeys: String, CodingKey {
        case name, rule, input, expect
    }

    /// The table text: the input lines joined with a line feed.
    var inputText: String {
        input.joined(separator: "\n")
    }

    var testDescription: String {
        "\(file) › \(name)"
    }

    /// Every case of every vendored fixture file, in file and case order.
    ///
    /// Throws when the fixture directory is missing or holds no file, so that zero cases is
    /// never a pass.
    static func all() throws -> [ParseFixture] {
        guard let directory = Bundle.module.url(forResource: "parse", withExtension: nil, subdirectory: "Fixtures")
        else {
            throw FixtureError("The test bundle has no Fixtures/parse directory")
        }
        let files = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else {
            throw FixtureError("No fixture files in \(directory.path)")
        }
        return try files.flatMap(casesOf)
    }

    private static func casesOf(_ file: URL) throws -> [ParseFixture] {
        try JSONDecoder()
            .decode([ParseFixture].self, from: Data(contentsOf: file))
            .map { fixture in
                var located = fixture
                located.file = file.lastPathComponent
                return located
            }
    }
}

struct FixtureError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
