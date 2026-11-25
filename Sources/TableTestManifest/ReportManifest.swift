import TableTestParser

/// The table of one `@TableTest` and its planned cases, as the companion test attaches it in a
/// reporting build. Report exporters join it to the outcomes of the table's test.

package struct ReportManifest: Codable, Equatable {
    /// The name of the Swift Testing function that `@TableTest` generates for the cases of a table.
    package static let tableTestFunction = "scenarios(_:)"

    package var version = 1
    package let suite: [String]
    /// The folders between the test target's folder and the file that holds the table.
    package let folders: [String]
    package let methodName: String
    package let title: String
    /// The doc comment above the `@TableTest` function, without its markers.
    package let description: String?
    /// The doc comment above the type that holds the `@TableTest` function, without its markers.
    package let suiteDescription: String?
    /// The name of the Swift Testing function that runs the cases, as in `scenarios(_:)`.
    package let testFunction: String
    package let headers: [ReportCell]
    package let rows: [ReportRow]

    package init(
        suite: [String], folders: [String] = [], methodName: String, title: String, description: String? = nil,
        suiteDescription: String? = nil, testFunction: String,
        headers: [ReportCell], rows: [ReportRow]
    ) {
        self.suite = suite
        self.folders = folders
        self.methodName = methodName
        self.title = title
        self.description = description
        self.suiteDescription = suiteDescription
        self.testFunction = testFunction
        self.headers = headers
        self.rows = rows
    }
}

extension ReportManifest {
    private enum CodingKeys: String, CodingKey {
        case version, suite, folders, methodName, title, description, suiteDescription, testFunction, headers, rows
    }

    /// Reads a manifest of an earlier version too, whose tables have no folders.
    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            suite: try container.decode([String].self, forKey: .suite),
            folders: try container.decodeIfPresent([String].self, forKey: .folders) ?? [],
            methodName: try container.decode(String.self, forKey: .methodName),
            title: try container.decode(String.self, forKey: .title),
            description: try container.decodeIfPresent(String.self, forKey: .description),
            suiteDescription: try container.decodeIfPresent(String.self, forKey: .suiteDescription),
            testFunction: try container.decode(String.self, forKey: .testFunction),
            headers: try container.decode([ReportCell].self, forKey: .headers),
            rows: try container.decode([ReportRow].self, forKey: .rows)
        )
        version = try container.decode(Int.self, forKey: .version)
    }
}

package struct ReportRow: Codable, Equatable {
    package let index: Int
    package let cells: [ReportCell]
    package let cases: [ReportCase]
    package let expansionError: String?

    package init(index: Int, cells: [ReportCell], cases: [ReportCase], expansionError: String? = nil) {
        self.index = index
        self.cells = cells
        self.cases = cases
        self.expansionError = expansionError
    }
}

package struct ReportCase: Codable, Equatable {
    package let number: Int
    package let displayName: String

    package init(number: Int, displayName: String) {
        self.number = number
        self.displayName = displayName
    }
}

package struct ReportCell: Codable, Equatable {
    package let value: ReportValue
    package let roles: [String]

    package init(value: TableValue, roles: [String]) {
        self.value = ReportValue(value)
        self.roles = roles
    }
}

/// A cell value of the manifest. It keeps the form of the ``TableValue`` that the table wrote.
package indirect enum ReportValue: Codable, Equatable {
    case null
    case string(String)
    case list([ReportValue])
    case set([ReportValue])
    case map([Entry])

    package struct Entry: Codable, Equatable {
        package let key: String
        package let value: ReportValue
    }

    init(_ value: TableValue) {
        switch value {
        case .null: self = .null
        case .string(let text): self = .string(text)
        case .list(let values): self = .list(values.map(Self.init))
        case .set(let values): self = .set(values.map(Self.init))
        case .map(let values): self = .map(values.map { Entry(key: $0.key, value: Self($0.value)) })
        }
    }

    private enum Kind: String, Codable { case null, string, list, set, map }

    private enum CodingKeys: String, CodingKey { case kind, text, items, entries }

    package init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .null: self = .null
        case .string: self = .string(try container.decode(String.self, forKey: .text))
        case .list: self = .list(try container.decode([ReportValue].self, forKey: .items))
        case .set: self = .set(try container.decode([ReportValue].self, forKey: .items))
        case .map: self = .map(try container.decode([Entry].self, forKey: .entries))
        }
    }

    package func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .null:
            try container.encode(Kind.null, forKey: .kind)
        case .string(let text):
            try container.encode(Kind.string, forKey: .kind)
            try container.encode(text, forKey: .text)
        case .list(let items):
            try container.encode(Kind.list, forKey: .kind)
            try container.encode(items, forKey: .items)
        case .set(let items):
            try container.encode(Kind.set, forKey: .kind)
            try container.encode(items, forKey: .items)
        case .map(let entries):
            try container.encode(Kind.map, forKey: .kind)
            try container.encode(entries, forKey: .entries)
        }
    }
}
