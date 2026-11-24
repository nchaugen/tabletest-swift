import Foundation

struct ExportError: LocalizedError {
    let errorDescription: String?

    init(_ message: String) {
        errorDescription = message
    }
}

/// The parts of a result bundle that the export reads.
protocol TestResults {
    /// Writes the TableTest manifests of the bundle to the directory, and lists them by test.
    func exportManifests(to directory: URL) throws -> [AttachmentGroup]
    /// The tree of tests, with the destinations and configurations of the run.
    func tests() throws -> TestReport
    /// The runs of one test, by destination, configuration, attempt and case.
    func testDetails(id: String) throws -> TestDetails
}

/// Reads a result bundle with the public `xcresulttool` commands.
struct XcodeResults: TestResults {
    let bundle: URL

    func exportManifests(to directory: URL) throws -> [AttachmentGroup] {
        _ = try command(
            "export", "attachments", "--path", bundle.path, "--output-path", directory.path,
            "--filter", "tabletest-manifest*.json"
        )
        return try JSONDecoder().decode(
            [AttachmentGroup].self, from: Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        )
    }

    func tests() throws -> TestReport {
        try JSONDecoder().decode(TestReport.self, from: command("get", "test-results", "tests", "--path", bundle.path))
    }

    func testDetails(id: String) throws -> TestDetails {
        try JSONDecoder().decode(
            TestDetails.self,
            from: command("get", "test-results", "test-details", "--path", bundle.path, "--test-id", id)
        )
    }

    private func command(_ arguments: String...) throws -> Data {
        #if os(macOS)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["xcresulttool"] + arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationReason == .exit, process.terminationStatus == 0 else {
            throw ExportError("xcresulttool \(arguments.prefix(3).joined(separator: " ")) failed with status \(process.terminationStatus).")
        }
        return data
        #else
        throw ExportError("tabletest-export requires macOS with Xcode installed.")
        #endif
    }
}

struct AttachmentGroup: Decodable {
    let testIdentifier: String
    let testIdentifierURL: String
    let attachments: [Attachment]

    struct Attachment: Decodable {
        let deviceId: String
        let configurationName: String
        let exportedFileName: String
        let suggestedHumanReadableName: String

        var isTableManifest: Bool {
            suggestedHumanReadableName == "tabletest-manifest.json" ||
                (suggestedHumanReadableName.hasPrefix("tabletest-manifest_") &&
                    suggestedHumanReadableName.hasSuffix(".json"))
        }
    }
}

struct TestReport: Decodable {
    let devices: [Device]
    let testPlanConfigurations: [Configuration]
    let testNodes: [TestNode]

    /// The names that Xcode shows for the suites that hold the test, outermost first. A suite's
    /// name is its display name when it has one.
    func suiteNames(ofTest url: String) -> [String] {
        testNodes.lazy.compactMap { $0.suiteNames(toTest: url, below: []) }.first ?? []
    }
}

struct TestDetails: Decodable {
    let devices: [Device]
    let testPlanConfigurations: [Configuration]
    let testRuns: [TestNode]
}

protocol RunDimension: Decodable, Encodable {
    var id: String { get }
    var name: String { get }
}

struct Device: RunDimension {
    let deviceId: String
    let deviceName: String
    let architecture: String?
    let modelName: String?
    let platform: String?
    let osVersion: String?
    let osBuildNumber: String?

    var id: String { deviceId }
    var name: String { deviceName }
}

struct Configuration: RunDimension {
    let configurationId: String
    let configurationName: String

    var id: String { configurationId }
    var name: String { configurationName }
}

struct TestNode: Decodable {
    enum Kind: String {
        case suite = "Test Suite"
        case test = "Test Case"
        case device = "Device"
        case configuration = "Test Plan Configuration"
        case arguments = "Arguments"
        case repetition = "Repetition"
        case skipped = "Skip Message"
        case testRun = "Test Case Run"
    }

    let nodeType: String
    let name: String
    let nodeIdentifier: String?
    let nodeIdentifierURL: String?
    let result: CaseStatus?
    let details: String?
    private let children: [Self]?

    /// The type that Xcode names for the reflected argument of a `@TableTest` case.
    static let tableTestRowType = "TableTest.TableTestRow"

    var kind: Kind? { Kind(rawValue: nodeType) }
    var descendants: [Self] { [self] + directChildren.flatMap(\.descendants) }

    fileprivate func suiteNames(toTest url: String, below suites: [String]) -> [String]? {
        if nodeIdentifierURL == url { return suites }
        let names = kind == .suite ? suites + [name] : suites
        return directChildren.lazy.compactMap { $0.suiteNames(toTest: url, below: names) }.first
    }
    var directChildren: [Self] { children ?? [] }
}

struct CaseIdentity: Hashable {
    let row: Int
    let number: Int
}

struct RunContext: Hashable, Comparable {
    let deviceID: String
    let configurationName: String

    static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.deviceID, lhs.configurationName) < (rhs.deviceID, rhs.configurationName)
    }
}

struct TestRun {
    let device: Device
    let configuration: Configuration
    let attempt: Int
    let attemptName: String
    let identity: CaseIdentity?
    let xcodeDisplayName: String?
    let caseURL: String?
    let status: CaseStatus
    let message: String?

    var context: RunContext {
        RunContext(deviceID: device.id, configurationName: configuration.name)
    }
}

extension TestDetails {
    /// Whether the cases of the test take a `TableTestRow`. A test with no case arguments in the
    /// bundle, such as a disabled one, could be a table test.
    var takesTableTestRows: Bool {
        let nodes = testRuns.flatMap(\.descendants)
        return !nodes.contains { $0.kind == .arguments } || nodes.contains { $0.details == TestNode.tableTestRowType }
    }

    func runs() throws -> [TestRun] {
        let defaults = RunPath(
            device: devices.count == 1 ? devices.first : nil,
            configuration: testPlanConfigurations.count == 1 ? testPlanConfigurations.first : nil
        )
        return try testRuns.flatMap { try runs(below: $0, path: defaults) }
    }

    private struct RunPath {
        var device: Device?
        var configuration: Configuration?
        var attempt = 1
        var attemptName = "First Run"
        var identity: CaseIdentity?
        var xcodeDisplayName: String?
    }

    private func runs(below node: TestNode, path: RunPath) throws -> [TestRun] {
        var path = path
        switch node.kind {
        case .device:
            path.device = try dimension(of: node, from: devices)
        case .configuration:
            path.configuration = try dimension(of: node, from: testPlanConfigurations)
        case .arguments:
            path.identity = try caseIdentity(of: node)
            path.xcodeDisplayName = node.name
        case .repetition:
            guard let number = node.nodeIdentifier.flatMap(Int.init), number > 0 else {
                throw ExportError("Xcode did not identify the attempt \(node.name).")
            }
            path.attempt = number
            path.attemptName = node.name
        default:
            break
        }

        let branches = node.directChildren.filter { child in
            child.result != nil && [.device, .configuration, .arguments, .repetition].contains(child.kind)
        }
        if !branches.isEmpty {
            return try branches.flatMap { try runs(below: $0, path: path) }
        }
        guard let status = node.result else { return [] }
        guard let device = path.device, let configuration = path.configuration else {
            throw ExportError("Xcode did not identify the destination and configuration of \(node.name).")
        }
        if path.identity != nil && node.nodeIdentifierURL == nil {
            throw ExportError("Xcode grouped the outcomes for \(node.name) without identifying individual attempts.")
        }

        let diagnostic = node.descendants.first { child in
            child.kind == .skipped || (child.kind == .testRun && child.result == status)
        }
        return [TestRun(
            device: device, configuration: configuration, attempt: path.attempt, attemptName: path.attemptName,
            identity: path.identity, xcodeDisplayName: path.xcodeDisplayName, caseURL: node.nodeIdentifierURL,
            status: path.identity != nil || status == .skipped ? status : .unknown, message: diagnostic?.name
        )]
    }

    private func dimension<Dimension: RunDimension>(of node: TestNode, from entries: [Dimension]) throws -> Dimension {
        let byID = entries.filter { $0.id == node.nodeIdentifier }
        if byID.count == 1 { return byID[0] }
        let byName = entries.filter { $0.name == node.name }
        guard byName.count == 1 else {
            throw ExportError("Could not identify \(node.nodeType) \(node.name).")
        }
        return byName[0]
    }

    private func caseIdentity(of node: TestNode) throws -> CaseIdentity {
        let values = node.directChildren.first { $0.kind == .arguments }?.directChildren ?? []
        guard let row = values.first(where: { $0.details == TestNode.tableTestRowType }) else {
            throw ExportError("Missing reflected TableTestRow for \(node.name).")
        }
        return try CaseIdentity(row: reflectedInt("index", in: row), number: reflectedInt("caseNumber", in: row))
    }

    private func reflectedInt(_ field: String, in row: TestNode) throws -> Int {
        let prefix = "\(field) : "
        let values = row.directChildren.filter { $0.details == "Swift.Int" && $0.name.hasPrefix(prefix) }
        guard values.count == 1, let value = Int(values[0].name.dropFirst(prefix.count)), value > 0 else {
            throw ExportError("Expected one positive reflected \(field) for \(row.name).")
        }
        return value
    }
}
