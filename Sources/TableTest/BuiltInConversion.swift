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
        if type == Date.self {
            return try date(from: value, codingPath: codingPath)
        }
        if type == Character.self {
            return try character(from: value, codingPath: codingPath)
        }
        if let range = type as? any SpelledRange.Type, value.isText {
            return try range.init(spelled: value, codingPath: codingPath)
        }
        return nil
    }

    /// A calendar date at midnight UTC, `2025-03-14`, or a date and time with a zone,
    /// `2025-03-14T10:30:00Z` or `2025-03-14T10:30:00+01:00` (ISO 8601).
    private static func date(from value: TableValue, codingPath: [any CodingKey]) throws -> Date {
        let text = try SingleCellContainer(value: value, codingPath: codingPath).text(for: Date.self)
        if let date = calendarDate(text) ?? dateTime(text) {
            return date
        }
        guard text.wholeMatch(of: #/\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2}(\.\d+)?)?/#) == nil else {
            throw DecodingError.typeMismatch(
                Date.self,
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Cannot convert `\(text)` to Date: add a zone, such as `Z` or `+01:00`"
                )
            )
        }
        throw SingleCellContainer.mismatch(Date.self, text: text, codingPath: codingPath)
    }

    /// The date at midnight UTC, when the text is a date that the calendar has.
    private static func calendarDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        formatter.timeZone = TimeZone(identifier: "UTC")
        guard let date = formatter.date(from: text), formatter.string(from: date) == text else {
            return nil
        }
        return date
    }

    private static func dateTime(_ text: String) -> Date? {
        let shape = #/(\d{4}-\d{2}-\d{2})T\d{2}:\d{2}:\d{2}(\.\d+)?(Z|[+-]\d{2}:\d{2})/#
        guard let match = text.wholeMatch(of: shape), calendarDate(String(match.1)) != nil else {
            return nil
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = match.2 == nil ? [.withInternetDateTime] : [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: text)
    }

    /// One grapheme, such as `a` or `e` + U+0301.
    private static func character(from value: TableValue, codingPath: [any CodingKey]) throws -> Character {
        let text = try SingleCellContainer(value: value, codingPath: codingPath).text(for: Character.self)
        guard text.count == 1, let character = text.first else {
            throw SingleCellContainer.mismatch(Character.self, text: text, codingPath: codingPath)
        }
        return character
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

/// A range that a cell spells as Swift does: `2028...2030`, or `2028..<2031`. A list of the
/// bounds, `[2028, 2030]`, reads as `Decodable` does.
protocol SpelledRange {
    static var rangeOperator: String { get }
    init(spelled value: TableValue, codingPath: [any CodingKey]) throws
}

extension SpelledRange {
    /// The two bounds on each side of the range operator, converted to the bound type.
    fileprivate static func bounds<Bound: Decodable & Comparable>(
        of value: TableValue,
        as bound: Bound.Type,
        codingPath: [any CodingKey]
    ) throws -> (lower: Bound, upper: Bound) {
        let text = try SingleCellContainer(value: value, codingPath: codingPath).text(for: Self.self)
        guard let separator = text.range(of: rangeOperator) else {
            throw SingleCellContainer.mismatch(Self.self, text: text, codingPath: codingPath)
        }
        let lower = try TableValueDecoding.decode(
            .string(text[..<separator.lowerBound].trimmingCharacters(in: .whitespaces)),
            as: Bound.self,
            codingPath: codingPath
        )
        let upper = try TableValueDecoding.decode(
            .string(text[separator.upperBound...].trimmingCharacters(in: .whitespaces)),
            as: Bound.self,
            codingPath: codingPath
        )
        guard lower <= upper else {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(
                    codingPath: codingPath,
                    debugDescription: "Cannot convert `\(text)` to \(typeName(Self.self)): "
                        + "the lower bound is above the upper bound"
                )
            )
        }
        return (lower, upper)
    }
}

extension ClosedRange: SpelledRange where Bound: Decodable {
    static var rangeOperator: String { "..." }

    init(spelled value: TableValue, codingPath: [any CodingKey]) throws {
        let bounds = try Self.bounds(of: value, as: Bound.self, codingPath: codingPath)
        self = bounds.lower...bounds.upper
    }
}

extension Range: SpelledRange where Bound: Decodable {
    static var rangeOperator: String { "..<" }

    init(spelled value: TableValue, codingPath: [any CodingKey]) throws {
        let bounds = try Self.bounds(of: value, as: Bound.self, codingPath: codingPath)
        self = bounds.lower..<bounds.upper
    }
}

extension TableValue {
    /// Whether the value is text, or the blank cell that stands for no text.
    fileprivate var isText: Bool {
        switch self {
        case .string, .null: true
        default: false
        }
    }
}
