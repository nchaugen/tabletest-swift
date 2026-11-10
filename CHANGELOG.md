# TableTest for Swift Changelog

## [Unreleased]

## [0.1.1] - 2026-11-10

### Added
- A map cell can leave out a list, set or map field of a `Decodable` struct, which is then empty: `[body: light]` for a struct with `var aromas: Set<Aroma> = []`

### Fixed
- A `@TableTest` in a type whose `init` throws or is `async` compiles; an `init` that throws fails the row, as it fails a Swift Testing test

## [0.1.0] - 2026-11-09

The first release: TableTest tables for Swift Testing. The table format is the one that
TableTest for the JVM uses, defined by `tabletest-spec`.

### Added
- `@TableTest`: runs a function once for each row of a table, as a Swift Testing test. Three forms: a table, a title and traits with a table, and traits with a table
- A scenario column names each row in the test results; value sets run a row once for each element, and a `Set` parameter takes the whole set
- A malformed table is a compile-time error at its row; a cell that does not convert fails only its own row, at its row's line
- Conversion of each cell to its parameter type: `Decodable` types, built-ins (`Decimal`, `URL`, `Date`, `ClosedRange`, `Range`, `Character`, `Duration`, `TimeZone`, `Locale`, `Locale.Currency`, `DateComponents`) and `LosslessStringConvertible` types
- Enums: a `String` raw value, else the case name; a `Codable` enum with associated values reads its Swift spelling, such as `month(year: 2025, month: 3)`
- `TableTextDecodable` and `TableValueDecodable` for a type's own conversion, and `TableValue.converted(to:)` to convert part of a cell
- `TableTestParser`, the parser, with no dependencies; it passes the parse and run fixtures of `tabletest-spec`
- `TableTestFormat` and the `tabletest-format` command line tool: align the tables in `.swift` and `.table` files, with indentation from `.editorconfig` or `.swift-format`; they pass the format fixtures of `tabletest-spec`
- The `tabletest-format` command plugin, for Swift packages and Xcode projects
