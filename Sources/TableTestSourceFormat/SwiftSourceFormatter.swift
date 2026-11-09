import SwiftParser
import SwiftSyntax
import TableTestFormat
import TableTestSyntax

/// Formats the `@TableTest` tables in Swift source, as the JVM formatter does in Java.
///
/// Each line of a table is trimmed and the table is formatted (SPEC chapter 4). The rows, the
/// comment lines and the closing `"""` then start one indent level past the line where
/// `@TableTest` starts; blank lines stay empty. A table that does not parse stays as written,
/// and so does a literal whose source text is not its value: one with an escape or an
/// interpolation. Only multiline literals, plain or raw, hold tables that the formatter changes.
public enum SwiftSourceFormatter {
    public static func format(_ source: String, indentation: Indentation) -> String {
        let tree = Parser.parse(source: source)
        let finder = TableLiteralFinder(viewMode: .sourceAccurate)
        finder.walk(tree)
        var bytes = Array(source.utf8)
        let lineEnding = source.utf8.firstIndex(of: UInt8(ascii: "\n")).map { index in
            index > source.utf8.startIndex && source.utf8[source.utf8.index(before: index)] == UInt8(ascii: "\r")
        } == true ? "\r\n" : "\n"
        for table in finder.tables.sorted(by: { $0.contentStart > $1.contentStart }) {
            guard let edit = table.edit(in: bytes, indentation: indentation, lineEnding: lineEnding) else {
                continue
            }
            bytes.replaceSubrange(edit.range, with: Array(edit.text.utf8))
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}

/// The table literal of one `@TableTest` attribute, by its offsets in the source.
private struct TableLiteral {
    /// The offset of the `@` that starts the attribute.
    let attributeStart: Int
    /// The offset after the opening `"""`.
    let contentStart: Int
    /// The offset of the closing `"""`.
    let closingQuote: Int

    /// The replacement of the content and the closing line's indentation, or `nil` when the
    /// content is not a table or is already formatted.
    func edit(in bytes: [UInt8], indentation: Indentation, lineEnding: String) -> (range: Range<Int>, text: String)? {
        guard let firstNewline = bytes[contentStart..<closingQuote].firstIndex(of: UInt8(ascii: "\n")) else {
            return nil
        }
        let start = firstNewline + 1
        let closingLineStart = (bytes[start..<closingQuote].lastIndex(of: UInt8(ascii: "\n")) ?? (start - 1)) + 1
        guard closingLineStart > start else {
            return nil
        }
        let content = String(decoding: bytes[start..<closingLineStart], as: UTF8.self)
        let trimmedLines = content.unicodeScalars
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String(String.UnicodeScalarView($0)).trimmingTableWhitespace() }
        let table = trimmedLines.joined(separator: "\n").trimmingTableWhitespace()
        guard let formatted = TableFormatter.formattedTable(table) else {
            return nil
        }
        let indent = baseIndentation(in: bytes) + indentation.unit
        let lines = formatted.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : indent + $0 }
        let text = lines.map { $0 + lineEnding }.joined() + indent
        let range = start..<closingQuote
        guard Array(text.utf8) != Array(bytes[range]) else {
            return nil
        }
        return (range, text)
    }

    /// The spaces and tabs that start the line where the attribute starts.
    private func baseIndentation(in bytes: [UInt8]) -> String {
        let lineStart = (bytes[..<attributeStart].lastIndex(of: UInt8(ascii: "\n")) ?? -1) + 1
        let indentation = bytes[lineStart..<attributeStart].prefix { $0 == UInt8(ascii: " ") || $0 == UInt8(ascii: "\t") }
        return String(decoding: indentation, as: UTF8.self)
    }
}

/// Finds the multiline table literal of each `@TableTest` attribute whose source text is its
/// value: no escape, no interpolation.
private final class TableLiteralFinder: SyntaxVisitor {
    var tables: [TableLiteral] = []

    override func visit(_ node: AttributeSyntax) -> SyntaxVisitorContinueKind {
        guard node.attributeName.trimmedDescription.split(separator: ".").last == "TableTest",
              let arguments = try? TableTestArguments(of: node)
        else {
            return .visitChildren
        }
        let literal = arguments.table
        let segments = literal.segments
        let isRaw = literal.openingPounds != nil
        let isPlainText = segments.allSatisfy { segment in
            guard let text = segment.as(StringSegmentSyntax.self) else {
                return false
            }
            return isRaw || !text.content.text.contains("\\")
        }
        if literal.isMultiline, isPlainText {
            tables.append(TableLiteral(
                attributeStart: node.positionAfterSkippingLeadingTrivia.utf8Offset,
                contentStart: literal.openingQuote.endPositionBeforeTrailingTrivia.utf8Offset,
                closingQuote: literal.closingQuote.positionAfterSkippingLeadingTrivia.utf8Offset
            ))
        }
        return .visitChildren
    }
}

extension Indentation {
    /// One indent level as text.
    var unit: String {
        String(repeating: style == .spaces ? " " : "\t", count: size)
    }
}

extension String {
    /// The text without whitespace (U+0000–U+0020, SPEC "Terms") at its start and its end.
    func trimmingTableWhitespace() -> String {
        let scalars = unicodeScalars.drop { $0.value <= 0x20 }
        let end = scalars.lastIndex { $0.value > 0x20 }.map { scalars.index(after: $0) } ?? scalars.startIndex
        return String(String.UnicodeScalarView(scalars[scalars.startIndex..<end]))
    }
}
