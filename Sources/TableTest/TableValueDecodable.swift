@_exported import TableTestParser

/// A type that converts itself from the parsed value of a table cell.
///
/// Every `Decodable` type already converts from a cell. Conform to this protocol when a type
/// is not `Decodable`, or when it needs its own reading of the cell, such as `12.50 EUR` for a
/// money type. When a type conforms to both protocols, this one decides.
///
/// ```swift
/// extension Money: TableValueDecodable {
///     init(tableValue: TableValue) throws {
///         guard case .string(let text) = tableValue, let money = Money(parsing: text) else {
///             throw TableValueConversionError("Cannot read `\(tableValue)` as money")
///         }
///         self = money
///     }
/// }
/// ```
public protocol TableValueDecodable {
    /// Creates a value from the parsed value of one cell, or of one element of a cell.
    init(tableValue: TableValue) throws
}

/// The error a ``TableValueDecodable`` type throws when a cell does not convert.
public struct TableValueConversionError: Error, CustomStringConvertible, Sendable {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}

extension TableValue: TableValueDecodable {
    /// The parsed value itself, for a parameter that wants it unconverted.
    public init(tableValue: TableValue) {
        self = tableValue
    }
}

extension Optional: TableValueDecodable where Wrapped: TableValueDecodable {
    /// `nil` for a blank cell, otherwise the wrapped type's conversion.
    public init(tableValue: TableValue) throws {
        self = tableValue == .null ? nil : try Wrapped(tableValue: tableValue)
    }
}

extension Array: TableValueDecodable where Element: TableValueDecodable {
    /// The elements of a list or a set cell, in order.
    public init(tableValue: TableValue) throws {
        self = try tableValue.elements(convertingTo: Self.self).map(Element.init(tableValue:))
    }
}

extension Set: TableValueDecodable where Element: TableValueDecodable {
    /// The elements of a list or a set cell.
    public init(tableValue: TableValue) throws {
        self = Set(try tableValue.elements(convertingTo: Self.self).map(Element.init(tableValue:)))
        try TableValueDecoding.refuseMergedElements(self, of: tableValue, as: Self.self)
    }
}

extension Dictionary: TableValueDecodable where Key == String, Value: TableValueDecodable {
    /// The entries of a map cell.
    public init(tableValue: TableValue) throws {
        guard case .map(let entries) = tableValue else {
            throw TableValueConversionError("Cannot convert `\(tableValue.tableText)` to \(typeName(Self.self))")
        }
        self = try Dictionary(
            entries.map { ($0.key, try Value(tableValue: $0.value)) },
            uniquingKeysWith: { first, _ in first }
        )
        try TableValueDecoding.refuseMergedElements(self, of: tableValue, as: Self.self)
    }
}

extension TableValueDecodable where Self: CaseIterable {
    /// The case whose name is the text of the cell, for an enum with no raw value.
    public init(tableValue: TableValue) throws {
        self = try TableValueDecoding.namedCase(of: Self.self, from: tableValue)
    }
}

extension TableValue {
    /// The value as it reads in a table cell, for an error message.
    var tableText: String {
        switch self {
        case let .string(text): text
        case .null: ""
        case let .list(elements): "[\(elements.map(\.tableText).joined(separator: ", "))]"
        case let .set(elements): "{\(elements.map(\.tableText).joined(separator: ", "))}"
        case let .map(entries) where entries.isEmpty: "[:]"
        case let .map(entries): "[\(entries.map { "\($0.key): \($0.value.tableText)" }.joined(separator: ", "))]"
        }
    }

    /// The elements of a list or a set, or an error that names the target type.
    func elements<Target>(convertingTo target: Target.Type) throws -> [TableValue] {
        switch self {
        case let .list(elements), let .set(elements): elements
        default: throw TableValueConversionError("Cannot convert `\(tableText)` to \(typeName(Target.self))")
        }
    }
}

/// The name of a type as a test author writes it, for an error message.
func typeName<T>(_ type: T.Type) -> String {
    let name = String(describing: type)
    return name == "NSDecimal" ? "Decimal" : name
}
