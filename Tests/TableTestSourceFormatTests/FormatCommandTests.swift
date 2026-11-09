import Foundation
import Testing
import TableTestSourceFormat

/// The `tabletest-format` command, run on files in a new temporary directory. It mirrors the
/// JVM CLI: `--check` reports and writes nothing, the default writes, the exit code is 1 when a
/// file fails or `--check` finds work. A directory walk skips hidden directories, such as
/// `.build`, which hold the sources of dependencies.
@Suite("tabletest-format")
struct FormatCommandTests {
    private let unformatted = "a|b\nx|y\n"
    private let formatted = "a | b\nx | y\n"

    @Test("Reports the files that need formatting and changes none when checking")
    func checks() throws {
        let directory = try TemporaryDirectory(files: ["T.table": unformatted, "Done.table": formatted])

        let run = Run(["--check", directory.root.path])

        #expect(run.status == 1)
        #expect(run.output.contains("Checked 2 files"))
        #expect(run.output.contains("1 files need formatting:"))
        #expect(run.output.contains("  \(directory.url(of: "T.table").path)"))
        #expect(try String(contentsOf: directory.url(of: "T.table"), encoding: .utf8) == unformatted)
    }

    @Test("Formats the files in place and keeps their permissions")
    func writes() throws {
        let directory = try TemporaryDirectory(files: ["T.table": unformatted])
        let file = directory.url(of: "T.table")
        try FileManager.default.setAttributes([.posixPermissions: 0o754], ofItemAtPath: file.path)

        let run = Run([file.path])

        #expect(run.status == 0)
        #expect(run.output.contains("1 files were reformatted"))
        #expect(try String(contentsOf: file, encoding: .utf8) == formatted)
        #expect(try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int == 0o754)
    }

    @Test("Formats Swift and table files, and skips other files and hidden directories")
    func walksADirectory() throws {
        let swift = "struct T {\n    @TableTest(\"\"\"\n    a|b\n    \"\"\")\n    func f(a: Int, b: Int) {}\n}\n"
        let directory = try TemporaryDirectory(files: [
            "Tests/A.swift": swift,
            "Tests/Data/B.table": unformatted,
            "notes.txt": unformatted,
            ".build/checkouts/C.swift": swift,
        ])

        let run = Run(["-v", directory.root.path])

        #expect(run.status == 0)
        #expect(run.output.contains("Formatted 2 files"))
        #expect(run.output.contains("\(directory.url(of: "Tests/A.swift").path) - needs formatting"))
        #expect(try String(contentsOf: directory.url(of: "Tests/A.swift"), encoding: .utf8).contains("        a | b\n        \"\"\")"))
        #expect(try String(contentsOf: directory.url(of: "notes.txt"), encoding: .utf8) == unformatted)
        #expect(try String(contentsOf: directory.url(of: ".build/checkouts/C.swift"), encoding: .utf8) == swift)
    }

    @Test("Says when every file is already formatted")
    func reportsNothingToDo() throws {
        let directory = try TemporaryDirectory(files: ["Done.table": formatted])

        let run = Run(["--check", "--verbose", directory.root.path])

        #expect(run.status == 0)
        #expect(run.output.contains("\(directory.url(of: "Done.table").path) - already formatted"))
        #expect(run.output.contains("All files are already formatted"))
    }

    @Test("Reports a file it cannot read, and fails")
    func reportsAnUnreadableFile() throws {
        let directory = try TemporaryDirectory(files: ["Good.table": formatted])
        try Data([0xFF, 0xFE, 0x00, 0xD8]).write(to: directory.url(of: "Bad.table"))

        let run = Run([directory.root.path])

        #expect(run.status == 1)
        #expect(run.errors.contains("Error formatting \(directory.url(of: "Bad.table").path)"))
        #expect(run.errors.contains("1 files could not be formatted:"))
    }

    @Test("Says when it finds no file to format")
    func findsNoFiles() throws {
        let directory = try TemporaryDirectory(files: ["notes.txt": unformatted])

        let run = Run([directory.root.path])

        #expect(run.status == 0)
        #expect(run.output.contains("No files found to format"))
    }

    @Test("Refuses a call without a path, or with an unknown option", arguments: [
        [String](),
        ["--fix", "Sources"],
    ])
    func refusesWrongUse(arguments: [String]) {
        let run = Run(arguments)

        #expect(run.status == 2)
        #expect(run.errors.contains("Usage: tabletest-format"))
    }

    @Test("Prints its usage on request")
    func printsUsage() {
        let run = Run(["--help"])

        #expect(run.status == 0)
        #expect(run.output.contains("Usage: tabletest-format [-c | --check] [-v | --verbose] PATH..."))
    }
}

/// One run of the command, with what it printed.
private struct Run {
    let status: Int32
    let output: String
    let errors: String

    init(_ arguments: [String]) {
        var output: [String] = []
        var errors: [String] = []
        status = FormatCommand.run(arguments: arguments, output: { output.append($0) }, errorOutput: { errors.append($0) })
        self.output = output.joined(separator: "\n")
        self.errors = errors.joined(separator: "\n")
    }
}
