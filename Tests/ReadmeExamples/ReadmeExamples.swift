import Foundation
import TableTest
import Testing

// The examples of README.md, verbatim. They import TableTest as a user's tests do, so they
// compile against the public API only. ReadmeSyncTests fails when a README table is not here.

struct Year {
    let value: Int

    init(_ value: Int) {
        self.value = value
    }

    var isLeap: Bool {
        value % 4 == 0 && (value % 100 != 0 || value % 400 == 0)
    }
}

extension Tag {
    @Tag static var calendar: Self
}

struct LeapYearTests {
    @TableTest("""
        Scenario                     | Year | Leap?
        Divisible by 4               | 2004 | true
        Not divisible by 4           | 2001 | false
        Divisible by 100, not by 400 | 1900 | false
        Divisible by 400             | 2000 | true
        """)
    func knowsALeapYear(year: Int, leap: Bool) {
        #expect(Year(year).isLeap == leap)
    }

    @TableTest("Leap years by rule", .tags(.calendar), table: """
        Year | Leap?
        2004 | true
        2001 | false
        """)
    func leapYearsByRule(year: Int, leap: Bool) {
        #expect(Year(year).isLeap == leap)
    }

    @TableTest(.tags(.calendar), table: """
        Year | Leap?
        2000 | true
        """)
    func leapYearsWithATag(year: Int, leap: Bool) {
        #expect(Year(year).isLeap == leap)
    }

    @TableTest("""
        Scenario           | Year               | Leap?
        Not divisible by 4 | {2001, 2002, 2003} | false
        Divisible by 4     | {2004, 2008, 2012} | true
        """)
    func knowsALeapYearForEachExample(year: Int, leap: Bool) {
        #expect(Year(year).isLeap == leap)
    }

    @TableTest("""
        Year | Leap?
        // Divisible by 4
        2004 | true

        // Divisible by 400
        2000 | true
        """)
    func readsCommentsAndBlankLines(year: Int, leap: Bool) {
        #expect(Year(year).isLeap == leap)
    }
}

struct ValueFormatTests {
    @TableTest("""
        Scenario          | Text    | Length?
        Plain text        | Ada     | 3
        A bar in quotes   | 'a | b' | 5
        A quote in quotes | "it's"  | 4
        Empty text        | ''      | 0
        """)
    func countsTheCharacters(text: String, length: Int) {
        #expect(text.count == length)
    }

    @TableTest("""
        Scenario   | Scores    | Bonus               | Total?
        No bonus   | [1, 2, 3] | [:]                 | 6
        With bonus | [10]      | [early: 2, late: 1] | 13
        """)
    func addsTheScoresAndTheBonus(scores: [Int], bonus: [String: Int], total: Int) {
        #expect(scores.reduce(0, +) + bonus.values.reduce(0, +) == total)
    }

    @TableTest("""
        Scenario      | Groups        | Members?
        Two groups    | [[a, b], [c]] | {a, b, c}
        A shared name | [[a, b], [b]] | {a, b}
        No groups     | []            | {}
        """)
    func collectsTheMembers(groups: [[String]], members: Set<String>) {
        #expect(Set(groups.joined()) == members)
    }

    @TableTest("""
        Scenario      | Name | Nickname | Greeting?
        With nickname | Ada  | Countess | Hello, Countess
        No nickname   | Ada  |          | Hello, Ada
        """)
    func greetsByTheNickname(name: String, nickname: String?, greeting: String) {
        #expect("Hello, \(nickname ?? name)" == greeting)
    }
}

/// How a bottle is closed; a cell gives the raw value.
enum Closure: String, Codable {
    case cork
    case screwCap = "screw cap"
}

/// The body of a wine on the WSET scale.
enum Body: String, Codable, CaseIterable {
    case light
    case mediumMinus = "medium(-)"
    case medium
    case mediumPlus = "medium(+)"
    case full

    var rank: Int {
        Body.allCases.firstIndex(of: self)!
    }
}

/// A VDP vineyard tier. The raw values are storage keys, so the tests name the cases.
enum VdpTier: String, CaseIterable {
    case grosseLage = "grosse_lage"
    case ersteLage = "erste_lage"
}

extension VdpTier: TableValueDecodable {}

/// When a wine is ready to drink.
enum Readiness: Codable, Equatable {
    case now
    case from(year: Int)
    case between(Int, Int)

    func allows(_ year: Int) -> Bool {
        switch self {
        case .now: true
        case let .from(first): year >= first
        case let .between(first, last): (first...last).contains(year)
        }
    }
}

struct Bottle: Decodable {
    let wine: String
    let vintage: Int?
}

/// An amount of money, written `12.50 EUR` in a cell.
struct Money: Equatable {
    let cents: Int
    let currency: String
}

extension Money: TableTextDecodable {
    init?(tableText: String) {
        let parts = tableText.split(separator: " ")
        guard parts.count == 2, let amount = Decimal(string: String(parts[0])) else {
            return nil
        }
        self.init(cents: NSDecimalNumber(decimal: amount * 100).intValue, currency: String(parts[1]))
    }
}

/// A shelf of bottles, written as a list of wine names in a cell.
struct Shelf {
    let wines: [String]
}

extension Shelf: TableValueDecodable {
    init(tableValue: TableValue) throws {
        guard case .list(let elements) = tableValue else {
            throw TableValueConversionError("A shelf is a list of wines")
        }
        self.init(wines: try elements.map { try $0.converted(to: String.self) })
    }
}

/// A cellar whose cell names only the fields it sets.
struct Cellar {
    var racks = 1
    var bottlesPerRack = 120

    var capacity: Int { racks * bottlesPerRack }
}

extension Cellar: TableValueDecodable {
    init(tableValue: TableValue) throws {
        self = try tableValue.readingFields { fields in
            var cellar = Cellar()
            cellar.racks = try fields.value("racks") ?? cellar.racks
            cellar.bottlesPerRack = try fields.value("bottlesPerRack") ?? cellar.bottlesPerRack
            return cellar
        }
    }
}

struct ConversionTests {
    @TableTest("""
        Scenario            | Tasted                    | Window                  | Inside?
        A day in the window | 2026-03-14                | 2025-01-01...2030-12-31 | true
        Before the window   | 2024-12-31T23:00:00+01:00 | 2025-01-01...2030-12-31 | false
        """)
    func knowsTheDrinkingWindow(tasted: Date, window: ClosedRange<Date>, inside: Bool) {
        #expect(window.contains(tasted) == inside)
    }

    @TableTest("""
        Pause            | Milliseconds?
        1.5 seconds      | 1500
        250 milliseconds | 250
        """)
    func readsADuration(pause: Duration, milliseconds: Int64) {
        #expect(pause == .milliseconds(milliseconds))
    }

    @TableTest("""
        Closure   | Reseals?
        cork      | false
        screw cap | true
        """)
    func knowsAClosureThatReseals(closure: Closure, reseals: Bool) {
        #expect((closure == .screwCap) == reseals)
    }

    @TableTest("""
        Lowest    | Highest | Wine      | Inside?
        medium(-) | medium  | medium(+) | false
        light     | full    | medium(-) | true
        """)
    func placesTheBodyInASpan(lowest: Body, highest: Body, wine: Body, inside: Bool) {
        #expect((lowest.rank...highest.rank).contains(wine.rank) == inside)
    }

    @TableTest("""
        Tier       | Top tier?
        grosseLage | true
        ersteLage  | false
        """)
    func knowsTheTopTier(tier: VdpTier, topTier: Bool) {
        #expect((tier == .grosseLage) == topTier)
    }

    @TableTest("""
        Scenario        | Readiness           | Year | Drink?
        Ready now       | now                 | 2026 | true
        Before its year | from(year: 2028)    | 2026 | false
        Inside the span | between(2025, 2030) | 2027 | true
        """)
    func allowsTheYearsItIsReady(readiness: Readiness, year: Int, drink: Bool) {
        #expect(readiness.allows(year) == drink)
    }

    @TableTest("""
        Readinesses                                 | Any now?
        ['from(year: 2028)', now]                   | true
        ['between(2025, 2030)', 'from(year: 2026)'] | false
        """)
    func findsAWineReadyNow(readinesses: [Readiness], anyNow: Bool) {
        #expect(readinesses.contains(.now) == anyNow)
    }

    @TableTest("""
        Bottles                                                         | Oldest?
        [[wine: Barolo, vintage: 2015], [wine: Chablis, vintage: 2020]] | 2015
        [[wine: Cava]]                                                  |
        """)
    func findsTheOldestVintage(bottles: [Bottle], oldest: Int?) {
        #expect(bottles.compactMap(\.vintage).min() == oldest)
    }

    @TableTest("""
        Price     | Quantity | Total?
        12.50 EUR | 2        | 25.00 EUR
        0.99 USD  | 3        | 2.97 USD
        """)
    func multipliesThePrice(price: Money, quantity: Int, total: Money) {
        #expect(Money(cents: price.cents * quantity, currency: price.currency) == total)
    }

    @TableTest("""
        Shelf             | Bottles?
        [Barolo, Chablis] | 2
        []                | 0
        """)
    func countsTheBottlesOnAShelf(shelf: Shelf, bottles: Int) {
        #expect(shelf.wines.count == bottles)
    }

    @TableTest("""
        Cellar                          | Capacity?
        [racks: 3]                      | 360
        [racks: 2, bottlesPerRack: 100] | 200
        [:]                             | 120
        """)
    func holdsTheBottlesOfItsRacks(cellar: Cellar, capacity: Int) {
        #expect(cellar.capacity == capacity)
    }
}

struct EscapeSequenceTests {
    @TableTest("""
        Scenario  | Text       | Length?
        Tab       | a\tb       | 3
        Backslash | path\\file | 9
        Unicode   | \u{41}B    | 2
        """)
    func countsTheProcessedEscapes(text: String, length: Int) {
        #expect(text.count == length)
    }

    @TableTest(#"""
        Scenario  | Text       | Length?
        Tab       | a\tb       | 4
        Backslash | path\\file | 10
        """#)
    func countsTheRawEscapes(text: String, length: Int) {
        #expect(text.count == length)
    }
}
