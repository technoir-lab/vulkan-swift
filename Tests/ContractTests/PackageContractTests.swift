import Foundation
import Testing

@Suite("Package contract")
struct PackageContractTests {
    private func dumpPackage(
        manifestName: String = "package-manifest.json"
    ) throws -> [String: Any] {
        let manifestURL = TestSupport.repoRoot
            .appendingPathComponent("Build/\(manifestName)")
        guard FileManager.default.fileExists(atPath: manifestURL.path) else {
            throw TestError(
                "Build/\(manifestName) missing; run: "
                    + "make test"
            )
        }
        let data = try Data(contentsOf: manifestURL)
        let object = try JSONSerialization.jsonObject(with: data)
        guard let dictionary = object as? [String: Any] else {
            throw TestError("dump-package produced no JSON")
        }
        return dictionary
    }

    @Test("products are static and declaration-free")
    func products() throws {
        let manifest = try dumpPackage()
        #expect(manifest["name"] as? String == "vulkan-swift")

        let products = manifest["products"] as? [[String: Any]] ?? []
        #expect(products.count == 2)
        let driver = try #require(
            products.first { $0["name"] as? String == "VulkanDriver" }
        )
        let validation = try #require(
            products.first { $0["name"] as? String == "VulkanValidation" }
        )
        #expect((driver["type"] as? [String: Any])?["library"] as? [String] == ["static"])
        #expect((validation["type"] as? [String: Any])?["library"] as? [String] == ["static"])
        #expect(driver["targets"] as? [String] == ["VulkanDriver"])
        #expect(validation["targets"] as? [String] == ["VulkanValidation"])
    }

    @Test("driver target selects the platform loader and ICD")
    func driverDependencies() throws {
        let manifest = try dumpPackage()
        let targets = manifest["targets"] as? [[String: Any]] ?? []
        let driver = try #require(
            targets.first { $0["name"] as? String == "VulkanDriver" }
        )
        let dependencies = driver["dependencies"] as? [[String: Any]] ?? []

        func dependsOn(_ name: String, platform: String) -> Bool {
            dependencies.contains { entry in
                guard let pair = entry["target"] as? [Any],
                      let dependencyName = pair.first as? String,
                      let condition = pair.last as? [String: Any] else {
                    return false
                }
                return dependencyName == name
                    && (condition["platformNames"] as? [String])?.contains(platform) == true
            }
        }

        #expect(dependsOn("VulkanLoaderMacOS", platform: "macos"))
        #expect(dependsOn("MoltenVK", platform: "macos"))
        #expect(dependsOn("KosmicKrisp", platform: "macos"))
        #expect(dependsOn("VulkanDriverMacOSResources", platform: "macos"))
        #expect(dependsOn("VulkanLoaderIOS", platform: "ios"))
        #expect(dependsOn("MoltenVK", platform: "ios"))
        #expect(dependsOn("VulkanDriverIOSResources", platform: "ios"))
        #expect(!dependsOn("KosmicKrisp", platform: "ios"))
    }

    @Test("validation target selects the platform validation layer")
    func validationDependencies() throws {
        let manifest = try dumpPackage()
        let targets = manifest["targets"] as? [[String: Any]] ?? []
        let validation = try #require(
            targets.first { $0["name"] as? String == "VulkanValidation" }
        )
        let dependencies = validation["dependencies"] as? [[String: Any]] ?? []

        func dependsOn(_ name: String, platform: String) -> Bool {
            dependencies.contains { entry in
                guard let pair = entry["target"] as? [Any],
                      let dependencyName = pair.first as? String,
                      let condition = pair.last as? [String: Any] else {
                    return false
                }
                return dependencyName == name
                    && (condition["platformNames"] as? [String]) == [platform]
            }
        }

        #expect(dependsOn("VulkanValidationMacOS", platform: "macos"))
        #expect(dependsOn("VulkanValidationMacOSResources", platform: "macos"))
        #expect(dependsOn("VulkanValidationIOS", platform: "ios"))
        #expect(dependsOn("VulkanValidationIOSResources", platform: "ios"))
    }

    @Test("all six binary targets are declared")
    func binaryTargets() throws {
        let manifest = try dumpPackage()
        let targets = manifest["targets"] as? [[String: Any]] ?? []
        let binaryNames = targets
            .filter { $0["type"] as? String == "binary" }
            .compactMap { $0["name"] as? String }
            .sorted()
        #expect(binaryNames == TestSupport.binaryTargetNames.sorted())
    }

    @Test("binary targets resolve to staged artifacts when VULKAN_SWIFT_ARTIFACTS is set")
    func localArtifactMode() throws {
        let manifest = try dumpPackage()
        let targets = manifest["targets"] as? [[String: Any]] ?? []
        let binaryTargets = targets.filter { $0["type"] as? String == "binary" }

        let config = try TestSupport.loadJSON(TestSupport.configURL)
        let artifacts = try #require(config["artifacts"] as? [[String: Any]])
        let expected: [String: String] = try Dictionary(
            uniqueKeysWithValues: TestSupport.binaryTargetNames.map { name in
                let local = try #require(
                    artifacts.first { $0["id"] as? String == name }?["local"] as? String
                )
                let basename = String(local.split(separator: "/").last ?? "")
                return (name, basename)
            }
        )

        #expect(binaryTargets.count == TestSupport.binaryTargetNames.count)
        for target in binaryTargets {
            let name = try #require(target["name"] as? String)
            let expectedBasename = try #require(expected[name])
            let path = try #require(target["path"] as? String, "\(name) should resolve locally")
            #expect(target["url"] == nil, "\(name) should not carry a remote URL")
            #expect(
                String(path.split(separator: "/").last ?? "") == expectedBasename,
                "\(name) staged path mismatch"
            )
        }
    }

    @Test("binary targets resolve to remote URLs when VULKAN_SWIFT_ARTIFACTS is off")
    func remoteArtifactMode() throws {
        let manifest = try dumpPackage(
            manifestName: "package-manifest-remote.json"
        )
        let targets = manifest["targets"] as? [[String: Any]] ?? []
        let binaryTargets = targets.filter { $0["type"] as? String == "binary" }

        let config = try TestSupport.loadJSON(TestSupport.configURL)
        let sdkVersion = try #require(config["sdkVersion"] as? String)
        let repository = try #require(config["repository"] as? String)
        let packageVersion = try packageVersionFromManifestSource()
        let manifestSdkVersion = try sdkVersionFromManifestSource()

        #expect(
            manifestSdkVersion == sdkVersion,
            "Package.swift sdkVersion must mirror the configuration"
        )

        #expect(binaryTargets.count == TestSupport.binaryTargetNames.count)
        for target in binaryTargets {
            let name = try #require(target["name"] as? String)
            let id = name
            let checksum = try #require(target["checksum"] as? String)
            let url = try #require(target["url"] as? String, "\(name) should resolve remotely")
            #expect(target["path"] == nil, "\(name) should not resolve locally")
            #expect(
                url
                    == "\(repository)/releases/download/\(packageVersion)/\(id)-\(sdkVersion).zip"
            )
            #expect(
                checksum.wholeMatch(of: /^[0-9a-f]{64}$/) != nil,
                "\(name) checksum"
            )
            let archive = TestSupport.repoRoot
                .appendingPathComponent("Dist/\(id)-\(sdkVersion).zip")
            #expect(
                FileManager.default.fileExists(atPath: archive.path),
                "\(id) archive missing"
            )
            let calculatedChecksum = try TestSupport.run(
                "/usr/bin/env",
                ["swift", "package", "compute-checksum", archive.path]
            ).trimmingCharacters(in: .whitespacesAndNewlines)
            #expect(checksum == calculatedChecksum, "\(id) checksum mismatch")
        }
    }

    private func manifestConstant(named name: String) throws -> String {
        let manifestURL = TestSupport.repoRoot
            .appendingPathComponent("Package.swift")
        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        guard let line = manifest
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("let \(name) = ") })
        else {
            throw TestError("\(name) missing from Package.swift")
        }
        let prefix = "let \(name) = \""
        guard line.hasPrefix(prefix), line.hasSuffix("\"") else {
            throw TestError("\(name) declaration malformed")
        }
        return String(line.dropFirst(prefix.count).dropLast())
    }

    private func packageVersionFromManifestSource() throws -> String {
        let value = try manifestConstant(named: "packageVersion")
        guard value.wholeMatch(of: /^[0-9]+\.[0-9]+\.[0-9]+$/) != nil else {
            throw TestError("packageVersion \(value) is not bare semver")
        }
        return value
    }

    private func sdkVersionFromManifestSource() throws -> String {
        let value = try manifestConstant(named: "sdkVersion")
        guard !value.isEmpty else {
            throw TestError("sdkVersion is empty")
        }
        return value
    }

    @Test("binary target URLs match the configuration")
    func binaryTargetsMatchConfiguration() throws {
        let manifestURL = TestSupport.repoRoot
            .appendingPathComponent("Package.swift")
        let manifest = try String(contentsOf: manifestURL, encoding: .utf8)
        #expect(
            !manifest.contains("Config/config.json"),
            "Package.swift must stay registry-safe and self-contained"
        )

        let config = try TestSupport.loadJSON(TestSupport.configURL)
        let artifacts = try #require(config["artifacts"] as? [[String: Any]])
        let configSdkVersion = try #require(config["sdkVersion"] as? String)
        _ = try packageVersionFromManifestSource()
        let sdkVersion = try sdkVersionFromManifestSource()
        #expect(
            sdkVersion == configSdkVersion,
            "Package.swift sdkVersion must mirror the configuration"
        )
        #expect(artifacts.count == TestSupport.binaryTargetNames.count)
        #expect(
            Set(artifacts.compactMap { $0["id"] as? String })
                == TestSupport.binaryTargetNames,
            "config artifact ids must match the binary target names"
        )
        let urlTemplate = #""\(repository)/releases/download/\(packageVersion)/\(name)-\(sdkVersion).zip""#
        #expect(
            manifest.contains(urlTemplate),
            "binaryTarget helper must build URLs from name, packageVersion, and sdkVersion"
        )
    }
}
