import Foundation
import TableTestFormat

/// The `tabletest-format` command: formats the tables in `.swift` and `.table` files, or checks
/// that they are formatted. Its options, output and exit codes follow the JVM CLI.
public enum FormatCommand {
    public static let usage = """
        Usage: tabletest-format [-c | --check] [-v | --verbose] PATH...
        Formats the TableTest tables in .swift and .table files. A directory is searched
        recursively; hidden directories such as .build are skipped.
          -c, --check     Report the files that need formatting; change none.
          -v, --verbose   Print the result for each file.
          -h, --help      Print this help.
        Exit status: 0 on success; 1 when a file cannot be formatted, or when --check finds a
        file that needs formatting; 2 on wrong use.
        """

    /// Runs the command and returns its exit status.
    public static func run(arguments: [String], output: (String) -> Void, errorOutput: (String) -> Void) -> Int32 {
        guard let options = Options(arguments) else {
            errorOutput(usage)
            return 2
        }
        if options.showsHelp {
            output(usage)
            return 0
        }
        let files = discover(options.paths)
        guard !files.isEmpty else {
            output("No files found to format")
            return 0
        }
        var changed: [String] = []
        var failed: [String] = []
        for file in files {
            do {
                let isChanged = try format(file, write: !options.checks)
                if isChanged {
                    changed.append(file)
                }
                if options.isVerbose {
                    output("\(file) - \(isChanged ? "needs formatting" : "already formatted")")
                }
            } catch {
                failed.append(file)
                errorOutput("Error formatting \(file): \(error)")
            }
        }
        output("\(options.checks ? "Checked" : "Formatted") \(files.count) files")
        if changed.isEmpty {
            output("All files are already formatted")
        } else if options.checks {
            output("\(changed.count) files need formatting:")
            changed.forEach { output("  \($0)") }
        } else {
            output("\(changed.count) files were reformatted")
        }
        if !failed.isEmpty {
            errorOutput("\(failed.count) files could not be formatted:")
            failed.forEach { errorOutput("  \($0)") }
        }
        return !failed.isEmpty || (options.checks && !changed.isEmpty) ? 1 : 0
    }

    private struct Options {
        var checks = false
        var isVerbose = false
        var showsHelp = false
        var paths: [String] = []

        /// The options, or `nil` for wrong use: an unknown option, or no path.
        init?(_ arguments: [String]) {
            for argument in arguments {
                switch argument {
                case "-c", "--check": checks = true
                case "-v", "--verbose": isVerbose = true
                case "-h", "--help": showsHelp = true
                case let option where option.hasPrefix("-"): return nil
                default: paths.append(argument)
                }
            }
            if paths.isEmpty && !showsHelp {
                return nil
            }
        }
    }

    private static let extensions: Set<String> = ["swift", "table"]

    /// The `.swift` and `.table` files at the paths, sorted; a directory is searched
    /// recursively, without its hidden directories.
    private static func discover(_ paths: [String]) -> [String] {
        paths.flatMap { path -> [String] in
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
                return [path]
            }
            let root = URL(fileURLWithPath: path, isDirectory: true)
            let entries = FileManager.default.enumerator(
                at: root,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            )
            return (entries?.allObjects as? [URL] ?? []).compactMap { url in
                guard (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true else {
                    return nil
                }
                let relative = url.standardizedFileURL.path.dropFirst(root.standardizedFileURL.path.count)
                return (path.hasSuffix("/") ? String(path.dropLast()) : path) + relative
            }
        }
        .filter { extensions.contains(URL(fileURLWithPath: $0).pathExtension) }
        .sorted()
    }

    /// Formats one file; writes it when asked and it changed. Returns whether it changed.
    private static func format(_ path: String, write: Bool) throws -> Bool {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw FormatError("the file is not UTF-8")
        }
        let formatted = url.pathExtension == "table"
            ? TableFormatter.format(content)
            : SwiftSourceFormatter.format(content, indentation: .forSwiftFile(at: url))
        guard formatted != content else {
            return false
        }
        if write {
            try replace(url, with: formatted)
        }
        return true
    }

    /// Writes through a temporary file in the same directory, which then takes the file's place
    /// with the file's permissions.
    private static func replace(_ file: URL, with content: String) throws {
        let temporary = file.deletingLastPathComponent().appendingPathComponent(".tabletest-format-\(UUID().uuidString).tmp")
        do {
            try Data(content.utf8).write(to: temporary)
            if let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] {
                try FileManager.default.setAttributes([.posixPermissions: permissions], ofItemAtPath: temporary.path)
            }
            guard rename(temporary.path, file.path) == 0 else {
                throw FormatError("cannot replace the file: \(String(cString: strerror(errno)))")
            }
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
    }
}

struct FormatError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
