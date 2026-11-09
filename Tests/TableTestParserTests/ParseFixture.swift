import Foundation
import SpecFixtures
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
    static func all() throws -> [ParseFixture] {
        let directory = Bundle.module.url(forResource: "parse", withExtension: nil, subdirectory: "Fixtures")
        return try FixtureFiles.files(in: directory).flatMap { file in
            try FixtureFiles.cases(ParseFixture.self, in: file).map { fixture in
                var located = fixture
                located.file = file.lastPathComponent
                return located
            }
        }
    }
}
