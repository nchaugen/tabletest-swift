import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

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
        let arguments = try TableTestArguments(of: node)
        guard let table = arguments.table.representedLiteralValue else {
            throw MacroError("@TableTest needs a table without string interpolation")
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
            throw MacroError("@TableTest needs a table")
        }
        guard let table = tableArgument.expression.as(StringLiteralExprSyntax.self) else {
            throw MacroError("@TableTest needs the table as a string literal")
        }
        let leading = arguments.filter { $0.label == nil && $0.id != tableArgument.id }
        let displayName = leading.first?.expression.as(StringLiteralExprSyntax.self)
        self.table = table
        self.displayName = displayName
        self.traits = leading.dropFirst(displayName == nil ? 0 : 1).map(\.expression)
    }
}

extension StringLiteralExprSyntax {
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
    fileprivate var typeName: String? {
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
