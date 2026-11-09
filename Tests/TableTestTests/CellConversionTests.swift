import Foundation
import Testing
@testable import TableTest

/// Each case writes the cell as it reads in a table. The test parses it as the only cell of a
/// data row and converts the parsed value to the type the expectation names.
@Suite("Cell conversion")
struct CellConversionTests {
    @Test("Converts a cell to a Decodable type", arguments: [
        (scenario: "Whole number", cell: "42", conversion: Conversion.to(42)),
        (scenario: "Negative number in a small type", cell: "-12", conversion: .to(Int8(-12))),
        (scenario: "Largest unsigned byte", cell: "255", conversion: .to(UInt8(255))),
        (scenario: "Fraction", cell: "3.25", conversion: .to(3.25)),
        (scenario: "Single-precision fraction", cell: "2.5", conversion: .to(Float(2.5))),
        (scenario: "Boolean in capitals", cell: "TRUE", conversion: .to(true)),
        (scenario: "Boolean in lower case", cell: "false", conversion: .to(false)),
        (scenario: "Text with a space", cell: "Ada Lovelace", conversion: .to("Ada Lovelace")),
        (scenario: "Quoted empty text", cell: "''", conversion: .to("")),
        (scenario: "Decimal amount", cell: "12.50", conversion: .to(Decimal(string: "12.50")!)),
        (scenario: "Web address", cell: "https://tabletest.org/spec?page=1",
         conversion: .to(URL(string: "https://tabletest.org/spec?page=1")!)),
        (scenario: "Enum with text raw values", cell: "green", conversion: .to(Colour.green)),
        (scenario: "Enum with number raw values", cell: "2", conversion: .to(Priority.high)),
        (scenario: "Blank cell to an optional", cell: "", conversion: .to(Int?.none)),
        (scenario: "Number to an optional", cell: "7", conversion: .to(Int?(7))),
        (scenario: "List", cell: "[1, 2, 3]", conversion: .to([1, 2, 3])),
        (scenario: "Set", cell: "{b, a}", conversion: .to(Set(["a", "b"]))),
        (scenario: "List with a repeated element to a set", cell: "[a, a]", conversion: .to(Set(["a"]))),
        (scenario: "Map with text keys", cell: "[a: 1, b: 2]", conversion: .to(["a": 1, "b": 2])),
        (scenario: "Map with number keys", cell: "[1: one, 2: two]", conversion: .to([1: "one", 2: "two"])),
        (scenario: "Map to a struct", cell: "[name: Ada, age: 36]", conversion: .to(Person(name: "Ada", age: 36))),
        (scenario: "Nested lists", cell: "[[1, 2], [3]]", conversion: .to([[1, 2], [3]])),
        (scenario: "Own conversion inside a Decodable struct", cell: "[item: 5]",
         conversion: .to(Boxed(item: Doubled(value: 10)))),
        (scenario: "Own conversion before Decodable", cell: "5", conversion: .to(Doubled(value: 10))),
    ])
    func convertsToADecodableType(scenario: String, cell: String, conversion: Conversion) throws {
        let result = try conversion.convert(cellValue(cell))

        #expect(result.matches, "converted to \(result.actual)")
    }

    @Test("Converts a cell with the type's own conversion", arguments: [
        (scenario: "Amount and currency", cell: "12.50 EUR", conversion: Conversion.own(Money(cents: 1250, currency: "EUR"))),
        (scenario: "List of amounts", cell: "[1.00 EUR, 2.50 USD]",
         conversion: .own([Money(cents: 100, currency: "EUR"), Money(cents: 250, currency: "USD")])),
        (scenario: "Set of amounts", cell: "{1.00 EUR}", conversion: .own(Set([Money(cents: 100, currency: "EUR")]))),
        (scenario: "Map of amounts", cell: "[rent: 900.00 EUR]",
         conversion: .own(["rent": Money(cents: 90000, currency: "EUR")])),
        (scenario: "Blank cell to an optional", cell: "", conversion: .own(Money?.none)),
        (scenario: "Case name of an enum with no raw value", cell: "south", conversion: .own(Compass.south)),
        (scenario: "Parsed value unconverted", cell: "[a: [1]]",
         conversion: .own(TableValue.map([TableMapEntry(key: "a", value: .list([.string("1")]))]))),
    ])
    func convertsWithTheTypesOwnConversion(scenario: String, cell: String, conversion: Conversion) throws {
        let result = try conversion.convert(cellValue(cell))

        #expect(result.matches, "converted to \(result.actual)")
    }

    @Test("Refuses a cell that does not convert, and says why", arguments: [
        (cell: "abc", target: FailedConversion.to(Int.self), message: "Cannot convert `abc` to Int"),
        (cell: "300", target: .to(UInt8.self), message: "Cannot convert `300` to UInt8"),
        (cell: "", target: .to(Int.self), message: "Cannot convert a blank cell to Int"),
        (cell: "maybe", target: .to(Bool.self), message: "Cannot convert `maybe` to Bool"),
        (cell: "[1, 2]", target: .to(Int.self), message: "Cannot convert `[1, 2]` to Int"),
        (cell: "abc", target: .to([Int].self), message: "Cannot convert `abc` to a list or a set"),
        (cell: "[1, x]", target: .to([Int].self), message: "Cannot convert `x` to Int (at `[1]`)"),
        (cell: "12,50", target: .to(Decimal.self), message: "Cannot convert `12,50` to Decimal"),
        (cell: "purple", target: .to(Colour.self),
         message: "Cannot initialize Colour from invalid String value purple"),
        (cell: "[name: Ada]", target: .to(Person.self), message: "The map has no key `age`"),
        (cell: "{é, e\u{301}}", target: .to(Set<String>.self),
         message: "Cannot convert `{é, e\u{301}}` to Set<String>: Swift treats two of its elements as equal"),
        (cell: "[é: 1, e\u{301}: 2]", target: .to([String: Int].self),
         message: "Cannot convert `[é: 1, e\u{301}: 2]` to Dictionary<String, Int>: Swift treats two of its elements as equal"),
        (cell: "west", target: .own(Compass.self), message: "Compass has no case named `west`"),
    ])
    func refusesACellThatDoesNotConvert(cell: String, target: FailedConversion, message: String) throws {
        #expect(target.message(converting: try cellValue(cell)) == message)
    }

    /// The parsed value of a cell, written as the first cell of a data row.
    private func cellValue(_ cell: String) throws -> TableValue {
        try TableParser.parse("Value | End\n\(cell) | end").rows[0].values[0]
    }
}

/// A conversion to one type, and the value it must give.
struct Conversion: Sendable, CustomTestStringConvertible {
    let testDescription: String
    let convert: @Sendable (TableValue) throws -> (matches: Bool, actual: String)

    /// Converts through `Decodable`, where a type's own conversion still wins at run time.
    static func to<T: Decodable & Equatable & Sendable>(_ expected: T) -> Conversion {
        Conversion(testDescription: "\(T.self) \(expected)") { value in
            let actual = try TableValueDecoding.decode(value, as: T.self)
            return (actual == expected, String(describing: actual))
        }
    }

    /// Converts through ``TableValueDecodable``.
    static func own<T: TableValueDecodable & Equatable & Sendable>(_ expected: T) -> Conversion {
        Conversion(testDescription: "\(T.self) \(expected)") { value in
            let actual = try TableValueDecoding.decode(value, as: T.self)
            return (actual == expected, String(describing: actual))
        }
    }
}

/// A conversion that must fail, and the message of its error.
struct FailedConversion: Sendable, CustomTestStringConvertible {
    let testDescription: String
    let attempt: @Sendable (TableValue) throws -> Void

    static func to<T: Decodable>(_ type: T.Type) -> FailedConversion {
        FailedConversion(testDescription: "\(T.self)") { _ = try TableValueDecoding.decode($0, as: T.self) }
    }

    static func own<T: TableValueDecodable>(_ type: T.Type) -> FailedConversion {
        FailedConversion(testDescription: "\(T.self)") { _ = try TableValueDecoding.decode($0, as: T.self) }
    }

    /// The message of the conversion error, or `nil` when the value converts.
    func message(converting value: TableValue) -> String? {
        do {
            try attempt(value)
            return nil
        } catch {
            return TableValueDecoding.message(of: error)
        }
    }
}

enum Colour: String, Decodable, Sendable {
    case red, green
}

enum Priority: Int, Decodable, Sendable {
    case low = 1, high = 2
}

struct Person: Decodable, Equatable, Sendable {
    let name: String
    let age: Int
}

/// An amount in cents with its currency, written as `12.50 EUR` in a cell.
struct Money: TableValueDecodable, Hashable, Sendable {
    let cents: Int
    let currency: String

    init(cents: Int, currency: String) {
        self.cents = cents
        self.currency = currency
    }

    init(tableValue: TableValue) throws {
        guard case .string(let text) = tableValue else {
            throw TableValueConversionError("Money is written as an amount and a currency")
        }
        let parts = text.split(separator: " ")
        guard parts.count == 2, let cents = Int(parts[0].replacingOccurrences(of: ".", with: "")) else {
            throw TableValueConversionError("Cannot read `\(text)` as money")
        }
        self.init(cents: cents, currency: String(parts[1]))
    }
}

enum Compass: TableValueDecodable, CaseIterable, Equatable, Sendable {
    case north, south
}

/// Doubles the number in its own conversion, so a test can see which conversion ran.
struct Doubled: Decodable, TableValueDecodable, Equatable, Sendable {
    let value: Int

    init(value: Int) {
        self.value = value
    }

    init(from decoder: any Decoder) throws {
        value = try Int(from: decoder)
    }

    init(tableValue: TableValue) throws {
        guard case .string(let text) = tableValue, let number = Int(text) else {
            throw TableValueConversionError("Doubled needs a number")
        }
        value = 2 * number
    }
}

struct Boxed: Decodable, Equatable, Sendable {
    let item: Doubled
}
