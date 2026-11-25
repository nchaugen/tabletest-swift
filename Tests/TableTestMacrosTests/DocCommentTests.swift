import SwiftParser
import SwiftSyntax
import Testing
import TableTestSyntax

/// The text of the doc comment above a declaration, as the manifest's description takes it.
@Suite("Doc comment")
struct DocCommentTests {
    @Test("Reads the text of the doc comment above a declaration", arguments: [
        ("/// One line.", "One line."),
        ("///One line.", "One line."),
        ("/// First line.\n/// Second line.", "First line.\nSecond line."),
        ("/// A paragraph.\n///\n/// - A list item,\n///   continued.", "A paragraph.\n\n- A list item,\n  continued."),
        ("/** A block. */", "A block."),
        ("/**\n A block\n over two lines.\n */", "A block\nover two lines."),
        ("/**\n * A block\n * with stars.\n */", "A block\nwith stars."),
        ("// MARK: - Plain\n\n/// The doc comment.", "The doc comment."),
        ("/// An older doc comment.\n\n/// The doc comment.", "The doc comment."),
        ("/// Above a plain comment.\n// A plain comment.", nil),
        ("// Only a plain comment.", nil),
        ("", nil),
        ("///", nil),
    ] as [(String, String?)])
    func readsTheDocComment(comment: String, text: String?) throws {
        let source = Parser.parse(source: "\(comment)\n@available(*, deprecated)\nfunc f() {}")
        let declaration = try #require(source.statements.first?.item.as(FunctionDeclSyntax.self))

        #expect(declaration.leadingTrivia.docCommentText == text)
    }
}
