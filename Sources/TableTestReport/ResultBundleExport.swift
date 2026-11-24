import Foundation

/// Exports TableTest manifests and outcomes from the public Xcode result bundle commands.
package enum ResultBundleExport {
    package static func run(bundle: URL, output: URL) throws {
        let files = FileManager.default
        guard !files.fileExists(atPath: output.path) else {
            throw ExportError("Output directory already exists: \(output.path)")
        }
        let staging = output.deletingLastPathComponent()
            .appendingPathComponent(".tabletest-export-\(UUID().uuidString)", isDirectory: true)
        try files.createDirectory(at: staging, withIntermediateDirectories: false)
        defer { try? files.removeItem(at: staging) }

        let attachments = staging.appendingPathComponent("attachments", isDirectory: true)
        let results = XcodeResults(bundle: bundle)
        let groups = try results.exportManifests(to: attachments)
        let report = try results.tests()
        let tables = try tables(in: groups, attachments: attachments, report: report, results: results)
        guard !tables.isEmpty else {
            throw ExportError("No TableTest manifests found. Enable TABLETEST_REPORTING and include the companion tests.")
        }
        try ReportFiles.write(tables, devices: report.devices, to: staging)
        try files.moveItem(at: staging, to: output)
    }

    private static func tables(
        in groups: [AttachmentGroup], attachments: URL, report: TestReport, results: XcodeResults
    ) throws -> [[TableAttempt]] {
        let nodes = report.testNodes.flatMap(\.descendants)
        let tests = Dictionary(grouping: nodes.filter { $0.kind == .test }, by: RowTestKey.init)
        let devices = Dictionary(grouping: report.devices, by: \.id)
        let configurations = Dictionary(grouping: report.testPlanConfigurations, by: \.name)

        return try groups.sorted { $0.testIdentifierURL < $1.testIdentifierURL }.compactMap { group in
            let copies = group.attachments.filter(\.isTableManifest)
            guard !copies.isEmpty else { return nil }
            let contexts = Dictionary(grouping: copies) {
                RunContext(deviceID: $0.deviceId, configurationName: $0.configurationName)
            }
            let manifests = try contexts.map { context, copies in
                (context: context, manifest: try manifest(in: attachments, copies: copies, test: group, context: context))
            }.sorted { $0.context < $1.context }
            let parent = parentURL(of: group.testIdentifierURL)
            let functions = Set(manifests.map(\.manifest.testFunction))
            let tableTests = try Dictionary(uniqueKeysWithValues: functions.map { function in
                (function, try TableTestRuns(parent: parent, function: function, tests: tests, results: results))
            })

            let attempts = try manifests.flatMap { context, manifest in
                guard let matchingDevices = devices[context.deviceID], matchingDevices.count == 1 else {
                    throw ExportError("Ambiguous destination \(context.deviceID) for \(group.testIdentifier).")
                }
                guard let matchingConfigurations = configurations[context.configurationName], matchingConfigurations.count == 1 else {
                    throw ExportError("Ambiguous configuration \(context.configurationName) for \(group.testIdentifier).")
                }
                let device = matchingDevices[0]
                let configuration = matchingConfigurations[0]
                let tableTest = tableTests[manifest.testFunction] ?? .notRun
                let runs = tableTest.runs.filter { $0.context == context }
                let fallback = TestRun(
                    device: device, configuration: configuration, attempt: 1, attemptName: "First Run",
                    identity: nil, xcodeDisplayName: nil, caseURL: nil, status: "Not Run", message: nil
                )
                let planned = Set(manifest.rows.flatMap { row in row.cases.map { CaseIdentity(row: row.index, number: $0.number) } })
                guard runs.compactMap(\.identity).allSatisfy(planned.contains) else {
                    throw ExportError("Unexpected case identities in \(tableTest.url ?? group.testIdentifier).")
                }
                let firstInvocations = manifest.rows.reduce(into: [1]) { starts, row in
                    starts.append(starts[starts.count - 1] + row.cases.count)
                }
                let outcomes = try zip(manifest.rows, firstInvocations).flatMap { row, firstInvocation in
                    try outcomes(for: row, testURL: tableTest.url, firstInvocation: firstInvocation, runs: runs, fallback: fallback)
                }
                let byAttempt = outcomes.isEmpty ? [1: []] : Dictionary(grouping: outcomes, by: \.attempt)
                return byAttempt.keys.sorted().map { number in
                    let cases = byAttempt[number, default: []]
                    let names = Set(cases.map(\.attemptName))
                    return TableAttempt(
                        manifest: manifest, outcomes: cases, device: device, configuration: configuration,
                        attemptName: names.count == 1 ? names.first ?? "Attempt \(number)" : "Attempt \(number)"
                    )
                }
            }
            let observedContexts = Set(tableTests.values.flatMap { $0.runs.map(\.context) })
            let missing = observedContexts.subtracting(contexts.keys)
            guard missing.isEmpty else {
                let names = missing.sorted().map { "\($0.deviceID) / \($0.configurationName)" }.joined(separator: ", ")
                throw ExportError("Missing manifests for \(group.testIdentifier) on \(names).")
            }
            return attempts
        }
    }

    /// The runs of the Swift Testing function that runs the cases of a table.
    private struct TableTestRuns {
        static let notRun = TableTestRuns(url: nil, runs: [])

        let url: String?
        let runs: [TestRun]

        init(url: String?, runs: [TestRun]) {
            self.url = url
            self.runs = runs
        }

        init(parent: String, function: String, tests: [RowTestKey: [TestNode]], results: XcodeResults) throws {
            let matches = tests[RowTestKey(parent: parent, function: function)] ?? []
            guard matches.count <= 1 else {
                throw ExportError("Expected at most one result for \(parent)/\(function), found \(matches.count).")
            }
            url = matches.first?.nodeIdentifierURL
            runs = try url.map { try results.testDetails(id: $0).runs() } ?? []
        }
    }

    private static func manifest(
        in directory: URL, copies: [AttachmentGroup.Attachment], test: AttachmentGroup, context: RunContext
    ) throws -> ReportManifest {
        let decoder = JSONDecoder()
        var manifest: ReportManifest?
        for copy in copies {
            let filename = copy.exportedFileName
            guard !filename.isEmpty, filename != ".", filename != "..", !filename.contains("/") else {
                throw ExportError("Invalid exported attachment filename: \(filename)")
            }
            let data = try Data(contentsOf: directory.appendingPathComponent(filename))
            let decoded = try decoder.decode(ReportManifest.self, from: data)
            guard decoded.version == 1 else {
                throw ExportError("Unsupported TableTest manifest version for \(test.testIdentifier): \(decoded.version).")
            }
            if let manifest, manifest != decoded {
                throw ExportError("Conflicting manifests for \(test.testIdentifier) on \(context.deviceID) in \(context.configurationName).")
            }
            manifest = decoded
        }
        guard let manifest else { throw ExportError("No manifest for \(test.testIdentifier).") }
        return manifest
    }

    private static func outcomes(
        for row: ReportRow, testURL: String?, firstInvocation: Int, runs: [TestRun], fallback: TestRun
    ) throws -> [CaseOutcome] {
        let caseRuns = Dictionary(grouping: runs.filter { $0.identity?.row == row.index }, by: \.identity)
        let rowRuns = runs.filter { $0.identity == nil }
        return try row.cases.enumerated().flatMap { offset, entry in
            let identity = CaseIdentity(row: row.index, number: entry.number)
            let attempts = caseRuns[identity] ?? (rowRuns.isEmpty ? [fallback] : rowRuns)
            guard Set(attempts.map(\.attempt)).count == attempts.count else {
                throw ExportError("Xcode returned indistinguishable attempts for row \(row.index), case \(entry.number).")
            }
            return attempts.sorted { $0.attempt < $1.attempt }.map { run in
                CaseOutcome(
                    rowIndex: row.index, caseNumber: entry.number, invocationIndex: firstInvocation + offset,
                    displayName: entry.displayName, xcodeDisplayName: run.xcodeDisplayName,
                    device: run.device, configuration: run.configuration, attempt: run.attempt, attemptName: run.attemptName,
                    status: run.status, testURL: testURL, caseURL: run.caseURL, message: run.message
                )
            }
        }
    }

    private struct RowTestKey: Hashable {
        let parent: String
        let function: String

        init(parent: String, function: String) {
            self.parent = parent
            self.function = function
        }

        init(_ test: TestNode) {
            parent = parentURL(of: test.nodeIdentifierURL ?? "")
            function = test.nodeIdentifier?.split(separator: "/").last.map(String.init) ?? ""
        }
    }

    private static func parentURL(of url: String) -> String {
        guard let separator = url.lastIndex(of: "/") else { return "" }
        return String(url[..<separator])
    }
}

struct TableAttempt {
    let manifest: ReportManifest
    let outcomes: [CaseOutcome]
    let device: Device
    let configuration: Configuration
    let attemptName: String
}

struct CaseOutcome: Encodable {
    let rowIndex: Int
    let caseNumber: Int
    let invocationIndex: Int
    let displayName: String
    let xcodeDisplayName: String?
    let device: Device
    let configuration: Configuration
    let attempt: Int
    let attemptName: String
    let status: String
    let testURL: String?
    let caseURL: String?
    let message: String?

    var completed: Bool {
        ["Passed", "Failed", "Expected Failure"].contains(status)
    }

    var failed: Bool { status == "Failed" }
}
