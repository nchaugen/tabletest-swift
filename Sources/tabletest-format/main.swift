import Foundation
import TableTestSourceFormat

let status = FormatCommand.run(
    arguments: Array(CommandLine.arguments.dropFirst()),
    output: { print($0) },
    errorOutput: { FileHandle.standardError.write(Data(($0 + "\n").utf8)) }
)
exit(status)
