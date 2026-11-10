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

/// A diet; a cell gives the raw value.
enum Diet: String, Codable {
    case vegetarian
    case glutenFree = "gluten-free"
}

/// How hot a dish is, mildest first.
enum Heat: String, Codable, CaseIterable {
    case mild
    case medium
    case hot
    case extraHot = "extra hot"

    var rank: Int {
        Heat.allCases.firstIndex(of: self)!
    }
}

/// A cut of meat. The raw values are a supplier's codes, so the tests name the cases.
enum Cut: String, CaseIterable {
    case sirloin = "SIRLOIN_STEAK"
    case brisket = "BRISKET"
}

extension Cut: TableValueDecodable {}

/// When a kitchen alarm rings.
enum Alarm: Codable, Equatable {
    case now
    case after(minutes: Int)
    case between(Int, Int)

    func rings(atMinute minute: Int) -> Bool {
        switch self {
        case .now: true
        case let .after(minutes): minute >= minutes
        case let .between(first, last): (first...last).contains(minute)
        }
    }
}

struct Recipe: Decodable {
    let dish: String
    let minutes: Int?
}

/// An amount of an ingredient, written `250 g` or `1.5 kg` in a cell.
struct Quantity: Equatable {
    let grams: Int
}

extension Quantity: TableTextDecodable {
    init?(tableText: String) {
        let parts = tableText.split(separator: " ")
        guard parts.count == 2, let amount = Double(parts[0]),
              let gramsPerUnit = ["g": 1.0, "kg": 1000.0][String(parts[1])] else {
            return nil
        }
        self.init(grams: Int((amount * gramsPerUnit).rounded()))
    }
}

/// A pantry, written as a list of items in a cell.
struct Pantry {
    let items: [String]
}

extension Pantry: TableValueDecodable {
    init(tableValue: TableValue) throws {
        guard case .list(let elements) = tableValue else {
            throw TableValueConversionError("A pantry is a list of items")
        }
        self.init(items: try elements.map { try $0.converted(to: String.self) })
    }
}

/// A baking tray whose cell names only the fields it sets.
struct Tray {
    var rows = 3
    var cookiesPerRow = 4

    var capacity: Int { rows * cookiesPerRow }
}

extension Tray: TableValueDecodable {
    init(tableValue: TableValue) throws {
        self = try tableValue.readingFields { fields in
            var tray = Tray()
            tray.rows = try fields.value("rows") ?? tray.rows
            tray.cookiesPerRow = try fields.value("cookiesPerRow") ?? tray.cookiesPerRow
            return tray
        }
    }
}

struct ConversionTests {
    @TableTest("""
        Scenario                   | Eaten                     | Shelf life              | Inside?
        Before the best-before day | 2026-03-14                | 2026-03-01...2026-03-31 | true
        The day before buying      | 2026-02-28T23:00:00+01:00 | 2026-03-01...2026-03-31 | false
        """)
    func knowsTheShelfLife(eaten: Date, shelfLife: ClosedRange<Date>, inside: Bool) {
        #expect(shelfLife.contains(eaten) == inside)
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
        Diet        | Without wheat?
        vegetarian  | false
        gluten-free | true
        """)
    func knowsADietWithoutWheat(diet: Diet, withoutWheat: Bool) {
        #expect((diet == .glutenFree) == withoutWheat)
    }

    @TableTest("""
        Lowest | Highest   | Dish   | Inside?
        mild   | medium    | hot    | false
        mild   | extra hot | medium | true
        """)
    func placesTheHeatInARange(lowest: Heat, highest: Heat, dish: Heat, inside: Bool) {
        #expect((lowest.rank...highest.rank).contains(dish.rank) == inside)
    }

    @TableTest("""
        Cut     | For the grill?
        sirloin | true
        brisket | false
        """)
    func knowsACutForTheGrill(cut: Cut, forTheGrill: Bool) {
        #expect((cut == .sirloin) == forTheGrill)
    }

    @TableTest("""
        Scenario        | Alarm              | Minute | Rings?
        Rings now       | now                | 10     | true
        Before its time | after(minutes: 12) | 10     | false
        Inside the span | between(8, 12)     | 10     | true
        """)
    func ringsAtItsMinute(alarm: Alarm, minute: Int, rings: Bool) {
        #expect(alarm.rings(atMinute: minute) == rings)
    }

    @TableTest("""
        Alarms                                  | Any now?
        ['after(minutes: 12)', now]             | true
        ['between(8, 12)', 'after(minutes: 5)'] | false
        """)
    func findsAnAlarmRingingNow(alarms: [Alarm], anyNow: Bool) {
        #expect(alarms.contains(.now) == anyNow)
    }

    @TableTest("""
        Recipes                                                       | Longest?
        [[dish: Pancakes, minutes: 20], [dish: Risotto, minutes: 35]] | 35
        [[dish: Salad]]                                               |
        """)
    func findsTheLongestRecipe(recipes: [Recipe], longest: Int?) {
        #expect(recipes.compactMap(\.minutes).max() == longest)
    }

    @TableTest("""
        Per serving | Servings | Total?
        250 g       | 2        | 500 g
        0.4 kg      | 3        | 1.2 kg
        """)
    func scalesTheQuantity(perServing: Quantity, servings: Int, total: Quantity) {
        #expect(Quantity(grams: perServing.grams * servings) == total)
    }

    @TableTest("""
        Pantry         | Items?
        [flour, sugar] | 2
        []             | 0
        """)
    func countsTheItemsInThePantry(pantry: Pantry, items: Int) {
        #expect(pantry.items.count == items)
    }

    @TableTest("""
        Tray                        | Capacity?
        [rows: 4]                   | 16
        [rows: 2, cookiesPerRow: 5] | 10
        [:]                         | 12
        """)
    func holdsTheCookiesOfItsRows(tray: Tray, capacity: Int) {
        #expect(tray.capacity == capacity)
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
