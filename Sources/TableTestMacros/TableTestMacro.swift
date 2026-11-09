import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxMacros
import TableTestParser
import TableTestSyntax

/// Expands `@TableTest` on a function to a Swift Testing test that calls the function once
/// for each row of the table.
///
/// The expansion is a nested type that holds the `@Test` function `scenarios`, so the Xcode
/// test tree reads `Suite > title > scenarios(_:) > case`. The type takes the test's title as a
/// raw identifier, or else the function's name. A `@Test`
/// written directly beside the function does not compile, because a nested macro expansion does
/// not see the enclosing type. The `@Test` function cannot share the type's name: Swift Testing
/// creates the suite instance by the type's name, which inside the type would name the function.
/// A static function cannot share its name with a type, so its type is `__tabletest_<name>`. The
/// table text goes to the runtime, which parses it and converts the cells: the macro only reads
/// the syntax around it.
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
        let parameterList = function.parameters
            .map { "TableParameter((\($0.type.trimmedDescription)).self)" }
            .joined(separator: ", ")
        let title = arguments.displayName?.trimmedDescription ?? "\"\(name.withoutBackticks)\""
        let testAttributeArguments = ([title] + arguments.traits.map(\.trimmedDescription) + [
            """
            arguments: try TableTestRows.make(
                table: \(StringLiteralExprSyntax(content: table)),
                parameters: [\(parameterList)],
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
        let receiver = receiver(of: function, in: context)
        let call = "try \(isAsync ? "await " : "")\(receiver.prefix)\(name)(\(callArguments))"

        return [
            """
            \(raw: isolation(of: function, in: context))struct \(raw: typeName(for: function, title: arguments.displayName)) {
                @Test(\(raw: testAttributeArguments))
                func scenarios(_ row: TableTestRow) \(raw: isAsync || receiver.makesSuite ? "async " : "")throws {
                    \(raw: receiver.statement)\(raw: isThrowing ? "do" : "do throws(TableCellError)") {
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

    /// The test's title as a raw identifier, so Xcode shows the title. Else the function's own
    /// name; for a static function, which cannot share its name with a type, `__tabletest_<name>`.
    private static func typeName(for function: FunctionDeclSyntax, title: StringLiteralExprSyntax?) -> String {
        let name = function.name.text
        if function.isStatic {
            return name.hasPrefix("`") ? "`__tabletest_\(name.withoutBackticks)`" : "__tabletest_\(name)"
        }
        if let title = title?.representedLiteralValue, title.canBeRawIdentifier {
            return "`\(title)`"
        }
        return name
    }

    /// How the expansion reaches the function: `Type.` for a static function. For an instance
    /// function it makes the suite first, as Swift Testing does, so that the suite's `init` can
    /// throw or suspend outside the block that catches only cell errors.
    private static func receiver(of function: FunctionDeclSyntax,
                                 in context: some MacroExpansionContext) -> (statement: String, prefix: String, makesSuite: Bool) {
        guard let enclosingType = context.lexicalContext.lazy.compactMap(\.typeName).first else {
            return ("", "", false)
        }
        if function.isStatic {
            return ("", "\(enclosingType).", false)
        }
        return ("let suite = try await TableTestRows.suite(\(enclosingType)())\n        ", "suite.", true)
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

extension FunctionDeclSyntax {
    var parameters: FunctionParameterListSyntax {
        signature.parameterClause.parameters
    }

    var isStatic: Bool {
        modifiers.contains { $0.name.tokenKind == .keyword(.static) || $0.name.tokenKind == .keyword(.class) }
    }
}

extension String {
    var withoutBackticks: String {
        filter { $0 != "`" }
    }

    /// Whether the text can stand between backticks as a name: it holds a letter or a digit, and
    /// no backtick, backslash or control character.
    var canBeRawIdentifier: Bool {
        unicodeScalars.contains { $0.properties.isAlphabetic || $0.properties.numericType != nil }
            && !unicodeScalars.contains {
                $0 == "`" || $0 == "\\" || [.control, .lineSeparator, .paragraphSeparator].contains($0.properties.generalCategory)
            }
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
