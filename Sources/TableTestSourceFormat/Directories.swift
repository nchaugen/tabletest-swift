import Foundation

extension URL {
    /// The directory of a file and every directory above it, nearest first, up to the root.
    ///
    /// Walks by path components: `deletingLastPathComponent()` on `/` can give `/..`, which
    /// never reaches a fixed point.
    var directoriesAbove: [URL] {
        var components = standardizedFileURL.deletingLastPathComponent().pathComponents
        var directories: [URL] = []
        while !components.isEmpty {
            directories.append(URL(fileURLWithPath: NSString.path(withComponents: components), isDirectory: true))
            components.removeLast()
        }
        return directories
    }
}
