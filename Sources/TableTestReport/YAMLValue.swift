import Foundation

/// A YAML value in flow style, as the reporter's YAML files hold it.
indirect enum YAMLValue {
    case text(String), number(Int), boolean(Bool), null
    case sequence([YAMLValue]), set([YAMLValue]), mapping([(String, YAMLValue)])

    func rendered() throws -> String {
        switch self {
        case .text(let text): return try Self.quoted(text)
        case .number(let number): return String(number)
        case .boolean(let flag): return String(flag)
        case .null: return "null"
        case .sequence(let items): return try "[" + items.map { try $0.rendered() }.joined(separator: ", ") + "]"
        case .set(let items): return try "!!set {" + items.map { "? \(try $0.rendered()) : null" }.joined(separator: ", ") + "}"
        case .mapping(let entries):
            return try "{" + entries.map { key, value in "\(try Self.quoted(key)): \(try value.rendered())" }
                .joined(separator: ", ") + "}"
        }
    }

    /// A double-quoted YAML scalar. A JSON string is one, once the line breaks that YAML reads
    /// and JSON does not escape are escaped too.
    private static func quoted(_ text: String) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        return try String(decoding: encoder.encode(text), as: UTF8.self)
            .replacingOccurrences(of: "\u{85}", with: "\\u0085")
            .replacingOccurrences(of: "\u{2028}", with: "\\u2028")
            .replacingOccurrences(of: "\u{2029}", with: "\\u2029")
    }
}
