import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros
import TableTestParser

/// Expands `@TableTest` on a function to a Swift Testing test that calls the function once
/// for each row of the table.
///
/// The expansion is a nested type `__tabletest_<name>` that holds the `@Test` function. A
/// `@Test` written directly beside the function does not compile, because a nested macro
/// expansion does not see the enclosing type. The table text goes to the runtime, which parses
/// it and converts the cells: the macro only reads the syntax around it.
public struct TableTestMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let function = declaration.as(FunctionDeclSyntax.self) else {
            throw MacroError("@TableTest applies only to a function")
        }
        guard context.lexicalContext.contains(where: { $0.typeName != nil }) else {
            throw MacroError(
                "@TableTest applies only to a function inside a type: the generated test calls it through the type"
            )
        }
        let arguments: TableTestArguments
        do {
            arguments = try TableTestArguments(of: node)
        } catch let error as ArgumentError {
            context.diagnose(Diagnostic(node: error.node, message: TableTestDiagnostic(error.message)))
            return []
        }
        if let interpolation = arguments.table.segments.first(where: { $0.is(ExpressionSegmentSyntax.self) }) {
            context.diagnose(Diagnostic(
                node: interpolation,
                message: TableTestDiagnostic("@TableTest needs a table without string interpolation")
            ))
            return []
        }
        guard let table = arguments.table.representedLiteralValue else {
            throw MacroError("@TableTest cannot read the table literal")
        }
        if let problem = problem(in: table, parameterCount: function.parameters.count) {
            context.diagnose(Diagnostic(
                node: arguments.table.node(atLine: problem.line),
                message: TableTestDiagnostic(problem.message)
            ))
            return []
        }
        guard let fileID = context.location(of: arguments.table, at: .afterLeadingTrivia, filePathMode: .fileID),
              let filePath = context.location(of: arguments.table, at: .afterLeadingTrivia, filePathMode: .filePath)
        else {
            throw MacroError("@TableTest cannot find the location of the table")
        }

        let name = function.name.text
        let title = arguments.displayName?.trimmedDescription ?? "\"\(name.withoutBackticks)\""
        let testAttributeArguments = ([title] + arguments.traits.map(\.trimmedDescription) + [
            """
            arguments: try TableTestRows.make(
                table: \(StringLiteralExprSyntax(content: table)),
                parameterCount: \(function.parameters.count),
                source: TableSource(fileID: \(fileID.file), filePath: \(filePath.file), line: \(fileID.line), \
            column: \(fileID.column), indentation: \(arguments.table.indentation), \
            isMultiline: \(arguments.table.isMultiline))
            )
            """,
        ]).joined(separator: ", ")

        let effects = function.signature.effectSpecifiers
        let isAsync = effects?.asyncSpecifier != nil
        let isThrowing = effects?.throwsClause != nil
        let callArguments = function.parameters.enumerated().map { column, parameter in
            let label = parameter.firstName.tokenKind == .wildcard ? "" : "\(parameter.firstName.text): "
            return "\(label)row.decode(\(column), as: (\(parameter.type.trimmedDescription)).self)"
        }.joined(separator: ", ")
        let call = "try \(isAsync ? "await " : "")\(receiver(of: function, in: context))\(name)(\(callArguments))"

        return [
            """
            \(raw: isolation(of: function, in: context))struct \(raw: generatedName(for: name)) {
                @Test(\(raw: testAttributeArguments))
                func rows(_ row: TableTestRow) \(raw: isAsync ? "async " : "")throws {
                    \(raw: isThrowing ? "do" : "do throws(TableCellError)") {
                        \(raw: call)
                    } \(raw: isThrowing ? "catch let error as TableCellError" : "catch") {
                        Issue.record(error, sourceLocation: error.sourceLocation)
                    }
                }
            }
            """,
        ]
    }

    /// The first reason the table does not parse or does not fit the function, with its position
    /// in the table text.
    private static func problem(in table: String, parameterCount: Int) -> (line: Int, column: Int, message: String)? {
        do {
            _ = try TableParser.parse(table).columnLayout(parameterCount: parameterCount)
            return nil
        } catch let error as TableParseError {
            return (error.line, error.column, error.message)
        } catch let error as TableFitError {
            return (error.line, error.column, error.message)
        } catch {
            return (0, 0, String(describing: error))
        }
    }

    /// `__tabletest_<name>`, in backticks when the function's name is a raw identifier.
    private static func generatedName(for name: String) -> String {
        name.hasPrefix("`") ? "`__tabletest_\(name.withoutBackticks)`" : "__tabletest_\(name)"
    }

    /// `Type.` for a static function, and `Type().` for an instance function.
    private static func receiver(of function: FunctionDeclSyntax, in context: some MacroExpansionContext) -> String {
        guard let enclosingType = context.lexicalContext.lazy.compactMap(\.typeName).first else {
            return ""
        }
        let isStatic = function.modifiers.contains {
            $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class)
        }
        return isStatic ? "\(enclosingType)." : "\(enclosingType)()."
    }

    /// The global actor of the function, or else of its enclosing type, as an attribute prefix.
    private static func isolation(of function: FunctionDeclSyntax, in context: some MacroExpansionContext) -> String {
        let enclosingAttributes = context.lexicalContext.lazy
            .compactMap { $0.asProtocol(WithAttributesSyntax.self)?.attributes }
            .first ?? []
        return (Array(enclosingAttributes) + Array(function.attributes))
            .compactMap(\.globalActorName)
            .last
            .map { "@\($0) " } ?? ""
    }
}

/// The arguments of one `@TableTest` attribute: an optional display name, the traits, and the
/// table literal.
struct TableTestArguments {
    let displayName: StringLiteralExprSyntax?
    let traits: [ExprSyntax]
    let table: StringLiteralExprSyntax

    init(of attribute: AttributeSyntax) throws {
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
struct ArgumentError: Error {
    let node: Syntax
    let message: String
}

extension StringLiteralExprSyntax {
    /// The syntax node of a line of the literal's value, for a diagnostic: the string segment
    /// that starts the line in a multiline literal, or else the literal itself.
    ///
    /// A diagnostic cannot point at a column inside a node. The compiler places a macro
    /// diagnostic at the start of its node and ignores `Diagnostic.position`.
    func node(atLine line: Int) -> Syntax {
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

    var isMultiline: Bool {
        openingQuote.tokenKind == .multilineStringQuote
    }

    /// The number of columns that a multiline literal removes from each line: the indentation
    /// of its closing quote.
    var indentation: Int {
        guard isMultiline else {
            return 0
        }
        let lastLine = closingQuote.leadingTrivia.description.split(separator: "\n", omittingEmptySubsequences: false).last
            ?? segments.last.map { Substring($0.description.split(separator: "\n", omittingEmptySubsequences: false).last ?? "") }
            ?? ""
        return lastLine.unicodeScalars.prefix { $0 == " " || $0 == "\t" }.count
    }
}

extension FunctionDeclSyntax {
    var parameters: FunctionParameterListSyntax {
        signature.parameterClause.parameters
    }
}

extension String {
    var withoutBackticks: String {
        filter { $0 != "`" }
    }
}

extension SyntaxProtocol {
    /// The name of the type this syntax node declares or extends, if it is one.
    var typeName: String? {
        if let decl = self.as(StructDeclSyntax.self) { return decl.name.text }
        if let decl = self.as(ClassDeclSyntax.self) { return decl.name.text }
        if let decl = self.as(ActorDeclSyntax.self) { return decl.name.text }
        if let decl = self.as(EnumDeclSyntax.self) { return decl.name.text }
        if let decl = self.as(ExtensionDeclSyntax.self) { return decl.extendedType.trimmedDescription }
        return nil
    }
}

extension AttributeListSyntax.Element {
    /// The name of the global actor this attribute names: `MainActor`, or another name that
    /// ends in `Actor`. Syntax alone cannot tell a global actor from another attribute.
    fileprivate var globalActorName: String? {
        guard case .attribute(let attribute) = self else {
            return nil
        }
        let name = attribute.attributeName.trimmedDescription
        return name.hasSuffix("Actor") ? name : nil
    }
}

/// An error in a table, reported at its place in the source.
struct TableTestDiagnostic: DiagnosticMessage {
    let message: String

    init(_ message: String) {
        self.message = message
    }

    var diagnosticID: MessageID {
        MessageID(domain: "TableTest", id: "table")
    }

    var severity: DiagnosticSeverity {
        .error
    }
}

struct MacroError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}

@main
struct TableTestPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [TableTestMacro.self]
}
