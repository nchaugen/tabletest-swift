import Foundation

/// The conversions the library has for types whose `Decodable` reading does not fit a cell, or
/// that are not `Decodable`.
extension TableValueDecoding {
    /// The value converted by a built-in conversion, or `nil` when the type has none.
    static func builtIn(_ type: Any.Type, from value: TableValue, codingPath: [any CodingKey]) throws -> Any? {
        if type == Decimal.self {
            return try decimal(from: value, codingPath: codingPath)
        }
        if type == URL.self {
            return try url(from: value, codingPath: codingPath)
        }
        return nil
    }

    private static func decimal(from value: TableValue, codingPath: [any CodingKey]) throws -> Decimal {
        let text = try SingleCellContainer(value: value, codingPath: codingPath).text(for: Decimal.self)
        guard let decimal = Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")),
              text.allSatisfy({ $0.isNumber || "+-.eE".contains($0) })
        else {
            throw SingleCellContainer.mismatch(Decimal.self, text: text, codingPath: codingPath)
        }
        return decimal
    }

    private static func url(from value: TableValue, codingPath: [any CodingKey]) throws -> URL {
        let text = try SingleCellContainer(value: value, codingPath: codingPath).text(for: URL.self)
        guard let url = URL(string: text) else {
            throw SingleCellContainer.mismatch(URL.self, text: text, codingPath: codingPath)
        }
        return url
    }
}
