import Foundation
@_exported import TableTestParser

/// A type that converts itself from the parsed value of a table cell.
///
/// Every `Decodable` type already converts from a cell. Conform to this protocol when a type
/// needs its own reading of a list, a set or a map; for a text form, such as `12.50 EUR`,
/// conform to ``TableTextDecodable``. When a type conforms to both this protocol and `Decodable`,
/// this one decides. ``TableValue/converted(to:)`` converts each part with the library's rules.
///
/// ```swift
/// extension Pantry: TableValueDecodable {
///     init(tableValue: TableValue) throws {
///         guard case .list(let elements) = tableValue else {
///             throw TableValueConversionError("A pantry is a list of items")
///         }
///         self.init(items: try elements.map { try $0.converted(to: String.self) })
///     }
/// }
/// ```
public protocol TableValueDecodable {
    /// Creates a value from the parsed value of one cell, or of one element of a cell.
    init(tableValue: TableValue) throws
}

/// A type that converts itself from the text of a table cell, such as `250 g` for a quantity
/// type.
///
/// Return `nil` when the text does not convert: the library then reports the cell. A blank cell,
/// a list, a set and a map do not convert, and an optional parameter takes a blank cell as `nil`.
///
/// ```swift
/// extension Quantity: TableTextDecodable {
///     init?(tableText: String) {
///         self.init(parsing: tableText)
///     }
/// }
/// ```
public protocol TableTextDecodable: TableValueDecodable {
    /// Creates a value from the text of one cell, or of one element of a cell, or returns `nil`.
    init?(tableText: String)
}

extension TableTextDecodable {
    public init(tableValue: TableValue) throws {
        let text = try SingleCellContainer(value: tableValue, codingPath: []).text(for: Self.self)
        guard let value = Self(tableText: text) else {
            throw SingleCellContainer.mismatch(Self.self, text: text, codingPath: [])
        }
        self = value
    }
}

extension TableValue {
    /// The value converted to a type by the rules the library applies to a cell, for a
    /// ``TableValueDecodable`` conversion that reads a list or a map by hand.
    ///
    /// ```swift
    /// self.init(colour: try entry.value.converted(to: Colour.self))
    /// ```
    public func converted<T>(to type: T.Type) throws -> T {
        do {
            return try TableValueDecoding.convert(self, to: T.self)
        } catch let error as TableValueConversionError {
            throw error
        } catch {
            throw TableValueConversionError(TableValueDecoding.message(of: error))
        }
    }
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
    /// The case whose name is the text of the cell. An enum with text raw values that declares
    /// `TableValueDecodable` reads its case names in place of its raw values.
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
///
/// The types are compared, not their names: a Foundation type lives in another module on Linux
/// (`FoundationEssentials.Locale.Currency`), and `Decimal` is `NSDecimal` on Apple platforms.
func typeName<T>(_ type: T.Type) -> String {
    switch ObjectIdentifier(type) {
    case ObjectIdentifier(Decimal.self): "Decimal"
    case ObjectIdentifier(Locale.Currency.self): "Locale.Currency"
    default: String(describing: type)
    }
}
