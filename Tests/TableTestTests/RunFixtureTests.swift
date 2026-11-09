import Foundation
import SpecFixtures
import Testing
@testable import TableTest

/// Runs the run fixtures of `tabletest-spec` against ``TableTestRows``.
@Suite("Spec run fixtures")
struct RunFixtureTests {
    @Test("Finds the vendored run fixture cases")
    func findsVendoredRunFixtureCases() throws {
        #expect(try RunFixture.all().count > 0)
    }

    @Test("Makes the test cases that each run fixture states", arguments: try RunFixture.all())
    func makesTheStatedCases(_ fixture: RunFixture) {
        #expect(RunOutcome.of(fixture.inputText, parameterKinds: fixture.parameters) == fixture.expect, "rule \(fixture.rule)")
    }
}

/// One run fixture case: the table text, the kinds of the parameters, and the test cases or the
/// error the runtime must give.
struct RunFixture: Sendable, Decodable, CustomTestStringConvertible {
    /// The fixture file the case comes from, set after decoding.
    var file = ""
    let name: String
    let rule: String
    let input: [String]
    let parameters: [String]
    let expect: RunOutcome

    private enum CodingKeys: String, CodingKey {
        case name, rule, input, parameters, expect
    }

    var inputText: String {
        input.joined(separator: "\n")
    }

    var testDescription: String {
        "\(file) › \(name)"
    }

    /// Every case of every vendored run fixture file, in file and case order.
    static func all() throws -> [RunFixture] {
        let directory = Bundle.module.url(forResource: "run", withExtension: nil, subdirectory: "Fixtures")
        return try FixtureFiles.files(in: directory).flatMap { file in
            try FixtureFiles.cases(RunFixture.self, in: file).map { fixture in
                var located = fixture
                located.file = file.lastPathComponent
                return located
            }
        }
    }
}

/// A run result in the fixture format: the test cases, or an error class.
enum RunOutcome: Equatable, Sendable, Decodable, CustomStringConvertible {
    case cases([RunCase])
    case error(String)

    private enum CodingKeys: String, CodingKey {
        case cases, error
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let errorClass = try container.decodeIfPresent(String.self, forKey: .error) {
            self = .error(errorClass)
        } else {
            self = .cases(try container.decode([RunCase].self, forKey: .cases))
        }
    }

    /// The outcome of building the rows of the text for parameters of the given kinds.
    static func of(_ text: String, parameterKinds: [String]) -> RunOutcome {
        let source = TableSource(fileID: "Fixture/run.swift", filePath: "/run.swift", line: 1, column: 1, indentation: 0, isMultiline: true)
        do {
            let rows = try TableTestRows.make(
                table: text,
                parameters: parameterKinds.map { TableParameter(takesSet: $0 == "set") },
                source: source
            )
            return .cases(rows.map(RunCase.init(row:)))
        } catch let error as TableParseError {
            return .error(error.kind.fixtureName)
        } catch let error as TableTestError {
            return .error(error.kind.fixtureName)
        } catch {
            return .error("unexpected \(error)")
        }
    }

    var description: String {
        switch self {
        case let .cases(cases): cases.map(\.description).joined(separator: "; ")
        case let .error(errorClass): "error \(errorClass)"
        }
    }
}

/// One test case: its display name, or `nil` where the spec leaves the name to the runner, and
/// its arguments.
struct RunCase: Equatable, Sendable, Decodable, CustomStringConvertible {
    let name: String?
    let arguments: [ValueTree]

    init(row: TableTestRow) {
        name = row.scenario == nil ? nil : row.testDescription
        arguments = row.cells.map { ValueTree($0.value) }
    }

    var description: String {
        "\(name ?? "-") \(arguments)"
    }
}

extension TableTestError.Kind {
    /// The error class name the run fixture files use.
    var fixtureName: String {
        switch self {
        case .columnCount: "column-count"
        case .rowWidth: "row-width"
        case .emptyValueSet: "empty-value-set"
        }
    }
}
