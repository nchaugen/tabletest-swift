import Foundation

extension TableValue {
    /// Reads a map cell field by field, for a ``TableValueDecodable`` conversion whose cell names
    /// only the fields it sets, such as `[racks: 3]` for a type whose other fields have defaults.
    ///
    /// The closure reads each field with ``TableFields/value(_:as:)`` or
    /// ``TableFields/required(_:as:)``, which convert it by the library's rules. When the closure
    /// returns, a key that it did not read fails the cell, so a misspelt key is not left out
    /// silently. A cell that is not a map fails too.
    ///
    /// ```swift
    /// extension Cellar: @retroactive TableValueDecodable {
    ///     public init(tableValue: TableValue) throws {
    ///         self = try tableValue.readingFields { fields in
    ///             var cellar = Cellar()
    ///             cellar.racks = try fields.value("racks") ?? cellar.racks
    ///             return cellar
    ///         }
    ///     }
    /// }
    /// ```
    public func readingFields<T>(_ read: (inout TableFields) throws -> T) throws -> T {
        guard case .map(let entries) = self else {
            throw TableValueConversionError("Cannot convert `\(tableText)` to a map")
        }
        var fields = TableFields(entries: entries)
        let result = try read(&fields)
        let unread = entries.map(\.key).filter { !fields.readKeys.contains($0) }
        guard unread.isEmpty else {
            let keys = unread.map { "`\($0)`" }.joined(separator: ", ")
            throw TableValueConversionError(
                "\(typeName(T.self)) does not read the \(unread.count == 1 ? "key" : "keys") \(keys)"
            )
        }
        return result
    }
}

/// The entries of a map cell, read by key inside ``TableValue/readingFields(_:)``.
public struct TableFields {
    private let entries: [TableMapEntry]
    fileprivate var readKeys: Set<String> = []

    fileprivate init(entries: [TableMapEntry]) {
        self.entries = entries
    }

    /// The value of the key, converted by the library's rules; `nil` when the cell leaves the key
    /// out.
    public mutating func value<Value>(_ key: String, as type: Value.Type = Value.self) throws -> Value? {
        readKeys.insert(key)
        guard let entry = entries.first(where: { $0.key == key }) else {
            return nil
        }
        do {
            return try entry.value.converted(to: Value.self)
        } catch let error as TableValueConversionError {
            throw TableValueConversionError(Self.message(error.description, at: key))
        }
    }

    /// The value of the key, converted by the library's rules; the cell fails when it leaves the
    /// key out.
    public mutating func required<Value>(_ key: String, as type: Value.Type = Value.self) throws -> Value {
        guard let value = try value(key, as: Value.self) else {
            throw TableValueConversionError("The map has no key `\(key)`")
        }
        return value
    }

    /// The message with the key in front of the path it already names: `(at `bins[1]`)`.
    private static func message(_ message: String, at key: String) -> String {
        let suffix = " (at `"
        guard let range = message.range(of: suffix, options: .backwards), message.hasSuffix("`)") else {
            return "\(message)\(suffix)\(key)`)"
        }
        let path = message[range.upperBound..<message.index(message.endIndex, offsetBy: -2)]
        let joined = path.hasPrefix("[") ? "\(key)\(path)" : "\(key).\(path)"
        return "\(message[..<range.lowerBound])\(suffix)\(joined)`)"
    }
}
