import TableTestParser

/// The table of one `@TableTest` and its planned cases, as the companion test attaches it in a
/// reporting build. Report exporters join it to the outcomes of the table's test.

package struct ReportManifest: Codable, Equatable {
    package var version = 1
    package let suite: [String]
    package let methodName: String
    package let title: String
    /// The name of the Swift Testing function that runs the cases, as in `scenarios(_:)`.
    package let testFunction: String
    package let headers: [ReportCell]
    package let rows: [ReportRow]

    package init(
        suite: [String], methodName: String, title: String, testFunction: String,
        headers: [ReportCell], rows: [ReportRow]
    ) {
        self.suite = suite
        self.methodName = methodName
        self.title = title
        self.testFunction = testFunction
        self.headers = headers
        self.rows = rows
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

package struct ReportValue: Codable, Equatable {
    package enum Kind: String, Codable { case null, string, list, set, map }

    package struct Entry: Codable, Equatable {
        package let key: String
        package let value: ReportValue
    }

    package let kind: Kind
    package var text: String?
    package var items: [ReportValue]?
    package var entries: [Entry]?

    init(_ value: TableValue) {
        switch value {
        case .null:
            kind = .null
        case .string(let value):
            kind = .string
            text = value
        case .list(let values):
            kind = .list
            items = values.map(Self.init)
        case .set(let values):
            kind = .set
            items = values.map(Self.init)
        case .map(let values):
            kind = .map
            entries = values.map { Entry(key: $0.key, value: Self($0.value)) }
        }
    }
}
