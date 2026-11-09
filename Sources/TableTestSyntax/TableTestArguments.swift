import SwiftSyntax

/// The arguments of one `@TableTest` attribute: an optional display name, the traits, and the
/// table literal.
package struct TableTestArguments {
    package let displayName: StringLiteralExprSyntax?
    package let traits: [ExprSyntax]
    package let table: StringLiteralExprSyntax

    package init(of attribute: AttributeSyntax) throws {
        let arguments = Array(attribute.arguments?.as(LabeledExprListSyntax.self) ?? [])
        let labelled = arguments.first { $0.label?.text == "table" }
        guard let tableArgument = labelled ?? arguments.last else {
            throw ArgumentError(node: Syntax(attribute), message: "@TableTest needs a table")
        }
        guard let table = tableArgument.expression.as(StringLiteralExprSyntax.self) else {
            throw ArgumentError(
                node: Syntax(tableArgument.expression),
                message: "@TableTest needs the table as a string literal, so that it can check the table at compile time"
            )
        }
        let leading = arguments.filter { $0.label == nil && $0.id != tableArgument.id }
        let displayName = leading.first?.expression.as(StringLiteralExprSyntax.self)
        self.table = table
        self.displayName = displayName
        self.traits = leading.dropFirst(displayName == nil ? 0 : 1).map(\.expression)
    }
}

/// An argument of `@TableTest` that the macro cannot use, and the syntax to point at.
package struct ArgumentError: Error {
    package let node: Syntax
    package let message: String
}

extension StringLiteralExprSyntax {
    /// The syntax node of a line of the literal's value, for a diagnostic: the string segment
    /// that starts the line in a multiline literal, or else the literal itself.
    ///
    /// A diagnostic cannot point at a column inside a node. The compiler places a macro
    /// diagnostic at the start of its node and ignores `Diagnostic.position`.
    package func node(atLine line: Int) -> Syntax {
        guard isMultiline else {
            return Syntax(self)
        }
        var linesBefore = 0
        for segment in segments {
            if linesBefore == line {
                return Syntax(segment)
            }
            linesBefore += segment.description.utf8.count { $0 == UInt8(ascii: "\n") }
        }
        return Syntax(self)
    }

    package var isMultiline: Bool {
        openingQuote.tokenKind == .multilineStringQuote
    }

    /// The number of columns that a multiline literal removes from each line: the indentation
    /// of its closing quote.
    package var indentation: Int {
        guard isMultiline else {
            return 0
        }
        let lastLine = closingQuote.leadingTrivia.description.split(separator: "\n", omittingEmptySubsequences: false).last
            ?? segments.last.map { Substring($0.description.split(separator: "\n", omittingEmptySubsequences: false).last ?? "") }
            ?? ""
        return lastLine.unicodeScalars.prefix { $0 == " " || $0 == "\t" }.count
    }
}
