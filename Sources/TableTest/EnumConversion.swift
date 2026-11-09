/// Converts a cell to a type that is neither `Decodable` nor ``TableValueDecodable``: a
/// raw-value enum, an enum with no raw value, a `LosslessStringConvertible` type, and an
/// optional, list, set or map of them.
///
/// A `CaseIterable` enum reads its case name, as the ``TableValueDecodable`` default for
/// `CaseIterable` does, so a cell names a case as Swift code does. A `LosslessStringConvertible`
/// type reads the text of the cell. A raw-value enum with no case list reads its raw value. A `Decodable` enum does not come here: `TableValueDecoding.decode`
/// reads its case name when it is `CaseIterable`, and its raw value otherwise.
extension TableValueDecoding {
    static func convert<T>(_ value: TableValue, to type: T.Type) throws -> T {
        try instance(of: T.self, from: value) as! T
    }

    /// The value as an instance of the type, by the first conversion the type has.
    static func instance(of type: Any.Type, from value: TableValue) throws -> Any {
        if let own = type as? any TableValueDecodable.Type {
            return try own.init(tableValue: value)
        }
        if let builtIn = try builtIn(type, from: value, codingPath: []) {
            return builtIn
        }
        if let decodable = type as? any Decodable.Type {
            return try decodeOpened(value, as: decodable)
        }
        if let collection = type as? any EnumCollection.Type {
            return try collection.init(converting: value)
        }
        if let enumerable = type as? any CaseIterable.Type {
            return try namedCase(of: enumerable, from: value)
        }
        if let lossless = type as? any LosslessStringConvertible.Type {
            return try described(as: lossless, by: value)
        }
        if let rawValued = type as? any RawRepresentable.Type {
            return try rawValueCase(of: rawValued, from: value)
        }
        throw TableValueConversionError(
            "\(typeName(type)) does not convert from a cell: make it Decodable, or conform it to TableCellText"
        )
    }

    /// The value that the type's `init?(_:)` reads from the text of the cell.
    private static func described<T: LosslessStringConvertible>(as type: T.Type, by value: TableValue) throws -> T {
        let text = try SingleCellContainer(value: value, codingPath: []).text(for: T.self)
        guard let result = T(text) else {
            throw SingleCellContainer.mismatch(T.self, text: text, codingPath: [])
        }
        return result
    }

    /// The case whose name is the text of the cell.
    static func namedCase<T: CaseIterable>(of type: T.Type, from value: TableValue) throws -> T {
        guard case .string(let name) = value else {
            throw TableValueConversionError("Cannot convert `\(value.tableText)` to \(typeName(T.self))")
        }
        guard let match = T.allCases.first(where: { String(describing: $0) == name }) else {
            let rawValueMatch = T.allCases.first { rawValueText(of: $0) == name }
            throw TableValueConversionError(
                "\(typeName(T.self)) has no case named `\(name)`"
                    + (rawValueMatch.map { "; the case with this raw value is `\($0)`" } ?? "")
            )
        }
        return match
    }

    /// The raw value of a case as it reads in a cell, or `nil` for an enum with no raw value.
    private static func rawValueText(of enumCase: Any) -> String? {
        (enumCase as? any RawRepresentable).map { "\($0.rawValue)" }
    }

    private static func decodeOpened<T: Decodable>(_ value: TableValue, as type: T.Type) throws -> T {
        try decode(value, as: T.self, codingPath: [])
    }

    private static func rawValueCase<T: RawRepresentable>(of type: T.Type, from value: TableValue) throws -> T {
        let rawValue = try convert(value, to: T.RawValue.self)
        guard let match = T(rawValue: rawValue) else {
            throw TableValueConversionError("\(typeName(T.self)) has no case with the raw value `\(value.tableText)`")
        }
        return match
    }
}

/// A Swift collection whose elements convert through ``TableValueDecoding/instance(of:from:)``.
protocol EnumCollection {
    init(converting value: TableValue) throws
}

extension Optional: EnumCollection {
    init(converting value: TableValue) throws {
        self = value == .null ? nil : .some(try TableValueDecoding.convert(value, to: Wrapped.self))
    }
}

extension Array: EnumCollection {
    init(converting value: TableValue) throws {
        self = try value.elements(convertingTo: Self.self).map {
            try TableValueDecoding.convert($0, to: Element.self)
        }
    }
}

extension Set: EnumCollection {
    init(converting value: TableValue) throws {
        self = Set(try [Element](converting: value))
        try TableValueDecoding.refuseMergedElements(self, of: value, as: Self.self)
    }
}

/// A Swift dictionary, which `Decodable` reads from a map only for some key types.
protocol MapCollection: EnumCollection {
    /// Whether the dictionary's own `init(from:)` reads a map; for other keys it reads a list.
    static var decodesFromAMap: Bool { get }
}

extension Dictionary: MapCollection {
    static var decodesFromAMap: Bool {
        Key.self == String.self || Key.self == Int.self
            || (Key.self is any CodingKeyRepresentable.Type && !(Key.self is any CaseIterable.Type))
    }
}

extension Dictionary: EnumCollection {
    init(converting value: TableValue) throws {
        guard case .map(let entries) = value else {
            throw TableValueConversionError("Cannot convert `\(value.tableText)` to \(typeName(Self.self))")
        }
        self = try Dictionary(
            entries.map {
                (
                    try TableValueDecoding.convert(.string($0.key), to: Key.self),
                    try TableValueDecoding.convert($0.value, to: Value.self)
                )
            },
            uniquingKeysWith: { first, _ in first }
        )
        try TableValueDecoding.refuseMergedElements(self, of: value, as: Self.self)
    }
}
