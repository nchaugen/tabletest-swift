import Foundation

/// Finds and reads the vendored fixture files of `tabletest-spec`.
public enum FixtureFiles {
    /// The JSON files of a fixture directory in name order.
    ///
    /// Throws when the directory is missing or holds no file, so that zero cases is never a pass.
    public static func files(in directory: URL?) throws -> [URL] {
        guard let directory else {
            throw FixtureError("The test bundle has no fixture directory")
        }
        let files = try FileManager.default
            .contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard !files.isEmpty else {
            throw FixtureError("No fixture files in \(directory.path)")
        }
        return files
    }

    /// The cases of one fixture file.
    public static func cases<Case: Decodable>(_ type: Case.Type, in file: URL) throws -> [Case] {
        try JSONDecoder().decode([Case].self, from: Data(contentsOf: file))
    }
}

public struct FixtureError: Error, CustomStringConvertible {
    public let description: String

    public init(_ description: String) {
        self.description = description
    }
}
