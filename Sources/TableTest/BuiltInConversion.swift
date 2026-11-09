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
            return try fromText(Character.self, value, codingPath) { $0.count == 1 ? $0.first : nil }
        }
        if type == Duration.self {
            return try fromText(Duration.self, value, codingPath, duration(_:))
        }
        if type == TimeZone.self {
            return try fromText(TimeZone.self, value, codingPath) { TimeZone(identifier: $0) }
        }
        if type == Locale.self {
            return try fromText(Locale.self, value, codingPath, locale(_:))
        }
        if type == Locale.Currency.self {
            return try fromText(Locale.Currency.self, value, codingPath) { text in
                let currency = Locale.Currency(text)
                return currency.isISOCurrency ? currency : nil
            }
        }
        if type == DateComponents.self {
            return try fromText(DateComponents.self, value, codingPath, dateComponents(_:))
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

    /// The value that the text of the cell gives, or a conversion error when it gives none.
    private static func fromText<T>(
        _ type: T.Type,
        _ value: TableValue,
        _ codingPath: [any CodingKey],
        _ parse: (String) -> T?
    ) throws -> T {
        let text = try SingleCellContainer(value: value, codingPath: codingPath).text(for: T.self)
        guard let result = parse(text) else {
            throw SingleCellContainer.mismatch(T.self, text: text, codingPath: codingPath)
        }
        return result
    }

    /// An amount and a unit, as Swift writes a duration: `1.5 seconds`, `250 milliseconds`.
    private static func duration(_ text: String) -> Duration? {
        let parts = text.split(separator: " ")
        guard parts.count == 2 else {
            return nil
        }
        let amount = String(parts[0])
        let whole = Int64(amount)
        let fraction = Double(amount).flatMap { $0.isFinite ? $0 : nil }
        switch parts[1] {
        case "second", "seconds": return whole.map { .seconds($0) } ?? fraction.map { .seconds($0) }
        case "millisecond", "milliseconds": return whole.map { .milliseconds($0) } ?? fraction.map { .milliseconds($0) }
        case "microsecond", "microseconds": return whole.map { .microseconds($0) } ?? fraction.map { .microseconds($0) }
        case "nanosecond", "nanoseconds": return whole.map { .nanoseconds($0) }
        default: return nil
        }
    }

    /// The locale of an identifier whose language, and region if it has one, are ISO codes.
    private static func locale(_ text: String) -> Locale? {
        let locale = Locale(identifier: text)
        guard locale.language.languageCode?.isISOLanguage == true, locale.region?.isISORegion ?? true else {
            return nil
        }
        return locale
    }

    /// A year, a month or a date, `2025`, `2025-03`, `2025-03-14`; or a time of day, `12:30`,
    /// `12:30:15`.
    private static func dateComponents(_ text: String) -> DateComponents? {
        if text.contains(":") {
            guard let parts = numbers(in: text, separator: ":", widths: [2, 2, 2]),
                  parts[0] < 24, parts[1] < 60, parts.count < 3 || parts[2] < 60
            else {
                return nil
            }
            return DateComponents(hour: parts[0], minute: parts[1], second: parts.count == 3 ? parts[2] : nil)
        }
        guard let parts = numbers(in: text, separator: "-", widths: [4, 2, 2]) else {
            return nil
        }
        switch parts.count {
        case 1: return DateComponents(year: parts[0])
        case 2: return (1...12).contains(parts[1]) ? DateComponents(year: parts[0], month: parts[1]) : nil
        default: return calendarDate(text).map { _ in DateComponents(year: parts[0], month: parts[1], day: parts[2]) }
        }
    }

    /// The numbers between the separators, each with the number of digits its position needs.
    private static func numbers(in text: String, separator: Character, widths: [Int]) -> [Int]? {
        let parts = text.split(separator: separator, omittingEmptySubsequences: false)
        guard parts.count <= widths.count,
              zip(parts, widths).allSatisfy({ $0.count == $1 && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) })
        else {
            return nil
        }
        return parts.compactMap { Int($0) }
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
