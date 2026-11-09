import SpecFixtures
import TableTestParser

/// A parse result in the fixture format: a table of value trees, or an error class.
///
/// Comparison is strict, as in the JVM runner: the elements of a set and the entries of a map
/// must be in the same order, and strings must have the same Unicode scalars.
enum ParseOutcome: Equatable, Sendable, Decodable, CustomStringConvertible {
    case table(headers: [ValueTree], rows: [[ValueTree]])
    case error(String)

    private enum CodingKeys: String, CodingKey {
        case headers, rows, error
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        if let errorClass = try container.decodeIfPresent(String.self, forKey: .error) {
            self = .error(errorClass)
        } else {
            self = .table(
                headers: try container.decode([ValueTree].self, forKey: .headers),
                rows: try container.decode([[ValueTree]].self, forKey: .rows)
            )
        }
    }

    /// The outcome of parsing the text with ``TableParser``.
    static func of(_ text: String) -> ParseOutcome {
        do {
            let table = try TableParser.parse(text)
            return .table(
                headers: table.headers.map(ValueTree.init),
                rows: table.rows.map { $0.values.map(ValueTree.init) }
            )
        } catch {
            return .error(error.kind.fixtureName)
        }
    }

    var description: String {
        switch self {
        case let .table(headers, rows):
            "headers \(headers) rows \(rows)"
        case let .error(errorClass):
            "error \(errorClass)"
        }
    }
}
