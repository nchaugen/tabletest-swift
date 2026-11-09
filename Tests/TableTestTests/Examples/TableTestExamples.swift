import Testing
import TableTest

/// Tables as a test author writes them. Each one exercises a shape of the expansion: a
/// scenario column, optionals, collections, an enum, a title and traits, a raw identifier,
/// a static function, effects, and a global actor.
struct LeapYearExamples {
    @TableTest("""
        Scenario                     | Year | Leap?
        Divisible by 4               | 2004 | true
        Not divisible by 4           | 2001 | false
        Divisible by 100, not by 400 | 1900 | false
        Divisible by 400             | 2000 | true
        """)
    func knowsALeapYear(year: Int, leap: Bool) {
        #expect(isLeap(year) == leap)
    }

    @TableTest("Leap years by rule", .tags(.calendar), table: """
        Year | Leap?
        2004 | true
        2001 | false
        """)
    func leapYearsWithATitle(year: Int, leap: Bool) {
        #expect(isLeap(year) == leap)
    }

    @TableTest(.tags(.calendar), table: """
        Year | Leap?
        2000 | true
        """)
    func leapYearsWithTraitsOnly(_ year: Int, _ leap: Bool) {
        #expect(isLeap(year) == leap)
    }

    @TableTest("""
        Year | Leap?
        2400 | true
        """)
    func `knows a leap year from a sentence`(year: Int, leap: Bool) {
        #expect(isLeap(year) == leap)
    }

    @TableTest("""
        Year | Leap?
        1600 | true
        """)
    static func knowsALeapYearStatically(year: Int, leap: Bool) {
        #expect(isLeap(year) == leap)
    }

    @TableTest("""
        Year | Leap?
        1700 | false
        """)
    func knowsALeapYearAsynchronously(year: Int, leap: Bool) async throws {
        await Task.yield()
        #expect(isLeap(year) == leap)
    }

    private static func isLeap(_ year: Int) -> Bool {
        year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
    }

    private func isLeap(_ year: Int) -> Bool {
        Self.isLeap(year)
    }
}

struct ValueSetExamples {
    @TableTest("""
        Scenario       | x         | y       | Even sum?
        Even plus even | {2, 4, 6} | {8, 10} | true
        Odd plus even  | {1, 3, 5} | {6, 8}  | false
        """)
    func knowsAnEvenSum(x: Int, y: Int, evenSum: Bool) {
        #expect(((x + y) % 2 == 0) == evenSum)
    }

    @TableTest("""
        Values    | Size?
        {1, 2, 3} | 3
        {}        | 0
        """)
    func countsTheWholeSet(values: Set<Int>, size: Int) {
        #expect(values.count == size)
    }
}

struct ValueExamples {
    @TableTest("""
        Scenario      | Name | Nickname | Greeting?
        With nickname | Ada  | Countess | Hello, Countess
        No nickname   | Ada  |          | Hello, Ada
        """)
    func greetsByNickname(name: String, nickname: String?, greeting: String) {
        #expect("Hello, \(nickname ?? name)" == greeting)
    }

    @TableTest("""
        Scenario   | Scores    | Bonus               | Total?
        No bonus   | [1, 2, 3] | [:]                 | 6
        With bonus | [10]      | [early: 2, late: 1] | 13
        """)
    func addsScoresAndBonus(scores: [Int], bonus: [String: Int], total: Int) {
        #expect(scores.reduce(0, +) + bonus.values.reduce(0, +) == total)
    }

    @TableTest("""
        Colour | Warm?
        red    | true
        blue   | false
        """)
    func knowsAWarmColour(colour: Hue, warm: Bool) {
        #expect((colour == .red) == warm)
    }

    @TableTest("""
        Scenario       | Band      | Notes        | Shades             | Best?
        Raw value      | grand_cru | [fruit, oak] | [fruit: grand_cru] | true
        Blank optional |           | []           | [:]                | false
        """)
    func readsAnEnumThatIsNotDecodable(band: Band?, notes: Set<Note>, shades: [Note: Band], best: Bool) {
        #expect((band == .grandCru) == best)
    }

    @TableTest("""
        Scenario       | Vintage                     | Others                           | Years?
        Year           | year(2025)                  | [year(2024), nonVintage]         | [2025, 2024]
        Year and month | month(year: 2025, month: 3) | ['month(year: 2024, month: 12)'] | [2025, 2024]
        """)
    func readsTheSwiftSpellingOfACase(vintage: Vintage, others: [Vintage], years: [Int]) {
        #expect(([vintage] + others).compactMap(\.year) == years)
    }
}

@MainActor
struct MainActorExamples {
    @TableTest("""
        Count | Doubled?
        2     | 4
        """)
    func doublesOnTheMainActor(count: Int, doubled: Int) {
        #expect(MainActorCounter.double(count) == doubled)
    }
}

@MainActor
enum MainActorCounter {
    static func double(_ count: Int) -> Int { count * 2 }
}

enum Hue: String, Decodable {
    case red, blue
}

/// A raw-value enum that is not `Decodable`, which a cell names by its raw value.
enum Band: String, CaseIterable, Sendable {
    case grandCru = "grand_cru"
    case premierCru = "premier_cru"
}

extension Vintage {
    var year: Int? {
        switch self {
        case let .year(year), let .month(year, _), let .span(year, _): year
        case .nonVintage: nil
        }
    }
}

/// An enum with no raw value, which is not `Decodable` and not `TableValueDecodable`.
enum Note: Hashable, CaseIterable, Sendable {
    case fruit, oak
}

extension Tag {
    @Tag static var calendar: Self
}
