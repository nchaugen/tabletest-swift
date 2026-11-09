import Foundation

/// Converts the parsed value of a cell to a Swift type by the first route that applies: the
/// type's own ``TableValueDecodable`` conformance, a built-in conversion, the case name of a
/// `CaseIterable` enum, and then `Decodable`.
enum TableValueDecoding {
    static func decode<T: Decodable>(
        _ value: TableValue,
        as type: T.Type,
        codingPath: [any CodingKey] = []
    ) throws -> T {
        if let custom = T.self as? any TableValueDecodable.Type {
            return try custom.init(tableValue: value) as! T
        }
        if let map = T.self as? any MapCollection.Type, !map.decodesFromAMap {
            return try map.init(converting: value) as! T
        }
        if T.self == Decimal.self {
            return try decimal(from: value, codingPath: codingPath) as! T
        }
        if T.self == URL.self {
            return try url(from: value, codingPath: codingPath) as! T
        }
        if let enumerable = T.self as? any CaseIterable.Type {
            return try namedCase(of: enumerable, from: value, codingPath: codingPath) as! T
        }
        let result = try T(from: TableValueDecoder(value: value, codingPath: codingPath))
        try refuseMergedElements(result, of: value, as: T.self)
        return result
    }

    static func decode<T: TableValueDecodable>(_ value: TableValue, as type: T.Type) throws -> T {
        try T(tableValue: value)
    }

    static func decode<T: Decodable & TableValueDecodable>(_ value: TableValue, as type: T.Type) throws -> T {
        try T(tableValue: value)
    }

    /// Refuses a Swift collection with fewer members than the cell has distinct elements.
    ///
    /// Swift `Set` and `Dictionary` treat canonically equal strings, such as `é` and `e` + U+0301,
    /// as one. The table format keeps them apart, so a merge would drop a value silently.
    static func refuseMergedElements<T>(_ result: T, of value: TableValue, as type: T.Type) throws {
        let distinctElements: Int
        switch value {
        case let .list(elements), let .set(elements): distinctElements = Set(elements).count
        case let .map(entries): distinctElements = entries.count
        default: return
        }
        guard let collection = result as? any Collection, collection.count < distinctElements else {
            return
        }
        throw TableValueConversionError(
            "Cannot convert `\(value.tableText)` to \(typeName(T.self)): Swift treats two of its elements as equal"
        )
    }

    /// The case whose name is the text of the cell, with the path to the cell in an error.
    private static func namedCase<T: CaseIterable>(
        of type: T.Type,
        from value: TableValue,
        codingPath: [any CodingKey]
    ) throws -> T {
        do {
            return try namedCase(of: T.self, from: value)
        } catch let error as TableValueConversionError {
            throw DecodingError.dataCorrupted(
                DecodingError.Context(codingPath: codingPath, debugDescription: error.description)
            )
        }
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

    /// The message of a conversion error, with the path to the element that failed.
    static func message(of error: any Error) -> String {
        switch error {
        case let DecodingError.typeMismatch(_, context),
             let DecodingError.valueNotFound(_, context),
             let DecodingError.keyNotFound(_, context),
             let DecodingError.dataCorrupted(context):
            context.debugDescription + pathSuffix(context.codingPath)
        default:
            String(describing: error)
        }
    }

    private static func pathSuffix(_ codingPath: [any CodingKey]) -> String {
        guard !codingPath.isEmpty else {
            return ""
        }
        let path = codingPath.map { key in
            key.intValue.map { "[\($0)]" } ?? ".\(key.stringValue)"
        }.joined()
        return " (at `\(path.hasPrefix(".") ? String(path.dropFirst()) : path)`)"
    }
}

/// A `Decoder` over the parsed value of one cell or element.
struct TableValueDecoder: Decoder {
    let value: TableValue
    let codingPath: [any CodingKey]
    var userInfo: [CodingUserInfoKey: Any] { [:] }

    func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
        guard case .map(let entries) = value else {
            throw DecodingError.typeMismatch(
                [String: Any].self,
                context("Cannot convert `\(value.tableText)` to a map")
            )
        }
        return KeyedDecodingContainer(MapContainer<Key>(entries: entries, codingPath: codingPath))
    }

    func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
        switch value {
        case let .list(elements), let .set(elements):
            return ElementsContainer(elements: elements, codingPath: codingPath)
        default:
            throw DecodingError.typeMismatch(
                [Any].self,
                context("Cannot convert `\(value.tableText)` to a list or a set")
            )
        }
    }

    func singleValueContainer() throws -> any SingleValueDecodingContainer {
        SingleCellContainer(value: value, codingPath: codingPath)
    }

    private func context(_ description: String) -> DecodingError.Context {
        DecodingError.Context(codingPath: codingPath, debugDescription: description)
    }
}

/// Reads a string value as text, a number, or a Boolean.
struct SingleCellContainer: SingleValueDecodingContainer {
    let value: TableValue
    let codingPath: [any CodingKey]

    func decodeNil() -> Bool {
        value == .null
    }

    func decode(_ type: Bool.Type) throws -> Bool {
        let text = try text(for: Bool.self)
        switch text.lowercased() {
        case "true": return true
        case "false": return false
        default: throw Self.mismatch(Bool.self, text: text, codingPath: codingPath)
        }
    }

    func decode(_ type: String.Type) throws -> String { try text(for: String.self) }
    func decode(_ type: Double.Type) throws -> Double { try number(Double.self) }
    func decode(_ type: Float.Type) throws -> Float { try number(Float.self) }
    func decode(_ type: Int.Type) throws -> Int { try number(Int.self) }
    func decode(_ type: Int8.Type) throws -> Int8 { try number(Int8.self) }
    func decode(_ type: Int16.Type) throws -> Int16 { try number(Int16.self) }
    func decode(_ type: Int32.Type) throws -> Int32 { try number(Int32.self) }
    func decode(_ type: Int64.Type) throws -> Int64 { try number(Int64.self) }
    func decode(_ type: UInt.Type) throws -> UInt { try number(UInt.self) }
    func decode(_ type: UInt8.Type) throws -> UInt8 { try number(UInt8.self) }
    func decode(_ type: UInt16.Type) throws -> UInt16 { try number(UInt16.self) }
    func decode(_ type: UInt32.Type) throws -> UInt32 { try number(UInt32.self) }
    func decode(_ type: UInt64.Type) throws -> UInt64 { try number(UInt64.self) }

    func decode<T: Decodable>(_ type: T.Type) throws -> T {
        try TableValueDecoding.decode(value, as: T.self, codingPath: codingPath)
    }

    /// The text of a string value, or an error for a blank cell or a collection.
    func text<Target>(for target: Target.Type) throws -> String {
        switch value {
        case let .string(text):
            return text
        case .null:
            throw DecodingError.valueNotFound(
                Target.self,
                DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot convert a blank cell to \(typeName(Target.self))")
            )
        default:
            throw Self.mismatch(Target.self, text: value.tableText, codingPath: codingPath)
        }
    }

    private func number<Number: LosslessStringConvertible>(_ type: Number.Type) throws -> Number {
        let text = try text(for: Number.self)
        guard let number = Number(text) else {
            throw Self.mismatch(Number.self, text: text, codingPath: codingPath)
        }
        return number
    }

    static func mismatch<Target>(_ target: Target.Type, text: String, codingPath: [any CodingKey]) -> DecodingError {
        DecodingError.typeMismatch(
            Target.self,
            DecodingError.Context(codingPath: codingPath, debugDescription: "Cannot convert `\(text)` to \(typeName(Target.self))")
        )
    }
}

/// Reads the elements of a list or a set in order.
struct ElementsContainer: UnkeyedDecodingContainer {
    let elements: [TableValue]
    let codingPath: [any CodingKey]
    private(set) var currentIndex = 0

    init(elements: [TableValue], codingPath: [any CodingKey]) {
        self.elements = elements
        self.codingPath = codingPath
    }

    var count: Int? { elements.count }
    var isAtEnd: Bool { currentIndex >= elements.count }

    mutating func decodeNil() throws -> Bool {
        guard try next() == .null else {
            return false
        }
        currentIndex += 1
        return true
    }

    mutating func decode<T: Decodable>(_ type: T.Type) throws -> T {
        let element = try next()
        let decoded = try TableValueDecoding.decode(element, as: T.self, codingPath: elementPath)
        currentIndex += 1
        return decoded
    }

    mutating func decode(_ type: Bool.Type) throws -> Bool { try decodeNext(type) }
    mutating func decode(_ type: String.Type) throws -> String { try decodeNext(type) }
    mutating func decode(_ type: Double.Type) throws -> Double { try decodeNext(type) }
    mutating func decode(_ type: Float.Type) throws -> Float { try decodeNext(type) }
    mutating func decode(_ type: Int.Type) throws -> Int { try decodeNext(type) }
    mutating func decode(_ type: Int8.Type) throws -> Int8 { try decodeNext(type) }
    mutating func decode(_ type: Int16.Type) throws -> Int16 { try decodeNext(type) }
    mutating func decode(_ type: Int32.Type) throws -> Int32 { try decodeNext(type) }
    mutating func decode(_ type: Int64.Type) throws -> Int64 { try decodeNext(type) }
    mutating func decode(_ type: UInt.Type) throws -> UInt { try decodeNext(type) }
    mutating func decode(_ type: UInt8.Type) throws -> UInt8 { try decodeNext(type) }
    mutating func decode(_ type: UInt16.Type) throws -> UInt16 { try decodeNext(type) }
    mutating func decode(_ type: UInt32.Type) throws -> UInt32 { try decodeNext(type) }
    mutating func decode(_ type: UInt64.Type) throws -> UInt64 { try decodeNext(type) }

    mutating func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type
    ) throws -> KeyedDecodingContainer<NestedKey> {
        let container = try TableValueDecoder(value: next(), codingPath: elementPath).container(keyedBy: type)
        currentIndex += 1
        return container
    }

    mutating func nestedUnkeyedContainer() throws -> any UnkeyedDecodingContainer {
        let container = try TableValueDecoder(value: next(), codingPath: elementPath).unkeyedContainer()
        currentIndex += 1
        return container
    }

    mutating func superDecoder() throws -> any Decoder {
        let decoder = TableValueDecoder(value: try next(), codingPath: elementPath)
        currentIndex += 1
        return decoder
    }

    private var elementPath: [any CodingKey] {
        codingPath + [ElementKey(index: currentIndex)]
    }

    private mutating func decodeNext<T: Decodable>(_ type: T.Type) throws -> T {
        try decode(type)
    }

    private func next() throws -> TableValue {
        guard !isAtEnd else {
            throw DecodingError.valueNotFound(
                TableValue.self,
                DecodingError.Context(codingPath: codingPath, debugDescription: "The cell has no element \(currentIndex)")
            )
        }
        return elements[currentIndex]
    }
}

/// Reads the entries of a map by key.
struct MapContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
    let entries: [TableMapEntry]
    let codingPath: [any CodingKey]

    var allKeys: [Key] {
        entries.compactMap { Key(stringValue: $0.key) }
    }

    func contains(_ key: Key) -> Bool {
        entry(for: key) != nil
    }

    func decodeNil(forKey key: Key) throws -> Bool {
        try value(for: key) == .null
    }

    func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T {
        try TableValueDecoding.decode(value(for: key), as: T.self, codingPath: codingPath + [key])
    }

    func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try decodeValue(type, key) }
    func decode(_ type: String.Type, forKey key: Key) throws -> String { try decodeValue(type, key) }
    func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try decodeValue(type, key) }
    func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try decodeValue(type, key) }
    func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try decodeValue(type, key) }
    func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try decodeValue(type, key) }
    func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try decodeValue(type, key) }
    func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try decodeValue(type, key) }
    func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try decodeValue(type, key) }
    func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try decodeValue(type, key) }
    func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try decodeValue(type, key) }
    func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try decodeValue(type, key) }
    func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try decodeValue(type, key) }
    func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try decodeValue(type, key) }

    func nestedContainer<NestedKey: CodingKey>(
        keyedBy type: NestedKey.Type,
        forKey key: Key
    ) throws -> KeyedDecodingContainer<NestedKey> {
        try TableValueDecoder(value: value(for: key), codingPath: codingPath + [key]).container(keyedBy: type)
    }

    func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer {
        try TableValueDecoder(value: value(for: key), codingPath: codingPath + [key]).unkeyedContainer()
    }

    func superDecoder() throws -> any Decoder {
        TableValueDecoder(value: .map(entries), codingPath: codingPath)
    }

    func superDecoder(forKey key: Key) throws -> any Decoder {
        TableValueDecoder(value: try value(for: key), codingPath: codingPath + [key])
    }

    private func decodeValue<T: Decodable>(_ type: T.Type, _ key: Key) throws -> T {
        try decode(type, forKey: key)
    }

    private func entry(for key: Key) -> TableMapEntry? {
        entries.first { $0.key.unicodeScalars.elementsEqual(key.stringValue.unicodeScalars) }
    }

    private func value(for key: Key) throws -> TableValue {
        guard let entry = entry(for: key) else {
            throw DecodingError.keyNotFound(
                key,
                DecodingError.Context(codingPath: codingPath, debugDescription: "The map has no key `\(key.stringValue)`")
            )
        }
        return entry.value
    }
}

/// The coding key of an element of a list or a set.
struct ElementKey: CodingKey {
    let index: Int

    init(index: Int) {
        self.index = index
    }

    init?(stringValue: String) {
        nil
    }

    init?(intValue: Int) {
        index = intValue
    }

    var stringValue: String { "\(index)" }
    var intValue: Int? { index }
}
