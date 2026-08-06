import Foundation

enum TestSupport {
    static let repoRoot: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static let configURL: URL = repoRoot
        .appendingPathComponent("Config/config.json")

    // Artifact ids equal binary target names; the release URL and archive
    // filename for each artifact are derived from this single list.
    static let binaryTargetNames: Set<String> = [
        "VulkanLoaderMacOS",
        "VulkanLoaderIOS",
        "KosmicKrisp",
        "MoltenVK",
        "VulkanValidationIOS",
        "VulkanValidationMacOS",
    ]

    static func loadJSON(_ url: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: url)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw TestError("not a JSON object: \(url.path)")
        }
        return dictionary
    }

    static func run(
        _ executable: String,
        _ arguments: [String],
        directory: URL? = nil
    ) throws -> String {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        if let directory {
            process.currentDirectoryURL = directory
        }
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let deadline = Date().addingTimeInterval(120)
        while process.isRunning && Date() < deadline {
            Thread.sleep(forTimeInterval: 0.1)
        }
        if process.isRunning {
            process.terminate()
            throw TestError("process timed out: \(executable) \(arguments)")
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8) ?? ""
    }

}

struct TestError: Error, CustomStringConvertible {
    let description: String

    init(_ description: String) {
        self.description = description
    }
}
