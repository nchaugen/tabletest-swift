import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

/// Expands `@TableTest` on a function to a Swift Testing test that calls the function once
/// for each row of the table.
public struct TableTestMacro: PeerMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingPeersOf declaration: some DeclSyntaxProtocol,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        []
    }
}

@main
struct TableTestPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [TableTestMacro.self]
}
