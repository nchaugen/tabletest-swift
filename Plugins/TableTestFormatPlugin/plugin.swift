import Foundation
import PackagePlugin

/// Runs `tabletest-format` over the tables of a package or an Xcode project:
/// `swift package tabletest-format [--check] [--verbose] [--target NAME]...`.
///
/// With no `--target`, it formats the `.swift` and `.table` files of every target. `--check` reports the files that
/// need formatting and changes none.
@main
struct TableTestFormatPlugin: CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        var extractor = ArgumentExtractor(arguments)
        let targetNames = extractor.extractOption(named: "target")
        let targets = targetNames.isEmpty ? context.package.targets : try context.package.targets(named: targetNames)
        let files = targets.compactMap { $0 as? SourceModuleTarget }.flatMap(\.sourceFiles).map(\.url)
        try runFormatter(context.tool(named: "tabletest-format").url, extractor.remainingArguments, files)
    }
}

/// Runs the formatter on the `.swift` and `.table` files, after the options, and fails when it
/// exits with an error.
func runFormatter(_ formatter: URL, _ options: [String], _ files: [URL]) throws {
    let tableFiles = files.filter { ["swift", "table"].contains($0.pathExtension) }.map(\.path)
    guard !tableFiles.isEmpty else {
        Diagnostics.remark("No .swift or .table files in the selected targets")
        return
    }
    let process = Process()
    process.executableURL = formatter
    process.arguments = options + tableFiles
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw FormatterFailure(status: process.terminationStatus)
    }
}

/// The formatter found a file that needs formatting under `--check`, or could not format one.
struct FormatterFailure: Error, CustomStringConvertible {
    let status: Int32

    var description: String {
        status == 1
            ? "tabletest-format found tables that need formatting, or a file it could not format"
            : "tabletest-format exited with status \(status)"
    }
}

#if canImport(XcodeProjectPlugin)
import XcodeProjectPlugin

extension TableTestFormatPlugin: XcodeCommandPlugin {
    /// Formats the `.swift` and `.table` files of the targets that Xcode passes as `--target`,
    /// or of every target.
    func performCommand(context: XcodePluginContext, arguments: [String]) throws {
        var extractor = ArgumentExtractor(arguments)
        let targetNames = Set(extractor.extractOption(named: "target"))
        let files = context.xcodeProject.targets
            .filter { targetNames.isEmpty || targetNames.contains($0.displayName) }
            .flatMap(\.inputFiles)
            .map(\.url)
        try runFormatter(context.tool(named: "tabletest-format").url, extractor.remainingArguments, files)
    }
}
#endif
