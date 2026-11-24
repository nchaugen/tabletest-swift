import Foundation

/// Makes the file name and URL segment of a suite or a table from its name, as the JVM reporter's
/// `Slugger` does, so that a Swift report and a JVM report have one URL form.
///
/// The words of the name are separated by how it is written: a name with spaces keeps its words,
/// a snake case name splits at the underscores, and any other name splits at its camel case. The
/// slug is then lowercase ASCII. A name with no letter left in ASCII keeps its own script, and a
/// name with no letter or digit at all takes a hash of itself.
enum Slug {
    static func of(_ name: String) -> String {
        guard !name.isEmpty else { return name }
        let words = separatedWords(of: name)
        let ascii = asciiSlug(of: words)
        if ascii.unicodeScalars.contains(where: \.properties.isAlphabetic) {
            return ascii
        }
        let ownScript = ownScriptSlug(of: words)
        return ownScript.isEmpty ? "unnamed-" + javaHash(of: name) : ownScript
    }

    /// Latin letters that have no decomposition to an ASCII letter, as the JVM reporter spells them.
    private static let lettersWithoutASCIIForm: [Unicode.Scalar: String] = [
        "ß": "ss", "æ": "ae", "œ": "oe", "ø": "o", "ł": "l", "đ": "d", "ð": "d", "þ": "th",
    ]

    private static func separatedWords(of name: String) -> String {
        if name.contains(" ") { return name.replacingOccurrences(of: "_", with: " ") }
        if name.contains("_") { return name.replacingOccurrences(of: "_", with: "-") }
        return camelCaseSplit(name).lowercased()
    }

    /// Puts a hyphen before a capital that follows a lowercase letter or a digit, and before the
    /// last capital of an acronym that a lowercase letter follows: `parsesXMLInput` gives
    /// `parses-XML-Input`.
    private static func camelCaseSplit(_ name: String) -> String {
        let scalars = Array(name.unicodeScalars)
        let split = scalars.indices.reduce(into: String.UnicodeScalarView()) { result, index in
            if startsAWord(at: index, in: scalars) { result.append("-") }
            result.append(scalars[index])
        }
        return String(split)
    }

    private static func startsAWord(at index: Int, in scalars: [Unicode.Scalar]) -> Bool {
        guard index > 0, scalars[index].properties.isUppercase else { return false }
        let previous = scalars[index - 1].properties
        if previous.isLowercase || previous.numericType == .decimal { return true }
        let nextIsLowercase = index + 1 < scalars.count && scalars[index + 1].properties.isLowercase
        return previous.isUppercase && nextIsLowercase
    }

    private static func asciiSlug(of words: String) -> String {
        let simplified = words.decomposedStringWithCompatibilityMapping.lowercased()
        let spelledOut = simplified.unicodeScalars.map { lettersWithoutASCIIForm[$0] ?? String($0) }.joined()
        return hyphenated(String(String.UnicodeScalarView(spelledOut.unicodeScalars.filter(\.isASCII)))) { scalar in
            ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "_"
        }
    }

    private static func ownScriptSlug(of words: String) -> String {
        hyphenated(words.lowercased().precomposedStringWithCompatibilityMapping) { scalar in
            let category = scalar.properties.generalCategory
            return scalar == "_" || isLetterMarkOrNumber(category)
        }
    }

    private static func isLetterMarkOrNumber(_ category: Unicode.GeneralCategory) -> Bool {
        switch category {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .nonspacingMark, .spacingMark, .enclosingMark,
             .decimalNumber, .letterNumber, .otherNumber:
            true
        default:
            false
        }
    }

    /// Replaces each run of scalars that the slug does not keep with one hyphen, and drops the
    /// hyphens at the ends.
    private static func hyphenated(_ text: String, keeping keeps: (Unicode.Scalar) -> Bool) -> String {
        let runs = text.unicodeScalars.split(omittingEmptySubsequences: true) { !keeps($0) }
        return runs.map { String(String.UnicodeScalarView($0)) }.joined(separator: "-")
    }

    /// Java's `String.hashCode` as eight hex digits, so a name without letters slugs as on the JVM.
    private static func javaHash(of name: String) -> String {
        let hash = name.utf16.reduce(Int32(0)) { hash, unit in hash &* 31 &+ Int32(unit) }
        return String(format: "%08x", UInt32(bitPattern: hash))
    }
}
