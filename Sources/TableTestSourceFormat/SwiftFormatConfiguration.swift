import Foundation

/// Reads the indent level from the nearest `.swift-format`, the configuration file of Apple's
/// swift-format, in the file's directory or above it.
enum SwiftFormatConfiguration {
    /// swift-format's own default when its configuration names no indentation.
    static let defaultIndentation = Indentation(style: .spaces, size: 2)

    /// The indent level of the nearest `.swift-format`, or `nil` when there is none or it does
    /// not parse.
    static func indentation(for file: URL) -> Indentation? {
        for directory in file.directoriesAbove {
            if let data = try? Data(contentsOf: directory.appendingPathComponent(".swift-format")) {
                return indentation(in: data)
            }
        }
        return nil
    }

    /// `"indentation": {"spaces": N}` or `{"tabs": N}`; no key means swift-format's default.
    private static func indentation(in data: Data) -> Indentation? {
        guard let configuration = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        guard let indentation = configuration["indentation"] as? [String: Any] else {
            return defaultIndentation
        }
        if let spaces = indentation["spaces"] as? Int {
            return Indentation(style: .spaces, size: spaces)
        }
        if let tabs = indentation["tabs"] as? Int {
            return Indentation(style: .tabs, size: tabs)
        }
        return nil
    }
}

extension Indentation {
    /// The indent level when no configuration sets one.
    public static let fourSpaces = Indentation(style: .spaces, size: 4)

    /// The indent level for a table in a Swift file: from `.editorconfig` when it sets one for
    /// the file, else from the nearest `.swift-format`, else 4 spaces.
    public static func forSwiftFile(at file: URL) -> Indentation {
        EditorConfig.indentation(for: file) ?? SwiftFormatConfiguration.indentation(for: file) ?? .fourSpaces
    }
}
