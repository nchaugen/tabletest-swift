import Foundation
import SpecFixtures
import TableTestFormat
import Testing

/// Runs the format fixtures of `tabletest-spec` against ``TableFormatter``, and checks on each
/// one that formatting changes only whitespace (SPEC 4.1).
@Suite("Spec format fixtures")
struct FormatFixtureTests {
    @Test("Finds the vendored format fixture cases")
    func findsVendoredFormatFixtureCases() throws {
        #expect(try FormatFixture.all().count > 0)
    }

    @Test("Formats each fixture's input to its output", arguments: try FormatFixture.all())
    func formatsTheInput(_ fixture: FormatFixture) {
        #expect(TableFormatter.format(fixture.inputText) == fixture.expectedText, "rule \(fixture.rule)")
    }

    @Test("Changes only whitespace", arguments: try FormatFixture.all())
    func changesOnlyWhitespace(_ fixture: FormatFixture) {
        let formatted = TableFormatter.format(fixture.inputText)

        #expect(formatted.withoutWhitespace == fixture.inputText.withoutWhitespace)
    }
}

/// One format fixture case: the table text, and the text a formatter must give for it.
struct FormatFixture: Sendable, Decodable, CustomTestStringConvertible {
    /// The fixture file the case comes from, set after decoding.
    var file = ""
    let name: String
    let rule: String
    let input: [String]
    /// The output lines, or `nil` when the input must stay unchanged.
    let output: [String]?

    private enum CodingKeys: String, CodingKey {
        case name, rule, input, expect
    }

    private enum ExpectKeys: String, CodingKey {
        case output
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        rule = try container.decode(String.self, forKey: .rule)
        input = try container.decode([String].self, forKey: .input)
        if let unchanged = try? container.decode(String.self, forKey: .expect) {
            guard unchanged == "unchanged" else {
                throw FixtureError("A format fixture expects an output or \"unchanged\", not \"\(unchanged)\"")
            }
            output = nil
        } else {
            output = try container.nestedContainer(keyedBy: ExpectKeys.self, forKey: .expect)
                .decode([String].self, forKey: .output)
        }
    }

    var inputText: String {
        input.joined(separator: "\n")
    }

    var expectedText: String {
        output?.joined(separator: "\n") ?? inputText
    }

    var testDescription: String {
        "\(file) › \(name)"
    }

    /// Every case of every vendored format fixture file, in file and case order.
    static func all() throws -> [FormatFixture] {
        let directory = Bundle.module.url(forResource: "format", withExtension: nil, subdirectory: "Fixtures")
        return try FixtureFiles.files(in: directory).flatMap { file in
            try FixtureFiles.cases(FormatFixture.self, in: file).map { fixture in
                var located = fixture
                located.file = file.lastPathComponent
                return located
            }
        }
    }
}

extension String {
    /// The text with every scalar from U+0000 to U+0020 removed (SPEC "Terms").
    var withoutWhitespace: [Unicode.Scalar] {
        unicodeScalars.filter { $0.value > 0x20 }
    }
}
