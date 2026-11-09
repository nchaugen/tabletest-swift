/// Measures how many terminal columns a text takes, by Unicode data, one character at a time
/// (SPEC 4.8). A Swift `Character` is an extended grapheme cluster: a letter and its accent, a
/// flag, or emoji joined into one picture.
enum DisplayWidth {
    /// The sum of the widths of the text's characters.
    static func of(_ text: String) -> Int {
        text.reduce(0) { $0 + of($1) }
    }

    /// 2 when a scalar in the character draws two columns on its own, or when U+FE0F (the emoji
    /// presentation selector) follows a scalar; 0 when no scalar draws a glyph of its own; else 1.
    static func of(_ character: Character) -> Int {
        let scalars = character.unicodeScalars
        if scalars.contains(where: WideScalars.contains) || scalars.dropFirst().contains("\u{FE0F}") {
            return 2
        }
        return scalars.allSatisfy(drawsNoGlyph) ? 0 : 1
    }

    /// A control character, a format character, a combining mark, or a Hangul vowel or final
    /// consonant that joins a syllable (Hangul_Syllable_Type V or T).
    private static func drawsNoGlyph(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .control, .format, .nonspacingMark, .enclosingMark:
            true
        default:
            (0x1160...0x11FF).contains(scalar.value) || (0xD7B0...0xD7FF).contains(scalar.value)
        }
    }
}
