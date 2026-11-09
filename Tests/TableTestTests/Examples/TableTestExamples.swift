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

struct ValueExamples {
    @TableTest("""
        Scenario       | Name | Nickname | Greeting?
        With nickname  | Ada  | Countess | Hello, Countess
        No nickname    | Ada  |          | Hello, Ada
        """)
    func greetsByNickname(name: String, nickname: String?, greeting: String) {
        #expect("Hello, \(nickname ?? name)" == greeting)
    }

    @TableTest("""
        Scenario    | Scores           | Bonus             | Total?
        No bonus    | [1, 2, 3]        | [:]               | 6
        With bonus  | [10]             | [early: 2, late: 1] | 13
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

extension Tag {
    @Tag static var calendar: Self
}
