/// One line of the input, as Unicode scalars, with its 0-based index in the input.
struct SourceLine {
    let index: Int
    let scalars: [Unicode.Scalar]

    /// The lines of a text, divided at each line feed (SPEC 1.1). A carriage return stays in its
    /// line, where it is whitespace.
    static func all(in text: String) -> [SourceLine] {
        text.unicodeScalars
            .split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated()
            .map { SourceLine(index: $0.offset, scalars: Array($0.element)) }
    }

    /// A row is a line that is neither blank nor a comment (SPEC 1.2).
    var isRow: Bool {
        let content = scalars.drop(while: \.isTableWhitespace)
        return !content.isEmpty && !content.starts(with: ["/", "/"])
    }

    /// The line as text, for an error message.
    var text: String {
        String(String.UnicodeScalarView(scalars))
    }
}

extension Unicode.Scalar {
    /// Whitespace is every scalar from U+0000 to U+0020 (SPEC "Terms").
    var isTableWhitespace: Bool {
        value <= 0x20
    }
}
