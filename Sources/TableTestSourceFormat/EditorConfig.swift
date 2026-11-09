import Foundation

/// Reads the indentation properties that the `.editorconfig` files above a file set for it
/// (EditorConfig specification: https://spec.editorconfig.org).
///
/// The files are read from the file's directory upwards, up to and including one that says
/// `root = true`. A section applies when its glob matches the file's path relative to the
/// directory of its `.editorconfig`. A later section, and a nearer file, wins.
enum EditorConfig {
    /// The properties that decide an indent level.
    struct IndentProperties: Equatable {
        var style: String?
        var size: String?
        var tabWidth: String?

        /// The indent level these properties set, or `nil` when they set neither a style nor a size.
        var indentation: Indentation? {
            guard style != nil || size != nil else {
                return nil
            }
            if style == "tab" {
                return Indentation(style: .tabs, size: size.flatMap { Int($0) } ?? 1)
            }
            let tabWidth = tabWidth.flatMap { Int($0) } ?? 4
            let spaces = size == "tab" ? tabWidth : size.flatMap { Int($0) } ?? 4
            return Indentation(style: .spaces, size: spaces)
        }
    }

    /// The indent level that the `.editorconfig` files above the file set for it, if any.
    static func indentation(for file: URL) -> Indentation? {
        properties(for: file).indentation
    }

    static func properties(for file: URL) -> IndentProperties {
        let target = file.standardizedFileURL
        var configs: [(directory: URL, sections: [Section])] = []
        for directory in target.directoriesAbove {
            guard let text = try? String(contentsOf: directory.appendingPathComponent(".editorconfig"), encoding: .utf8) else {
                continue
            }
            let parsed = parse(text)
            configs.append((directory, parsed.sections))
            if parsed.isRoot {
                break
            }
        }
        var properties = IndentProperties()
        for config in configs.reversed() {
            let relativePath = String(String(target.path.dropFirst(config.directory.path.count)).trimmingPrefix("/"))
            for section in config.sections where section.glob?.matches(relativePath) == true {
                properties.style = section.values["indent_style"] ?? properties.style
                properties.size = section.values["indent_size"] ?? properties.size
                properties.tabWidth = section.values["tab_width"] ?? properties.tabWidth
            }
        }
        return properties
    }

    struct Section {
        let glob: Glob?
        var values: [String: String] = [:]
    }

    /// The sections of one file, and whether it says `root = true` before its first section.
    static func parse(_ text: String) -> (isRoot: Bool, sections: [Section]) {
        var isRoot = false
        var sections: [Section] = []
        for rawLine in text.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") || line.hasPrefix(";") {
                continue
            }
            if line.hasPrefix("["), let close = line.lastIndex(of: "]") {
                sections.append(Section(glob: Glob(String(line[line.index(after: line.startIndex)..<close]))))
                continue
            }
            guard let equals = line.firstIndex(of: "=") else {
                continue
            }
            let key = line[..<equals].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces).lowercased()
            if sections.isEmpty {
                isRoot = isRoot || (key == "root" && value == "true")
            } else {
                sections[sections.count - 1].values[key] = value
            }
        }
        return (isRoot, sections)
    }

    /// A section name as a regular expression over a path relative to the `.editorconfig`.
    struct Glob {
        private let regex: Regex<AnyRegexOutput>
        private let numberRanges: [ClosedRange<Int>]

        init?(_ glob: String) {
            var ranges: [ClosedRange<Int>] = []
            let body = Self.pattern(glob.hasPrefix("/") ? glob.dropFirst() : Substring(glob), numberRanges: &ranges)
            // A glob with a `/` is relative to the .editorconfig's directory; one without
            // matches a file name at any depth below it.
            let anchored = glob.contains("/") ? "^" + body + "$" : "^(?:.*/)?" + body + "$"
            guard let regex = try? Regex(anchored) else {
                return nil
            }
            self.regex = regex
            numberRanges = ranges
        }

        func matches(_ path: String) -> Bool {
            guard let match = try? regex.wholeMatch(in: path) else {
                return false
            }
            return numberRanges.indices.allSatisfy { index in
                guard let text = match.output[index + 1].substring, let number = Int(text) else {
                    return false
                }
                return numberRanges[index].contains(number)
            }
        }

        private static func pattern(_ glob: Substring, numberRanges: inout [ClosedRange<Int>]) -> String {
            var result = ""
            var index = glob.startIndex
            while index < glob.endIndex {
                let character = glob[index]
                let next = glob.index(after: index)
                switch character {
                case "\\" where next < glob.endIndex:
                    result += NSRegularExpression.escapedPattern(for: String(glob[next]))
                    index = glob.index(after: next)
                    continue
                case "*":
                    if next < glob.endIndex, glob[next] == "*" {
                        result += ".*"
                        index = glob.index(after: next)
                        continue
                    }
                    result += "[^/]*"
                case "?":
                    result += "[^/]"
                case "[":
                    if let close = glob[next...].firstIndex(of: "]") {
                        var content = String(glob[next..<close])
                        if content.hasPrefix("!") {
                            content = "^" + content.dropFirst()
                        }
                        result += "[" + content.replacingOccurrences(of: "\\", with: "\\\\") + "]"
                        index = glob.index(after: close)
                        continue
                    }
                    result += "\\["
                case "{":
                    if let close = closingBrace(in: glob, from: next) {
                        let content = glob[next..<close]
                        result += braces(content, numberRanges: &numberRanges)
                        index = glob.index(after: close)
                        continue
                    }
                    result += "\\{"
                default:
                    result += NSRegularExpression.escapedPattern(for: String(character))
                }
                index = next
            }
            return result
        }

        /// `{a,b}` as alternatives, `{3..7}` as a number in a range, anything else as text.
        private static func braces(_ content: Substring, numberRanges: inout [ClosedRange<Int>]) -> String {
            let range = content.split(separator: "..", omittingEmptySubsequences: false)
            if range.count == 2, let low = Int(range[0]), let high = Int(range[1]), low <= high {
                numberRanges.append(low...high)
                return "([+-]?[0-9]+)"
            }
            let alternatives = topLevelParts(of: content)
            guard alternatives.count > 1 else {
                return "\\{" + pattern(content, numberRanges: &numberRanges) + "\\}"
            }
            return "(?:" + alternatives.map { pattern($0, numberRanges: &numberRanges) }.joined(separator: "|") + ")"
        }

        private static func closingBrace(in glob: Substring, from start: Substring.Index) -> Substring.Index? {
            var depth = 1
            var index = start
            while index < glob.endIndex {
                switch glob[index] {
                case "{": depth += 1
                case "}":
                    depth -= 1
                    if depth == 0 {
                        return index
                    }
                default: break
                }
                index = glob.index(after: index)
            }
            return nil
        }

        private static func topLevelParts(of content: Substring) -> [Substring] {
            var parts: [Substring] = []
            var depth = 0
            var start = content.startIndex
            for index in content.indices {
                switch content[index] {
                case "{": depth += 1
                case "}": depth -= 1
                case "," where depth == 0:
                    parts.append(content[start..<index])
                    start = content.index(after: index)
                default: break
                }
            }
            parts.append(content[start...])
            return parts
        }
    }
}
