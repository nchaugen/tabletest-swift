import Testing
@testable import TableTestReport

// The texts are line breaks and other control characters that a table cell cannot hold, so these
// tests take Swift literals.
struct YAMLValueTests {
    @Test("Writes text as a double-quoted scalar", arguments: [
        (text: "Leap years", scalar: #""Leap years""#),
        (text: #"say "hi" \ bye"#, scalar: #""say \"hi\" \\ bye""#),
        (text: "a/b", scalar: #""a/b""#),
        (text: "Årstider", scalar: #""Årstider""#),
        (text: "a\tb", scalar: #""a\tb""#),
        (text: "a\nb", scalar: #""a\nb""#),
        (text: "a\u{85}b", scalar: #""a\u0085b""#),
        (text: "a\u{2028}b", scalar: #""a\u2028b""#),
        (text: "a\u{2029}b", scalar: #""a\u2029b""#),
    ])
    func writesTextAsADoubleQuotedScalar(text: String, scalar: String) throws {
        #expect(try YAMLValue.text(text).rendered() == scalar)
    }

    @Test("Writes a collection in flow style", arguments: [
        (value: YAMLValue.sequence([.text("a"), .number(2)]), flow: #"["a", 2]"#),
        (value: YAMLValue.set([.text("a"), .sequence([.text("b")])]), flow: #"!!set {? "a" : null, ? ["b"] : null}"#),
        (value: YAMLValue.mapping([("key: 1", .boolean(true)), ("none", .null)]), flow: #"{"key: 1": true, "none": null}"#),
    ])
    func writesACollectionInFlowStyle(value: YAMLValue, flow: String) throws {
        #expect(try value.rendered() == flow)
    }
}
