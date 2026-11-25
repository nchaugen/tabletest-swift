import SwiftSyntax

extension Trivia {
    /// The text of the doc comment that ends this trivia: the `///` lines or the `/** */` block
    /// above a declaration, without their markers and the indentation the lines share. A plain
    /// comment ends the doc comment, and so does a blank line above it. It is `nil` when there is
    /// no doc comment or it holds no text.
    package var docCommentText: String? {
        let lines = Self.lines(ofLastDocCommentIn: pieces)
        let text = Self.withoutSharedIndentation(lines)
            .map { $0.trimmingTrailingWhitespace }
            .drop { $0.isEmpty }
            .reversed().drop { $0.isEmpty }.reversed()
            .joined(separator: "\n")
        return text.isEmpty ? nil : text
    }

    private static func lines(ofLastDocCommentIn pieces: [TriviaPiece]) -> [Substring] {
        var lines: [Substring] = []
        for piece in pieces.reversed() {
            switch piece {
            case .docLineComment(let text):
                lines.insert(text.dropFirst(3), at: 0)
            case .docBlockComment(let text) where lines.isEmpty:
                return blockLines(of: text)
            case .newlines(let count), .carriageReturns(let count), .carriageReturnLineFeeds(let count):
                if count > 1 && !lines.isEmpty { return lines }
            case .spaces, .tabs:
                continue
            default:
                return lines
            }
        }
        return lines
    }

    /// The lines of a `/** */` comment without its markers, and without the `*` that starts each
    /// line when every line has one.
    private static func blockLines(of text: String) -> [Substring] {
        let lines = text.dropFirst(3).dropLast(2).split(separator: "\n", omittingEmptySubsequences: false)
        let written = lines.map { $0.drop { $0 == " " || $0 == "\t" } }.filter { !$0.isEmpty }
        guard !written.isEmpty, written.allSatisfy({ $0.hasPrefix("*") }) else { return lines }
        return lines.map { line in
            let start = line.drop { $0 == " " || $0 == "\t" }
            return start.hasPrefix("*") ? start.dropFirst() : start
        }
    }

    private static func withoutSharedIndentation(_ lines: [Substring]) -> [Substring] {
        let shared = lines.filter { !$0.allSatisfy(\.isWhitespace) }.map(\.indentation).min() ?? 0
        return lines.map { $0.dropFirst(Swift.min(shared, $0.indentation)) }
    }
}

extension Substring {
    fileprivate var indentation: Int { prefix { $0 == " " || $0 == "\t" }.count }

    fileprivate var trimmingTrailingWhitespace: Substring {
        self[..<(lastIndex { !$0.isWhitespace }.map(index(after:)) ?? startIndex)]
    }
}
