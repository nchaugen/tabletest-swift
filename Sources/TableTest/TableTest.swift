import Testing

/// Runs the attached function once for each data row of the table.
///
/// The first row of the table names the columns. When the table has one more column than
/// the function has parameters, the first column names the scenario of each row. The other
/// columns map to the parameters in order. Each cell converts to the type of its parameter.
///
/// ```swift
/// @TableTest("""
///     Scenario         | Year | Leap?
///     Divisible by 4   | 2004 | true
///     Divisible by 100 | 1900 | false
///     """)
/// func knowsALeapYear(year: Int, leap: Bool) {
///     #expect(Year(year).isLeap == leap)
/// }
/// ```
@attached(peer, names: arbitrary)
public macro TableTest(_ table: String) = #externalMacro(module: "TableTestMacros", type: "TableTestMacro")

/// Runs the attached function once for each data row of the table, with a display name and
/// the traits of a Swift Testing test.
@attached(peer, names: arbitrary)
public macro TableTest(
    _ displayName: String,
    _ traits: any TestTrait...,
    table: String
) = #externalMacro(module: "TableTestMacros", type: "TableTestMacro")

/// Runs the attached function once for each data row of the table, with the traits of a
/// Swift Testing test.
@attached(peer, names: arbitrary)
public macro TableTest(
    _ traits: any TestTrait...,
    table: String
) = #externalMacro(module: "TableTestMacros", type: "TableTestMacro")
