import Foundation

/// An enum case as Swift spells it in a cell: `nonVintage`, `year(2025)`,
/// `month(year: 2025, month: 3)`. A value with no label takes the key `_0`, `_1`, and so on, by
/// its position, as the synthesised `Decodable` conformance of an enum names it.
struct SwiftSpelling {
    let caseName: String
    let values: [TableMapEntry]

    /// The spelling in the text, or `nil` when the text is not one.
    init?(_ text: String) {
        guard let name = Self.identifierPrefix(of: Substring(text)) else {
            return nil
        }
        let rest = text.dropFirst(name.count)
        if rest.isEmpty {
            self.init(caseName: String(name), values: [])
            return
        }
        guard rest.first == "(", rest.last == ")", let arguments = Self.arguments(in: rest.dropFirst().dropLast()) else {
            return nil
        }
        let values = arguments.enumerated().map { position, argument in
            Self.entry(for: argument, at: position)
        }
        guard values.allSatisfy({ $0 != nil }) else {
            return nil
        }
        self.init(caseName: String(name), values: values.compactMap { $0 })
    }

    private init(caseName: String, values: [TableMapEntry]) {
        self.caseName = caseName
        self.values = values
    }

    /// The form that a synthesised `Decodable` enum reads: `[month: [year: 2025, month: 3]]`.
    var keyedForm: TableValue {
        .map([TableMapEntry(key: caseName, value: .map(values))])
    }

    /// The text of each value between the parentheses, split at the commas outside brackets,
    /// braces, parentheses and quotes, or `nil` when they do not balance.
    private static func arguments(in text: Substring) -> [Substring]? {
        guard !text.allSatisfy(\.isWhitespace) else {
            return []
        }
        var arguments: [Substring] = []
        var start = text.startIndex
        var closers: [Character] = []
        var quote: Character?
        for index in text.indices {
            let character = text[index]
            if let open = quote {
                quote = character == open ? nil : open
                continue
            }
            switch character {
            case "'", "\"": quote = character
            case "(": closers.append(")")
            case "[": closers.append("]")
            case "{": closers.append("}")
            case ")", "]", "}":
                guard closers.popLast() == character else {
                    return nil
                }
            case "," where closers.isEmpty:
                arguments.append(text[start..<index])
                start = text.index(after: index)
            default: break
            }
        }
        guard quote == nil, closers.isEmpty else {
            return nil
        }
        return arguments + [text[start...]]
    }

    /// The key and value of one argument: its label, or `_` and its position.
    private static func entry(for argument: Substring, at position: Int) -> TableMapEntry? {
        let trimmed = argument.trimmingCharacters(in: .whitespaces)
        if let label = identifierPrefix(of: Substring(trimmed)) {
            let rest = trimmed.dropFirst(label.count).drop(while: \.isWhitespace)
            if rest.first == ":" {
                return value(of: rest.dropFirst()).map { TableMapEntry(key: String(label), value: $0) }
            }
        }
        return value(of: Substring(trimmed)).map { TableMapEntry(key: "_\(position)", value: $0) }
    }

    /// The value of an argument as a cell reads it; `nil` is the value of a blank cell.
    private static func value(of text: Substring) -> TableValue? {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else {
            return nil
        }
        guard trimmed != "nil" else {
            return .null
        }
        return try? TableParser.parse("Value\n\(trimmed)").rows.first?.values.first
    }

    /// The Swift identifier at the start of the text.
    private static func identifierPrefix(of text: Substring) -> Substring? {
        guard let first = text.first, first == "_" || first.isLetter else {
            return nil
        }
        return text.prefix { $0 == "_" || $0.isLetter || $0.isNumber }
    }
}

/// Whether a `Decodable` type reads the keys of a map before any value, as the synthesised
/// conformance of an enum does to find its case.
enum CaseKeyProbe {
    static func readsACaseKey<T: Decodable>(_ type: T.Type) -> Bool {
        let log = AccessLog()
        _ = try? T(from: ProbeDecoder(log: log))
        return log.first == .allKeys
    }

    fileprivate enum Access {
        case allKeys, other
    }

    fileprivate final class AccessLog {
        private(set) var first: Access?

        func record(_ access: Access) {
            first = first ?? access
        }
    }

    fileprivate struct Stop: Error {}

    fileprivate struct ProbeDecoder: Decoder {
        let log: AccessLog
        var codingPath: [any CodingKey] { [] }
        var userInfo: [CodingUserInfoKey: Any] { [:] }

        func container<Key: CodingKey>(keyedBy type: Key.Type) throws -> KeyedDecodingContainer<Key> {
            KeyedDecodingContainer(ProbeContainer<Key>(log: log))
        }

        func unkeyedContainer() throws -> any UnkeyedDecodingContainer {
            log.record(.other)
            throw Stop()
        }

        func singleValueContainer() throws -> any SingleValueDecodingContainer {
            log.record(.other)
            throw Stop()
        }
    }

    fileprivate struct ProbeContainer<Key: CodingKey>: KeyedDecodingContainerProtocol {
        let log: AccessLog
        var codingPath: [any CodingKey] { [] }

        var allKeys: [Key] {
            log.record(.allKeys)
            return []
        }

        func contains(_ key: Key) -> Bool {
            log.record(.other)
            return false
        }

        func decodeNil(forKey key: Key) throws -> Bool { try stop() }
        func decode<T: Decodable>(_ type: T.Type, forKey key: Key) throws -> T { try stop() }
        func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try stop() }
        func decode(_ type: String.Type, forKey key: Key) throws -> String { try stop() }
        func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try stop() }
        func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try stop() }
        func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try stop() }
        func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try stop() }
        func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try stop() }
        func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try stop() }
        func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try stop() }
        func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try stop() }
        func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try stop() }
        func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try stop() }
        func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try stop() }
        func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try stop() }

        func nestedContainer<NestedKey: CodingKey>(
            keyedBy type: NestedKey.Type,
            forKey key: Key
        ) throws -> KeyedDecodingContainer<NestedKey> { try stop() }

        func nestedUnkeyedContainer(forKey key: Key) throws -> any UnkeyedDecodingContainer { try stop() }
        func superDecoder() throws -> any Decoder { try stop() }
        func superDecoder(forKey key: Key) throws -> any Decoder { try stop() }

        private func stop<T>() throws -> T {
            log.record(.other)
            throw Stop()
        }
    }
}
