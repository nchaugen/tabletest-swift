import Foundation
import TableTestReport

let usage = "Usage: tabletest-export <results.xcresult> <new output directory>"
let arguments = Array(CommandLine.arguments.dropFirst())

if arguments == ["--help"] || arguments == ["-h"] {
    print(usage)
    exit(0)
}

guard arguments.count == 2 else {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(2)
}

do {
    let bundle = URL(fileURLWithPath: arguments[0], isDirectory: true).standardizedFileURL
    let output = URL(fileURLWithPath: arguments[1], isDirectory: true).standardizedFileURL
    try ResultBundleExport.run(bundle: bundle, output: output)
} catch {
    FileHandle.standardError.write(Data(("tabletest-export: \(error.localizedDescription)\n").utf8))
    exit(1)
}
