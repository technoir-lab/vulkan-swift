import Foundation
import Testing

@Suite("Release artifacts")
struct ArtifactTests {
    private var config: [String: Any] {
        get throws {
            try TestSupport.loadJSON(TestSupport.configURL)
        }
    }

    private var artifacts: [[String: Any]] {
        get throws {
            try #require(config["artifacts"] as? [[String: Any]])
        }
    }

    private func archiveName(for id: String) throws -> String {
        let sdkVersion = try #require(config["sdkVersion"] as? String)
        return "\(id)-\(sdkVersion).zip"
    }

    private func extract(_ archive: URL, to directory: URL) throws {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        _ = try TestSupport.run(
            "/usr/bin/ditto",
            ["-x", "-k", archive.path, directory.path]
        )
    }

    private func contents(of root: URL) -> [String] {
        let resolved = root.resolvingSymlinksInPath()
        let enumerator = FileManager.default.enumerator(
            at: resolved,
            includingPropertiesForKeys: nil
        )!
        var result: [String] = []
        for case let url as URL in enumerator {
            let marker = "/\(resolved.lastPathComponent)/"
            guard let range = url.path.range(of: marker) else {
                continue
            }
            result.append(
                String(url.path[range.upperBound...])
            )
        }
        return result.sorted()
    }

    @Test("recreated archives contain the same entries")
    func recreatedArchiveContents() throws {
        let artifacts = try artifacts
        for artifact in artifacts {
            let id = try #require(artifact["id"] as? String)
            let local = try #require(artifact["local"] as? String)
            let licenses = try #require(artifact["licenses"] as? [String])
            let archiveName = try archiveName(for: id)

            let localURL = TestSupport.repoRoot.appendingPathComponent(local)
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            defer {
                try? FileManager.default.removeItem(at: tempDir)
            }
            try FileManager.default.createDirectory(
                at: tempDir,
                withIntermediateDirectories: true
            )
            let output = tempDir.appendingPathComponent("re.zip")

            var arguments = [
                TestSupport.repoRoot
                    .appendingPathComponent("Scripts/deterministic-zip.py")
                    .path,
                output.path,
                localURL.path,
                localURL.lastPathComponent,
            ]
            for license in licenses {
                arguments.append(
                    TestSupport.repoRoot
                        .appendingPathComponent("Licenses/\(license)")
                        .path
                )
                arguments.append("Licenses/\(license)")
            }
            _ = try TestSupport.run("/usr/bin/python3", arguments)
            let archive = TestSupport.repoRoot
                .appendingPathComponent("Dist/\(archiveName)")
            let recreated = tempDir.appendingPathComponent("recreated")
            let archived = tempDir.appendingPathComponent("archived")
            try extract(output, to: recreated)
            try extract(archive, to: archived)
            #expect(
                contents(of: recreated) == contents(of: archived),
                "\(archiveName)"
            )
        }
    }

    @Test("archives contain exactly the XCFramework and its licenses")
    func archiveContents() throws {
        let artifacts = try artifacts
        for artifact in artifacts {
            let id = try #require(artifact["id"] as? String)
            let archiveName = try archiveName(for: id)
            let local = try #require(artifact["local"] as? String)
            let licenses = try #require(artifact["licenses"] as? [String])

            let archive = TestSupport.repoRoot
                .appendingPathComponent("Dist/\(archiveName)")
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            defer {
                try? FileManager.default.removeItem(at: tempDir)
            }
            try extract(archive, to: tempDir)

            let entries = try FileManager.default.contentsOfDirectory(
                at: tempDir,
                includingPropertiesForKeys: nil
            )
            #expect(entries.count == 2, "\(id)")
            let frameworkName = URL(fileURLWithPath: local).lastPathComponent
            #expect(
                entries.contains {
                    $0.lastPathComponent == frameworkName
                },
                "\(id)"
            )
            let licenseDir = entries.first {
                $0.lastPathComponent == "Licenses"
            }
            #expect(licenseDir != nil, "\(id)")

            let licenseFiles = try FileManager.default
                .contentsOfDirectory(
                    at: licenseDir!,
                    includingPropertiesForKeys: nil
                )
            #expect(
                licenseFiles.map { $0.lastPathComponent }.sorted()
                    == licenses.sorted(),
                "\(id)"
            )
        }
    }

    @Test("vendor XCFrameworks retain their contents list")
    func vendorXCFrameworkContents() throws {
        let artifacts = try artifacts
        for artifact in artifacts
        where artifact["kind"] as? String == "vendor-xcframework" {
            let id = try #require(artifact["id"] as? String)
            let archiveName = try archiveName(for: id)
            let local = try #require(artifact["local"] as? String)

            let archive = TestSupport.repoRoot
                .appendingPathComponent("Dist/\(archiveName)")
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            defer {
                try? FileManager.default.removeItem(at: tempDir)
            }
            try extract(archive, to: tempDir)

            let extracted = tempDir
                .appendingPathComponent(
                    URL(fileURLWithPath: local).lastPathComponent
                )
            let staged = TestSupport.repoRoot
                .appendingPathComponent(local)
            #expect(
                contents(of: extracted) == contents(of: staged),
                "\(id)"
            )
        }
    }

    @Test("wrapped macOS payloads contain a dylib")
    func wrappedPayloadContents() throws {
        let artifacts = try artifacts
        for artifact in artifacts
        where ["wrapped-dylib", "wrapped-bundle"].contains(
            artifact["kind"] as? String
        ) {
            let id = try #require(artifact["id"] as? String)
            let archiveName = try archiveName(for: id)
            let local = try #require(artifact["local"] as? String)

            let archive = TestSupport.repoRoot
                .appendingPathComponent("Dist/\(archiveName)")
            let tempDir = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
            defer {
                try? FileManager.default.removeItem(at: tempDir)
            }
            try extract(archive, to: tempDir)

            let extractedRoot = tempDir
                .appendingPathComponent(
                    URL(fileURLWithPath: local).lastPathComponent
                )
            #expect(
                contents(of: extractedRoot).contains {
                    URL(fileURLWithPath: $0).pathExtension == "dylib"
                },
                "\(id)"
            )
        }
    }
}
