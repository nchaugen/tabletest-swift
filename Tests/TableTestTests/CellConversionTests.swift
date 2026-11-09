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
        (scenario: "Map with enum keys", cell: "[red: 1, green: 2]", conversion: .to([Colour.red: 1, .green: 2])),
        (scenario: "Map with enum keys in a struct", cell: "[counts: [red: 1]]",
         conversion: .to(Palette(counts: [.red: 1]))),
        (scenario: "Map to a struct", cell: "[name: Ada, age: 36]", conversion: .to(Person(name: "Ada", age: 36))),
        (scenario: "Nested lists", cell: "[[1, 2], [3]]", conversion: .to([[1, 2], [3]])),
        (scenario: "Own conversion inside a Decodable struct", cell: "[item: 5]",
         conversion: .to(Boxed(item: Doubled(value: 10)))),
        (scenario: "Own conversion before Decodable", cell: "5", conversion: .to(Doubled(value: 10))),
        (scenario: "Case name of a Decodable enum", cell: "grosseLage", conversion: .to(Site.grosseLage)),
        (scenario: "Case name of a number raw-value enum", cell: "high", conversion: .to(Level.high)),
        (scenario: "Case name in a Decodable struct", cell: "[site: ersteLage]",
         conversion: .to(Vineyard(site: .ersteLage))),
        (scenario: "List of case names", cell: "[ersteLage, grosseLage]", conversion: .to([Site.ersteLage, .grosseLage])),
        (scenario: "Map with case-name keys", cell: "[grosseLage: 1]", conversion: .to([Site.grosseLage: 1])),
        (scenario: "Map with coding-key case names", cell: "[topTier: 1]", conversion: .to([Tier.topTier: 1])),
    ])
    func convertsToADecodableType(scenario: String, cell: String, conversion: Conversion) throws {
        let result = try conversion.convert(cellValue(cell))

        #expect(result.matches, "converted to \(result.actual)")
    }

    @Test("Converts a cell with a built-in conversion", arguments: [
        (scenario: "Date at midnight UTC", cell: "2025-03-14", conversion: Conversion.to(Date(timeIntervalSince1970: 1741910400))),
        (scenario: "Date and time in UTC", cell: "2025-03-14T10:30:00Z", conversion: .to(Date(timeIntervalSince1970: 1741948200))),
        (scenario: "Date and time with an offset", cell: "2025-03-14T10:30:00+01:00",
         conversion: .to(Date(timeIntervalSince1970: 1741944600))),
        (scenario: "Fraction of a second", cell: "2025-03-14T10:30:00.5Z", conversion: .to(Date(timeIntervalSince1970: 1741948200.5))),
        (scenario: "List of dates", cell: "[2025-01-01, 2025-03-14]",
         conversion: .to([Date(timeIntervalSince1970: 1735689600), Date(timeIntervalSince1970: 1741910400)])),
        (scenario: "Date in a struct", cell: "[opened: 2025-03-14]", conversion: .to(Tasting(opened: Date(timeIntervalSince1970: 1741910400)))),
        (scenario: "Closed range", cell: "2028...2030", conversion: .to(2028...2030)),
        (scenario: "Half-open range", cell: "2028..<2031", conversion: .to(2028..<2031)),
        (scenario: "Closed range as a list", cell: "[2028, 2030]", conversion: .to(2028...2030)),
        (scenario: "Range of negative numbers", cell: "-5...-1", conversion: .to(-5 ... -1)),
        (scenario: "Range of fractions", cell: "1.5...2.5", conversion: .to(1.5...2.5)),
        (scenario: "Range of dates", cell: "2025-01-01...2025-03-14",
         conversion: .to(Date(timeIntervalSince1970: 1735689600)...Date(timeIntervalSince1970: 1741910400))),
        (scenario: "Range in a struct", cell: "[years: 2028...2030]", conversion: .to(DrinkWindow(years: 2028...2030))),
        (scenario: "Blank cell to an optional range", cell: "", conversion: .to(ClosedRange<Int>?.none)),
        (scenario: "Character", cell: "a", conversion: .plain(Character("a"))),
        (scenario: "Character of two scalars", cell: "e\u{301}", conversion: .plain(Character("e\u{301}"))),
        (scenario: "Quoted space", cell: "' '", conversion: .plain(Character(" "))),
        (scenario: "List of characters", cell: "[a, b]", conversion: .plain([Character("a"), Character("b")])),
    ])
    func convertsWithABuiltInConversion(scenario: String, cell: String, conversion: Conversion) throws {
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

    @Test("Converts a cell with the type's text conversion", arguments: [
        (scenario: "Amount and currency", cell: "12.50 EUR", conversion: Conversion.own(Price(cents: 1250, currency: "EUR"))),
        (scenario: "List of amounts", cell: "[1.00 EUR, 2.50 USD]",
         conversion: .own([Price(cents: 100, currency: "EUR"), Price(cents: 250, currency: "USD")])),
        (scenario: "Blank cell to an optional", cell: "", conversion: .own(Price?.none)),
    ])
    func convertsWithTheTypesTextConversion(scenario: String, cell: String, conversion: Conversion) throws {
        let result = try conversion.convert(cellValue(cell))

        #expect(result.matches, "converted to \(result.actual)")
    }

    @Test("Converts part of a cell with the library's rules", arguments: [
        (scenario: "Number", cell: "42", conversion: Conversion.part(42)),
        (scenario: "Decimal amount", cell: "12.50", conversion: .part(Decimal(string: "12.50")!)),
        (scenario: "Case name of an enum that is not Decodable", cell: "grandCru", conversion: .part(Band.grandCru)),
        (scenario: "List of case names", cell: "[fruit, oak]", conversion: .part([Note.fruit, .oak])),
        (scenario: "Text conversion", cell: "1.00 EUR", conversion: .part(Price(cents: 100, currency: "EUR"))),
        (scenario: "Map read by a hand-written conversion", cell: "[band: premierCru, price: 9.00 EUR]",
         conversion: .part(Listing(band: .premierCru, price: Price(cents: 900, currency: "EUR")))),
    ])
    func convertsPartOfACell(scenario: String, cell: String, conversion: Conversion) throws {
        let result = try conversion.convert(cellValue(cell))

        #expect(result.matches, "converted to \(result.actual)")
    }

    @Test("Converts the Swift spelling of an enum case", arguments: [
        (scenario: "One unlabelled value", cell: "year(2025)", conversion: Conversion.to(Vintage.year(2025))),
        (scenario: "Labelled values", cell: "month(year: 2025, month: 3)", conversion: .to(Vintage.month(year: 2025, month: 3))),
        (scenario: "No values", cell: "nonVintage", conversion: .to(Vintage.nonVintage)),
        (scenario: "Unlabelled and labelled values", cell: "span(2020, to: 2025)", conversion: .to(Vintage.span(2020, to: 2025))),
        (scenario: "Keyed form", cell: "[year: [_0: 2025]]", conversion: .to(Vintage.year(2025))),
        (scenario: "Case of another enum as a value", cell: "since(month(year: 2025, month: 3))",
         conversion: .to(Window.since(.month(year: 2025, month: 3)))),
        (scenario: "Optional value of nil", cell: "open(until: nil)", conversion: .to(Window.open(until: nil))),
        (scenario: "Optional value", cell: "open(until: 2030)", conversion: .to(Window.open(until: 2030))),
        (scenario: "Quoted text with a comma", cell: "note('dry, firm')", conversion: .to(Window.note("dry, firm"))),
        (scenario: "List of values", cell: "notes([a, b])", conversion: .to(Window.notes(["a", "b"]))),
        (scenario: "In a struct", cell: "[vintage: year(2025)]", conversion: .to(Bottle(vintage: .year(2025)))),
        (scenario: "In a list", cell: "[year(2025), nonVintage]", conversion: .to([Vintage.year(2025), .nonVintage])),
        (scenario: "Quoted in a list", cell: "['month(year: 2025, month: 3)', nonVintage]",
         conversion: .to([Vintage.month(year: 2025, month: 3), .nonVintage])),
        (scenario: "In a set", cell: "{year(2015), nonVintage}", conversion: .to(Set([Vintage.year(2015), .nonVintage]))),
        (scenario: "Blank cell to an optional", cell: "", conversion: .to(Vintage?.none)),
    ])
    func convertsTheSwiftSpellingOfAnEnumCase(scenario: String, cell: String, conversion: Conversion) throws {
        let result = try conversion.convert(cellValue(cell))

        #expect(result.matches, "converted to \(result.actual)")
    }

    @Test("Converts a cell to an enum that is not Decodable", arguments: [
        (scenario: "Case name of a raw-value enum", cell: "grandCru", conversion: Conversion.plain(Band.grandCru)),
        (scenario: "Case name of a number raw-value enum", cell: "reference", conversion: .plain(Source.reference)),
        (scenario: "Raw value of an enum with no case list", cell: "B", conversion: .plain(Grade.good)),
        (scenario: "Case name to an optional", cell: "premierCru", conversion: .plain(Band?.some(.premierCru))),
        (scenario: "Blank cell to an optional", cell: "", conversion: .plain(Band?.none)),
        (scenario: "List of case names", cell: "[grandCru, premierCru]", conversion: .plain([Band.grandCru, .premierCru])),
        (scenario: "Case name of an enum with no raw value", cell: "oak", conversion: .plain(Note.oak)),
        (scenario: "Set of case names", cell: "{fruit, oak}", conversion: .plain(Set([Note.fruit, .oak]))),
        (scenario: "Map with enum keys", cell: "[fruit: grandCru]", conversion: .plain([Note.fruit: Band.grandCru])),
        (scenario: "Map with text keys", cell: "[a: oak]", conversion: .plain(["a": Note.oak])),
        (scenario: "Nested optional list", cell: "[oak]", conversion: .plain([Note]?.some([.oak]))),
    ])
    func convertsToAnEnumThatIsNotDecodable(scenario: String, cell: String, conversion: Conversion) throws {
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
        (cell: "grand_cru", target: .plain(Band.self),
         message: "Band has no case named `grand_cru`; the case with this raw value is `grandCru`"),
        (cell: "grosse_lage", target: .to(Site.self),
         message: "Site has no case named `grosse_lage`; the case with this raw value is `grosseLage`"),
        (cell: "2", target: .to(Level.self), message: "Level has no case named `2`; the case with this raw value is `high`"),
        (cell: "[site: erste_lage]", target: .to(Vineyard.self),
         message: "Site has no case named `erste_lage`; the case with this raw value is `ersteLage` (at `site`)"),
        (cell: "[1]", target: .to(Site.self), message: "Cannot convert `[1]` to Site"),
        (cell: "E", target: .plain(Grade.self), message: "Grade has no case with the raw value `E`"),
        (cell: "wood", target: .plain(Note.self), message: "Note has no case named `wood`"),
        (cell: "[oak, wood]", target: .plain([Note].self), message: "Note has no case named `wood`"),
        (cell: "[oak]", target: .plain(Note.self), message: "Cannot convert `[oak]` to Note"),
        (cell: "12.50", target: .own(Price.self), message: "Cannot convert `12.50` to Price"),
        (cell: "[1.00 EUR, x]", target: .own([Price].self), message: "Cannot convert `x` to Price"),
        (cell: "", target: .own(Price.self), message: "Cannot convert a blank cell to Price"),
        (cell: "[1.00 EUR]", target: .own(Price.self), message: "Cannot convert `[1.00 EUR]` to Price"),
        (cell: "[1, x]", target: .part([Int].self), message: "Cannot convert `x` to Int (at `[1]`)"),
        (cell: "[band: grand, price: 9.00 EUR]", target: .part(Listing.self),
         message: "Band has no case named `grand`"),
        (cell: "yeer(2025)", target: .to(Vintage.self), message: "Vintage has no case named `yeer`"),
        (cell: "year(abc)", target: .to(Vintage.self), message: "Cannot convert `abc` to Int (at `year._0`)"),
        (cell: "year(2025", target: .to(Vintage.self), message: "Cannot convert `year(2025` to Vintage"),
        (cell: "[month(year: 2025, month: 3)]", target: .to([Vintage].self),
         message: "Cannot convert `[month(year: 2025, month: 3)]` to a list or a set: quote an element that has a comma or a colon"),
        (cell: "Ada", target: .to(Person.self), message: "Cannot convert `Ada` to a map"),
        (cell: "2025-3-14", target: .to(Date.self), message: "Cannot convert `2025-3-14` to Date"),
        (cell: "2025-02-30", target: .to(Date.self), message: "Cannot convert `2025-02-30` to Date"),
        (cell: "1741910400", target: .to(Date.self), message: "Cannot convert `1741910400` to Date"),
        (cell: "2025-03-14T10:30:00", target: .to(Date.self),
         message: "Cannot convert `2025-03-14T10:30:00` to Date: add a zone, such as `Z` or `+01:00`"),
        (cell: "2030...2028", target: .to(ClosedRange<Int>.self),
         message: "Cannot convert `2030...2028` to ClosedRange<Int>: the lower bound is above the upper bound"),
        (cell: "2031..<2028", target: .to(Range<Int>.self),
         message: "Cannot convert `2031..<2028` to Range<Int>: the lower bound is above the upper bound"),
        (cell: "2028...x", target: .to(ClosedRange<Int>.self), message: "Cannot convert `x` to Int"),
        (cell: "2028", target: .to(ClosedRange<Int>.self), message: "Cannot convert `2028` to ClosedRange<Int>"),
        (cell: "2028...2030", target: .to(Range<Int>.self), message: "Cannot convert `2028...2030` to Range<Int>"),
        (cell: "ab", target: .plain(Character.self), message: "Cannot convert `ab` to Character"),
        (cell: "", target: .plain(Character.self), message: "Cannot convert a blank cell to Character"),
        (cell: "x", target: .plain(Opaque.self),
         message: "Opaque does not convert from a cell: make it Decodable or TableValueDecodable"),
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

    /// Converts a type that only `RawRepresentable` or `CaseIterable` describes.
    static func plain<T: Equatable & Sendable>(_ expected: T) -> Conversion {
        Conversion(testDescription: "\(T.self) \(expected)") { value in
            let actual = try TableValueDecoding.convert(value, to: T.self)
            return (actual == expected, String(describing: actual))
        }
    }

    /// Converts with ``TableValue/converted(to:)``, the public entry for a hand-written conversion.
    static func part<T: Equatable & Sendable>(_ expected: T) -> Conversion {
        Conversion(testDescription: "\(T.self) \(expected)") { value in
            let actual = try value.converted(to: T.self)
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

    static func to<T: Decodable & Sendable>(_ type: T.Type) -> FailedConversion {
        FailedConversion(testDescription: "\(T.self)") { _ = try TableValueDecoding.decode($0, as: T.self) }
    }

    static func plain<T>(_ type: T.Type) -> FailedConversion {
        FailedConversion(testDescription: "\(T.self)") { _ = try TableValueDecoding.convert($0, to: T.self) }
    }

    static func part<T>(_ type: T.Type) -> FailedConversion {
        FailedConversion(testDescription: "\(T.self)") { _ = try $0.converted(to: T.self) }
    }

    static func own<T: TableValueDecodable & Sendable>(_ type: T.Type) -> FailedConversion {
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

/// A `Decodable` enum with a case list, which a cell names by its case name.
enum Site: String, Decodable, CaseIterable, Sendable {
    case grosseLage = "grosse_lage"
    case ersteLage = "erste_lage"
}

enum Level: Int, Decodable, CaseIterable, Sendable {
    case low = 1, high = 2
}

/// An enum that `Dictionary`'s own `Decodable` conformance reads by its raw value.
enum Tier: String, Decodable, CaseIterable, CodingKeyRepresentable, Sendable {
    case topTier = "top_tier"
}

struct Vineyard: Decodable, Equatable, Sendable {
    let site: Site
}

/// A `Codable` enum with associated values, which a cell names as Swift spells the case.
enum Vintage: Codable, Hashable, Sendable {
    case year(Int)
    case month(year: Int, month: Int)
    case span(Int, to: Int)
    case nonVintage
}

enum Window: Codable, Equatable, Sendable {
    case since(Vintage)
    case open(until: Int?)
    case note(String)
    case notes([String])
}

struct Bottle: Decodable, Equatable, Sendable {
    let vintage: Vintage
}

struct Tasting: Decodable, Equatable, Sendable {
    let opened: Date
}

struct DrinkWindow: Decodable, Equatable, Sendable {
    let years: ClosedRange<Int>
}

struct Palette: Decodable, Equatable, Sendable {
    let counts: [Colour: Int]
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

/// An amount in cents with its currency, written as `12.50 EUR`, read from the text of a cell.
struct Price: TableCellText, Hashable, Sendable {
    let cents: Int
    let currency: String

    init(cents: Int, currency: String) {
        self.cents = cents
        self.currency = currency
    }

    init?(tableText: String) {
        let parts = tableText.split(separator: " ")
        guard parts.count == 2, let cents = Int(parts[0].replacingOccurrences(of: ".", with: "")) else {
            return nil
        }
        self.init(cents: cents, currency: String(parts[1]))
    }
}

/// A struct that reads a map by hand, and converts each value with the library's rules.
struct Listing: TableValueDecodable, Equatable, Sendable {
    let band: Band
    let price: Price

    init(band: Band, price: Price) {
        self.band = band
        self.price = price
    }

    init(tableValue: TableValue) throws {
        guard case .map(let entries) = tableValue,
              let band = entries.first(where: { $0.key == "band" }),
              let price = entries.first(where: { $0.key == "price" })
        else {
            throw TableValueConversionError("A listing is a map with a band and a price")
        }
        self.init(band: try band.value.converted(to: Band.self), price: try price.value.converted(to: Price.self))
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

/// A raw-value enum with no case list.
enum Grade: String, Sendable {
    case good = "B"
}

/// A number raw-value enum that is not `Decodable`.
enum Source: Int, CaseIterable, Sendable {
    case tastings, reference
}

/// A type with no conversion at all.
struct Opaque: Sendable {}
