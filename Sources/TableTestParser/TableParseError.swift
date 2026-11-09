/// Why the parser refused an input, and where.
public struct TableParseError: Error, Sendable, Equatable {
    /// The error classes of the spec's parse fixtures.
    public enum Kind: Sendable, Equatable {
        /// The input is empty, or holds only blank lines and comment lines.
        case noRows
        /// A header cell is blank.
        case blankHeader
        /// A row does not parse.
        case malformed
        /// A map has the same key twice.
        case duplicateKey
    }

    public let kind: Kind
    /// The 0-based index of the line in the input.
    public let line: Int
    /// The 0-based Unicode scalar offset on the line.
    public let column: Int
    public let message: String
}
