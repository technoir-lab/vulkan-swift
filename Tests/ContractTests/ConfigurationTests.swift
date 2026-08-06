import Foundation
import Testing

@Suite("Configuration")
struct ConfigurationTests {
    private var config: [String: Any] {
        get throws {
            try TestSupport.loadJSON(TestSupport.configURL)
        }
    }

    @Test("central versions")
    func versions() throws {
        let config = try config
        #expect(config["sdkVersion"] as? String == "1.4.357.0")
        #expect(
            config["repository"] as? String
                == "https://github.com/technoir-lab/vulkan-swift"
        )
    }

    @Test("platform matrix drives the package build pipeline")
    func platforms() throws {
        let config = try config
        let platforms = try #require(config["platforms"] as? [String: Any])
        #expect(
            Set(platforms.keys)
                == Set(["macOS", "iOS device", "iOS Simulator"])
        )

        let macOS = try #require(platforms["macOS"] as? [String: Any])
        let iOSDevice = try #require(platforms["iOS device"] as? [String: Any])
        let iOSSimulator = try #require(
            platforms["iOS Simulator"] as? [String: Any]
        )

        #expect(
            Set(macOS.keys) == Set(["deploymentTarget"])
        )
        #expect(macOS["deploymentTarget"] as? String == "26.0")
        #expect(
            iOSDevice["deploymentTarget"] as? String == "26.0"
        )
        #expect(iOSDevice["triple"] as? String == "arm64-apple-ios")
        #expect(iOSDevice["sdk"] as? String == "iphoneos")
        #expect(
            iOSSimulator["deploymentTarget"] as? String == "26.0"
        )
        #expect(
            iOSSimulator["triple"] as? String
                == "arm64-apple-ios-simulator"
        )
        #expect(iOSSimulator["sdk"] as? String == "iphonesimulator")
    }

    @Test("six release artifacts with local paths and URLs")
    func artifacts() throws {
        let config = try config
        let artifacts = try #require(config["artifacts"] as? [[String: Any]])
        #expect(artifacts.count == TestSupport.binaryTargetNames.count)
        #expect(
            Set(artifacts.compactMap { $0["id"] as? String })
                == TestSupport.binaryTargetNames
        )

        let sdkVersion = try #require(config["sdkVersion"] as? String)
        for artifact in artifacts {
            let id = try #require(artifact["id"] as? String)
            let source = try #require(artifact["source"] as? String)
            let local = try #require(artifact["local"] as? String)
            #expect(source.hasPrefix("$SDK_ROOT/"), "\(id) source")
            #expect(local.hasPrefix("Artifacts/"), "\(id) local")
            #expect(!(artifact["licenses"] as? [String] ?? []).isEmpty, "\(id) licenses")

            let archive = "\(id)-\(sdkVersion).zip"
            #expect(archive.hasSuffix(".zip"), "\(id) archive")
        }
    }

    @Test("artifact license payloads")
    func artifactLicenses() throws {
        let config = try config
        let artifacts = try #require(config["artifacts"] as? [[String: Any]])
        func licenses(_ id: String) -> [String] {
            artifacts.first { $0["id"] as? String == id }?["licenses"] as? [String] ?? []
        }
        #expect(licenses("VulkanLoaderMacOS") == ["Vulkan-Loader.txt"])
        #expect(licenses("VulkanLoaderIOS") == ["Vulkan-Loader.txt"])
        #expect(licenses("KosmicKrisp") == ["Mesa-MIT.txt"])
        #expect(licenses("MoltenVK") == ["MoltenVK.txt"])
        #expect(
            licenses("VulkanValidationMacOS")
                == [
                    "Vulkan-ValidationLayers.txt",
                    "Vulkan-ValidationLayers-MIT.txt",
                    "Vulkan-ValidationLayers-BSD-2-Clause.txt",
                ]
        )
        #expect(
            licenses("VulkanValidationIOS")
                == licenses("VulkanValidationMacOS")
        )
    }

}
