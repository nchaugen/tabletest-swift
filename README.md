# TableTest for Swift

TableTest for Swift adds tables of test data to Swift Testing. You write the examples of a
behaviour as rows of a plain-text table, and each row runs as one test case.

```swift
import TableTest
import Testing

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
}
```

- **Readable**: the inputs and the expected result of each example are on one line.
- **Easy to extend**: a new example is a new row.
- **Specified**: the table format has its own specification,
  [tabletest-spec](https://github.com/nchaugen/tabletest-spec), with conformance fixtures.

**Status:** unpublished, in development.

**Latest updates:** see the [changelog](CHANGELOG.md).

**Examples:** [tabletest-swift-examples](https://github.com/nchaugen/tabletest-swift-examples) is
an Xcode project that uses the package, with an app target and hosted tests.

**Requirements:** Swift 6.2 or later (Xcode 26 or later); macOS 13 or iOS 16 or later. The package depends on
swift-syntax `602.0.0..<604.0.0`.

## Contents

- [Installation](#installation)
- [Usage](#usage)
- [Value formats](#value-formats)
- [Type conversion](#type-conversion)
- [Value sets](#value-sets)
- [Comments and blank lines](#comments-and-blank-lines)
- [Errors](#errors)
- [Escape sequences](#escape-sequences)
- [Formatter](#formatter)
- [Differences from TableTest for the JVM](#differences-from-tabletest-for-the-jvm)
- [Contributing](#contributing)
- [License](#license)

## Installation

### Swift package

Add the package, and add the `TableTest` product to your test target:

```swift
dependencies: [
    .package(url: "https://github.com/nchaugen/tabletest-swift.git", from: "0.1.2"),
],
targets: [
    .testTarget(
        name: "MyAppTests",
        dependencies: [.product(name: "TableTest", package: "tabletest-swift")]
    ),
]
```

### Xcode project

1. Select **File > Add Package Dependencies…** and enter the package URL.
2. Add the `TableTest` library to your test target, not to your app target.
3. Build the tests. Xcode asks you to trust the `TableTestMacros` macro: select
   **Trust & Enable**.

### Trusting the macro

Xcode asks you to trust every macro that comes from a package. These facts help you decide and
plan for it:

- **What the macro does.** `TableTestMacros` checks the table, so that a malformed table is a
  compile-time error, and generates the Swift Testing `@Test` that calls your function. The
  table is parsed again when the tests run. Swift runs every macro in a sandbox, with no access
  to files or the network.
- **One trust for each version.** Xcode stores the trust for the package's commit, for every
  project on your machine. Each new version of TableTest asks again.
- **Only Xcode asks.** `swift build` and `swift test` on the command line do not ask.
- **On a CI machine,** pass `-skipMacroValidation` to `xcodebuild`, or trust the macro once on
  that machine.

## Usage

Put `@TableTest` on a function inside a type, such as a struct or a class. The macro generates a
Swift Testing `@Test` that runs the function once for each data row.

```swift
@TableTest("Leap years by rule", .tags(.calendar), table: """
    Year | Leap?
    2004 | true
    2001 | false
    """)
func leapYearsByRule(year: Int, leap: Bool) {
    #expect(Year(year).isLeap == leap)
}
```

`@TableTest` has three forms:

| Form | Use |
|---|---|
| `@TableTest("""…""")` | The test has the name of the function. |
| `@TableTest("Title", traits…, table: """…""")` | A display name and Swift Testing traits, as `@Test` takes them. |
| `@TableTest(traits…, table: """…""")` | Traits and no display name. |

The table follows these rules:

- `|` separates the columns, and a new line separates the rows.
- The first row is the header. It names the columns, and a header cell cannot be blank.
- The columns map to the function's parameters by order, not by name. Keep the header and the
  parameter names close, so that a reader can match them.
- When the table has one more column than the function has parameters, the first column is the
  **scenario**. It names each row in the test results and maps to no parameter.
- Every row has as many cells as the header.

The function can be `static`, `async` and `throws`, and the type's `init` can be `async` and
`throws`. To call main-actor code, put `@MainActor` on the type. A function name can be a raw
identifier, for example ``func `knows a leap year`(year: Int, leap: Bool)``.

In Xcode the test navigator shows each row as its own result, under the title of the test, or
else the name of the function: `LeapYearTests > knowsALeapYear > scenarios(_:) > Divisible by 4`.
A row with no scenario shows its cells, `2004 | true`.

## Value formats

A cell holds a single value, a list, a set or a map. A cell that converts to a type converts by
the rules in [Type conversion](#type-conversion).

### Single values

Text needs no quotes. The whitespace around a value is removed. Use quotes, `'…'` or `"…"`,
when the text has a `|`, has whitespace at its ends, or is empty:

```swift
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
```

### Lists, sets and maps

- A list is `[1, 2, 3]`, and `[]` is an empty list. It converts to an `Array`.
- A set is `{a, b}`, and `{}` is an empty set. It converts to a `Set`. In the column of a
  parameter that is not a set, it is a [value set](#value-sets).
- A map is `[early: 2, late: 1]`, and `[:]` is an empty map. It converts to a `Dictionary`, or
  to a `Decodable` struct.
- Collections nest: `[[a, b], [c]]`.

```swift
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
```

Inside a list, a set or a map, an element ends at `,` and at `:`. Put quotes around an element
that has a comma or a colon: `['after(minutes: 12)', now]`,
`['2025-03-14T10:30:00Z']`, `['12:30']`.

### Blank cells

A blank cell is `nil`, so its parameter must be optional:

```swift
@TableTest("""
    Scenario      | Name | Nickname | Greeting?
    With nickname | Ada  | Countess | Hello, Countess
    No nickname   | Ada  |          | Hello, Ada
    """)
func greetsByTheNickname(name: String, nickname: String?, greeting: String) {
    #expect("Hello, \(nickname ?? name)" == greeting)
}
```

## Type conversion

Each cell converts to the type of its parameter. The same rules apply to the elements of a list
or a set, to the keys and values of a map, and to the fields of a `Decodable` struct. The first
rule that applies decides:

1. The type's own conversion: `TableTextDecodable` or `TableValueDecodable`.
2. A built-in conversion (the table below).
3. An enum with `String` raw values reads its raw value.
4. Another `CaseIterable` enum reads its case name.
5. `Decodable`. An enum with associated values also reads its Swift spelling.
6. `LosslessStringConvertible` reads the text of the cell.
7. Another enum with raw values reads its raw value.

A type that matches no rule gives the error "make it Decodable, or conform it to
TableTextDecodable".

### Built-in conversions

| Type | Cell |
|---|---|
| `String` | `Ada Lovelace` |
| `Int`, `Int8` … `UInt64` | `42`, `-12` |
| `Double`, `Float` | `3.25` |
| `Bool` | `true`, `FALSE` (any case) |
| `Decimal` | `12.50` |
| `URL` | `https://tabletest.org` |
| `Date` | `2025-03-14` (midnight UTC), `2025-03-14T10:30:00Z`, `2025-03-14T10:30:00+01:00` |
| `ClosedRange`, `Range` | `2028...2030`, `2028..<2031`; the list form `[2028, 2030]` also works |
| `Character` | `a` (one character) |
| `Duration` | `1.5 seconds`, `250 milliseconds`, `5 microseconds`, `7 nanoseconds` |
| `TimeZone` | `Europe/Oslo` |
| `Locale` | `nb_NO`, `fr` |
| `Locale.Currency` | `EUR` |
| `DateComponents` | `2025`, `2025-03`, `2025-03-14`, `12:30`, `12:30:15` |

A date and time must give its zone: `2025-03-14T10:30:00` is an error. The bounds of a range
convert by their own type's rules:

```swift
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
```

### Enums

An enum with `String` raw values reads its raw value. A raw value is often the word of the
domain, such as `gluten-free` or `extra hot`:

```swift
enum Diet: String, Codable {
    case vegetarian
    case glutenFree = "gluten-free"
}

enum Heat: String, Codable, CaseIterable {
    case mild
    case medium
    case hot
    case extraHot = "extra hot"

    var rank: Int {
        Heat.allCases.firstIndex(of: self)!
    }
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
```

A case name in such a cell is an error that gives the raw value: "Heat has no case with the raw
value `extraHot`; the raw value of `extraHot` is `extra hot`".

A `CaseIterable` enum with no raw values, or with number raw values, reads its case name. When
the raw values are storage keys, such as `SIRLOIN_STEAK`, the test target can choose the case names
with one line:

```swift
enum Cut: String, CaseIterable {
    case sirloin = "SIRLOIN_STEAK"
    case brisket = "BRISKET"
}

extension Cut: TableValueDecodable {}

@TableTest("""
    Cut     | For the grill?
    sirloin | true
    brisket | false
    """)
func knowsACutForTheGrill(cut: Cut, forTheGrill: Bool) {
    #expect((cut == .sirloin) == forTheGrill)
}
```

When the enum belongs to the app, write `extension Cut: @retroactive TableValueDecodable {}`
in the test target.

### Enums with associated values

A `Codable` enum with associated values reads a case as Swift code spells it. A value with no
label is given by its position:

```swift
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

@TableTest("""
    Scenario        | Alarm              | Minute | Rings?
    Rings now       | now                | 10     | true
    Before its time | after(minutes: 12) | 10     | false
    Inside the span | between(8, 12)     | 10     | true
    """)
func ringsAtItsMinute(alarm: Alarm, minute: Int, rings: Bool) {
    #expect(alarm.rings(atMinute: minute) == rings)
}
```

In a list or a set, put quotes around a spelling that has a label or two values:

```swift
@TableTest("""
    Alarms                                  | Any now?
    ['after(minutes: 12)', now]             | true
    ['between(8, 12)', 'after(minutes: 5)'] | false
    """)
func findsAnAlarmRingingNow(alarms: [Alarm], anyNow: Bool) {
    #expect(alarms.contains(.now) == anyNow)
}
```

### Structs

A map converts to a `Decodable` struct. An optional field can be left out:

```swift
struct Recipe: Decodable {
    let dish: String
    let minutes: Int?
}

@TableTest("""
    Recipes                                                       | Longest?
    [[dish: Pancakes, minutes: 20], [dish: Risotto, minutes: 35]] | 35
    [[dish: Salad]]                                               |
    """)
func findsTheLongestRecipe(recipes: [Recipe], longest: Int?) {
    #expect(recipes.compactMap(\.minutes).max() == longest)
}
```

A list, set or map field that the map leaves out is empty. A synthesised `Decodable` needs a key
for every other field that is not optional, also for a field with a default value. When a struct only collects the inputs of one example, give each field its
own column, and build the struct in the test body. When a cell must name only the fields it
sets, read the map with `readingFields` ([Your own conversion](#your-own-conversion)).

### Types from the app

A type that converts with no test code is the aim. For an app type that is neither `Codable` nor
`CaseIterable`, add `Codable`, or `CaseIterable` for a plain enum, to the type in the app. A cell
then reads the value as Swift spells it.

### Your own conversion

A type converts itself. For a text form that you invent, such as `250 g`, conform the type
to `TableTextDecodable`. Return `nil` when the text does not convert, and TableTest reports the cell:

```swift
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

@TableTest("""
    Per serving | Servings | Total?
    250 g       | 2        | 500 g
    0.4 kg      | 3        | 1.2 kg
    """)
func scalesTheQuantity(perServing: Quantity, servings: Int, total: Quantity) {
    #expect(Quantity(grams: perServing.grams * servings) == total)
}
```

To read a list, a set or a map in your own way, conform to `TableValueDecodable`.
`converted(to:)` converts each part by the rules above:

```swift
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

@TableTest("""
    Pantry         | Items?
    [flour, sugar] | 2
    []             | 0
    """)
func countsTheItemsInThePantry(pantry: Pantry, items: Int) {
    #expect(pantry.items.count == items)
}
```

To read a map that names only the fields it sets, use `readingFields`. Each field converts by the
rules above. A key that the conversion does not read fails the cell, so a misspelt key is not left
out silently:

```swift
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

@TableTest("""
    Tray                        | Capacity?
    [rows: 4]                   | 16
    [rows: 2, cookiesPerRow: 5] | 10
    [:]                         | 12
    """)
func holdsTheCookiesOfItsRows(tray: Tray, capacity: Int) {
    #expect(tray.capacity == capacity)
}
```

`fields.required("rows")` fails the cell when the map leaves the key out.

When the type belongs to the app, write the conformance with `@retroactive` in the test target,
and make its initialiser `public`: `public init(tableValue:)` or `public init?(tableText:)`. Under
`@testable import`, an app type has the access of a public type, so the build fails without it.
Swift does not synthesise `Codable` or `CaseIterable` in the test target, so that one word belongs
on the app type ([Types from the app](#types-from-the-app)). A type that conforms to `TableTextDecodable` cannot be a field of a synthesised `Decodable`
struct, because Swift needs every field to be `Decodable`.

## Value sets

A set in the column of a parameter that does not take a set is a **value set**. The row then
runs once for each element:

```swift
@TableTest("""
    Scenario           | Year               | Leap?
    Not divisible by 4 | {2001, 2002, 2003} | false
    Divisible by 4     | {2004, 2008, 2012} | true
    """)
func knowsALeapYearForEachExample(year: Int, leap: Bool) {
    #expect(Year(year).isLeap == leap)
}
```

Each case shows its element: `Divisible by 4 (Year = 2004)`. With value sets in two columns, a
row runs once for each combination, and the first column changes slowest. An empty value set is
an error.

A parameter of type `Set`, an `OptionSet`, `TableValue`, or an optional of one takes the whole
set, also through a `typealias`.

## Comments and blank lines

A line that starts with `//` is a comment, and a blank line is skipped:

```swift
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
```

## Errors

The macro checks the table when the tests compile, and reports an error at the line of the row:

- `Row 2 has 1 cell, but the header has 2`
- `The table has 3 columns, but the function has 1 parameter: give it one parameter for each
  column, or for each column after a scenario column`
- `Failed to parse ... in row ...` for a cell that is not a valid value, such as `[true`
- `@TableTest applies only to a function inside a type`
- `@TableTest needs a table without string interpolation`

A cell that does not convert fails only its own row, and the result points at the row:
``Row 2, column 'Year': Cannot convert `200x` to Int``.

## Escape sequences

The table is a Swift string literal, so Swift processes the escape sequences before TableTest
reads the table. In a multiline literal `"""…"""`, `\t` is a tab, `\\` is one backslash, and
`\u{41}` is `A`:

```swift
@TableTest("""
    Scenario  | Text       | Length?
    Tab       | a\tb       | 3
    Backslash | path\\file | 9
    Unicode   | \u{41}B    | 2
    """)
func countsTheProcessedEscapes(text: String, length: Int) {
    #expect(text.count == length)
}
```

In a raw literal `#"""…"""#`, Swift keeps the backslashes:

```swift
@TableTest(#"""
    Scenario  | Text       | Length?
    Tab       | a\tb       | 4
    Backslash | path\\file | 10
    """#)
func countsTheRawEscapes(text: String, length: Int) {
    #expect(text.count == length)
}
```

The formatter does not change a literal that has an escape sequence, because its source text is
not its value. Align that table by hand, or write the character itself. A table cannot have
string interpolation.

## Formatter

`tabletest-format` aligns the columns of the tables in `.swift` and `.table` files. A `.table`
file holds one table and nothing else. `@TableTest` cannot read one: it takes its table only as
a string literal.

### Command plugin

In a Swift package:

```sh
swift package --allow-writing-to-package-directory tabletest-format
swift package --allow-writing-to-package-directory tabletest-format --check
swift package --allow-writing-to-package-directory tabletest-format --target MyAppTests
```

`--check` changes no file. It lists the files that need formatting and exits with status 1, so
it can run in CI. SwiftPM asks for the write permission also for `--check`, because a plugin
states its permissions before it runs.

In an Xcode project that has the package, right-click the project in the project navigator, and
run the TableTest format command from the plugin menu. Xcode asks which targets to format.

### Command line

```sh
swift run tabletest-format [--check] [--verbose] PATH...
```

A directory is searched recursively, and hidden directories such as `.build` are skipped. The
exit status is 0 on success, 1 when `--check` finds a file to format or a file cannot be
formatted, and 2 on wrong use.

### Indentation

The formatter indents each table one level more than its `@TableTest` line. It takes the level
from `.editorconfig` (`indent_style`, `indent_size`), else from `.swift-format`
(`indentation`, 2 spaces by default), else 4 spaces. It does not change a table that does not
parse.

## Differences from TableTest for the JVM

TableTest started on the JVM: [TableTest for Java and Kotlin](https://github.com/nchaugen/tabletest)
extends JUnit, and [tabletest.org](https://tabletest.org) documents it. Both implementations read
the same table format, and the conformance fixtures of
[tabletest-spec](https://github.com/nchaugen/tabletest-spec) check both, so a table parses and
formats the same way in both. If you know the JVM version, these parts differ:

| Topic | JVM | Swift |
|---|---|---|
| Your own conversion | a `@TypeConverter` method converts a value | the type converts itself: a `TableTextDecodable` or `TableValueDecodable` conformance |
| Enums | the constant name, `MEDIUM_MINUS` | the `String` raw value, else the case name |
| A table in an external `.table` file | `@TableTest(resource = …)` | not supported; a macro cannot read files |
| The scenario as a parameter | `@Scenario` | not supported; the scenario only names the row |
| Escape sequences | processed in Java, not in Kotlin raw strings | processed, except in a raw literal `#"""…"""#` |

## Contributing

`Tests/TableTestParserTests/Fixtures/parse/` holds a copy of the parse fixtures of
`tabletest-spec`, and `Tests/TableTestTests/Fixtures/run/` a copy of its run fixtures.
`Fixtures/SPEC_COMMIT` in each names the spec commit of the copy. To update both copies
from a `tabletest-spec` checkout beside this repo:

```sh
scripts/sync-fixtures.sh
```

`scripts/check-plugin.sh` checks the command plugin in a package that depends on this repo.

The tables in this README are copies of `Tests/ReadmeExamples/ReadmeExamples.swift`, and
`ReadmeSyncTests` fails when a README table is not in that file.

## License

TableTest for Swift is licensed under the [Apache License, Version 2.0](LICENSE), as the other
TableTest products are.
