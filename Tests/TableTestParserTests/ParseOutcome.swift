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

/// A value in the fixture format: a JSON string, null, or a tagged list, set, or map.
indirect enum ValueTree: Equatable, Sendable, Decodable, CustomStringConvertible {
    case string(String)
    case null
    case list([ValueTree])
    case set([ValueTree])
    case map([MapPair])

    struct MapPair: Equatable, Sendable, Decodable {
        let key: String
        let value: ValueTree

        init(key: String, value: ValueTree) {
            self.key = key
            self.value = value
        }

        init(from decoder: any Decoder) throws {
            var pair = try decoder.unkeyedContainer()
            key = try pair.decode(String.self)
            value = try pair.decode(ValueTree.self)
        }

        static func == (lhs: MapPair, rhs: MapPair) -> Bool {
            lhs.key.unicodeScalars.elementsEqual(rhs.key.unicodeScalars) && lhs.value == rhs.value
        }
    }

    private enum CodingKeys: String, CodingKey {
        case list, set, map
    }

    init(_ value: TableValue) {
        switch value {
        case let .string(text): self = .string(text)
        case .null: self = .null
        case let .list(elements): self = .list(elements.map(ValueTree.init))
        case let .set(elements): self = .set(elements.map(ValueTree.init))
        case let .map(entries): self = .map(entries.map { MapPair(key: $0.key, value: ValueTree($0.value)) })
        }
    }

    init(from decoder: any Decoder) throws {
        let single = try decoder.singleValueContainer()
        if single.decodeNil() {
            self = .null
        } else if let text = try? single.decode(String.self) {
            self = .string(text)
        } else {
            let tagged = try decoder.container(keyedBy: CodingKeys.self)
            if let elements = try tagged.decodeIfPresent([ValueTree].self, forKey: .list) {
                self = .list(elements)
            } else if let elements = try tagged.decodeIfPresent([ValueTree].self, forKey: .set) {
                self = .set(elements)
            } else {
                self = .map(try tagged.decode([MapPair].self, forKey: .map))
            }
        }
    }

    static func == (lhs: ValueTree, rhs: ValueTree) -> Bool {
        switch (lhs, rhs) {
        case let (.string(left), .string(right)): left.unicodeScalars.elementsEqual(right.unicodeScalars)
        case (.null, .null): true
        case let (.list(left), .list(right)), let (.set(left), .set(right)): left == right
        case let (.map(left), .map(right)): left == right
        default: false
        }
    }

    var description: String {
        switch self {
        case let .string(text): "\"\(text.unicodeScalars.map(\.escapedForFixture).joined())\""
        case .null: "null"
        case let .list(elements): "list\(elements)"
        case let .set(elements): "set\(elements)"
        case let .map(pairs): "map[\(pairs.map { "\(ValueTree.string($0.key)): \($0.value)" }.joined(separator: ", "))]"
        }
    }
}

extension TableParseError.Kind {
    /// The error class name the fixture files use.
    var fixtureName: String {
        switch self {
        case .noRows: "no-rows"
        case .blankHeader: "blank-header"
        case .malformed: "malformed"
        case .duplicateKey: "duplicate-key"
        }
    }
}

extension Unicode.Scalar {
    /// The scalar as it reads in a failure message: a control character as `\u{…}`.
    fileprivate var escapedForFixture: String {
        value < 0x20 || value == 0x7F ? "\\u{\(String(value, radix: 16))}" : String(self)
    }
}
