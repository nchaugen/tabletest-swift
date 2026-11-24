import TableTest
import Testing
@testable import TableTestReport

/// A slug names the YAML file and the report page of a suite or a table. It is the slug that the
/// JVM reporter makes from the same name, so a Swift report and a JVM report have one URL form.
struct SlugTests {
    @TableTest("""
        Scenario                 | Name                | Slug?
        Words with spaces        | Leap years, by rule | leap-years-by-rule
        Spaces and underscores   | Leap_years by rule  | leap-years-by-rule
        Snake case               | knows_a_leap_year   | knows-a-leap-year
        Camel case               | knowsALeapYear      | knows-a-leap-year
        An acronym before a word | parsesXMLInput      | parses-xml-input
        A digit before a capital | year2004Rule        | year2004-rule
        """)
    func separatesTheWordsByHowTheNameIsWritten(name: String, slug: String) {
        #expect(Slug.of(name) == slug)
    }

    @TableTest("""
        Scenario             | Name     | Slug?
        An accented letter   | Årstider | arstider
        A stroked letter     | Smørbrød | smorbrod
        A joined letter      | Ærø      | aero
        A sharp s            | Straße   | strasse
        A thorn              | Þing     | thing
        A compatibility form | ﬁle      | file
        """)
    func foldsALatinLetterToItsASCIIForm(name: String, slug: String) {
        #expect(Slug.of(name) == slug)
    }

    /// A name with no letter or digit takes a hash of itself, so two such names get two slugs.
    @TableTest("""
        Scenario           | Name            | Slug?
        A Cyrillic name    | Високосные годы | високосные-годы
        Digits only        | 2024            | 2024
        No letter or digit | !!!             | unnamed-00008001
        """)
    func fallsBackToTheOwnScriptThenAHash(name: String, slug: String) {
        #expect(Slug.of(name) == slug)
    }
}
