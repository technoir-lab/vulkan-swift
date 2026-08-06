import Foundation
import Testing

@Suite("Vendor manifest overlays")
struct ManifestTests {
    private func manifest(
        _ target: String,
        _ directory: String,
        named filename: String
    ) throws -> [String: Any] {
        let url = TestSupport.repoRoot
            .appendingPathComponent("Sources/\(target)/\(directory)/\(filename)")
        #expect(FileManager.default.fileExists(atPath: url.path))
        return try TestSupport.loadJSON(url)
    }

    private func libraryPath(
        _ target: String,
        _ directory: String,
        named filename: String
    ) throws -> String {
        let manifest = try manifest(target, directory, named: filename)
        let icd = manifest["ICD"] as? [String: Any]
        let layer = manifest["layer"] as? [String: Any]
        return (icd?["library_path"] ?? layer?["library_path"]) as? String ?? ""
    }

    @Test("macOS KosmicKrisp manifest points into Contents/Frameworks")
    func macosDriverManifest() throws {
        let path = try libraryPath(
            "VulkanDriverMacOSResources",
            "vulkan/icd.d",
            named: "libkosmickrisp_icd.json"
        )
        #expect(
            path
                == "../../../../Frameworks/libvulkan_kosmickrisp.dylib"
        )
    }

    @Test("macOS MoltenVK manifest points into Contents/Frameworks")
    func macosMoltenVKDriverManifest() throws {
        let path = try libraryPath(
            "VulkanDriverMacOSResources",
            "vulkan/icd.d",
            named: "MoltenVK_icd.json"
        )
        #expect(
            path
                == "../../../../Frameworks/MoltenVK.framework/Versions/A/MoltenVK"
        )
    }

    @Test("iOS MoltenVK manifest keeps SDK-relative framework path shape")
    func iosDriverManifest() throws {
        let path = try libraryPath(
            "VulkanDriverIOSResources",
            "vulkan/icd.d",
            named: "MoltenVK_icd.json"
        )
        #expect(
            path == "../../../Frameworks/MoltenVK.framework/MoltenVK"
        )
    }

    @Test("macOS validation manifest points into Contents/Frameworks")
    func macosValidationManifest() throws {
        let manifest = try manifest(
            "VulkanValidationMacOSResources",
            "vulkan/explicit_layer.d",
            named: "VkLayer_khronos_validation.json"
        )
        let layer = try #require(manifest["layer"] as? [String: Any])
        #expect(layer["name"] as? String == "VK_LAYER_KHRONOS_validation")
        #expect(
            layer["library_path"] as? String
                == "../../../../Frameworks/VulkanValidationMacOS.framework/Versions/A/Resources/libVkLayer_khronos_validation.dylib"
        )
    }

    @Test("iOS validation manifest keeps SDK-relative framework path shape")
    func iosValidationManifest() throws {
        let manifest = try manifest(
            "VulkanValidationIOSResources",
            "vulkan/explicit_layer.d",
            named: "VkLayer_khronos_validation.json"
        )
        let layer = try #require(manifest["layer"] as? [String: Any])
        #expect(layer["name"] as? String == "VK_LAYER_KHRONOS_validation")
        #expect(
            layer["library_path"] as? String
                == "../../../Frameworks/VkLayer_khronos_validation.framework/VkLayer_khronos_validation"
        )
    }

    @Test("manifests match vendor JSON except library_path overrides")
    func vendorFidelity() throws {
        let sdkEnv = ProcessInfo.processInfo.environment["VULKAN_SDK"] ?? ""
        guard !sdkEnv.isEmpty else {
            return
        }
        let root: String
        if sdkEnv.hasSuffix("/macOS") {
            root = String(sdkEnv.dropLast("/macOS".count))
        } else {
            root = sdkEnv
        }

        let pairs: [(String, String, String, String)] = [
            (
                "VulkanDriverMacOSResources",
                "vulkan/icd.d",
                "libkosmickrisp_icd.json",
                "\(root)/macOS/share/vulkan/icd.d/libkosmickrisp_icd.json"
            ),
            (
                "VulkanDriverMacOSResources",
                "vulkan/icd.d",
                "MoltenVK_icd.json",
                "\(root)/macOS/share/vulkan/icd.d/MoltenVK_icd.json"
            ),
            (
                "VulkanDriverIOSResources",
                "vulkan/icd.d",
                "MoltenVK_icd.json",
                "\(root)/iOS/share/vulkan/icd.d/MoltenVK_icd.json"
            ),
            (
                "VulkanValidationMacOSResources",
                "vulkan/explicit_layer.d",
                "VkLayer_khronos_validation.json",
                "\(root)/macOS/share/vulkan/explicit_layer.d/VkLayer_khronos_validation.json"
            ),
            (
                "VulkanValidationIOSResources",
                "vulkan/explicit_layer.d",
                "VkLayer_khronos_validation.json",
                "\(root)/iOS/share/vulkan/explicit_layer.d/VkLayer_khronos_validation.json"
            ),
        ]

        for (target, directory, filename, vendorPath) in pairs {
            guard FileManager.default.fileExists(atPath: vendorPath) else {
                continue
            }
            let committed = try manifest(target, directory, named: filename)
            let vendor = try TestSupport.loadJSON(
                URL(fileURLWithPath: vendorPath)
            )
            func canonicalJSON(_ object: [String: Any]) throws -> Data {
                try JSONSerialization.data(
                    withJSONObject: normalized(object),
                    options: [.sortedKeys]
                )
            }
            #expect(
                try canonicalJSON(committed) == canonicalJSON(vendor),
                "\(target) differs from vendor JSON beyond library_path"
            )
        }
    }

    private func normalized(
        _ object: [String: Any]
    ) -> [String: Any] {
        var result = object
        if var icd = result["ICD"] as? [String: Any] {
            icd["library_path"] = nil
            result["ICD"] = icd
        }
        if var layer = result["layer"] as? [String: Any] {
            layer["library_path"] = nil
            result["layer"] = layer
        }
        return result
    }
}

@Suite("Sample contract")
struct SampleContractTests {
    @Test("sample manifest always links both products")
    func sampleManifest() throws {
        let url = TestSupport.repoRoot
            .appendingPathComponent("Sample/Project.swift")
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains(#""VulkanDriver""#))
        #expect(content.contains(#""VulkanValidation""#))

        let packageURL = TestSupport.repoRoot
            .appendingPathComponent("Sample/Package.swift")
        let package = try String(contentsOf: packageURL, encoding: .utf8)
        #expect(package.contains(".package(path: \"..\")"))
    }

    @Test("validation activation is gated to debug builds")
    func validationActivationIsDebugOnly() throws {
        let projectURL = TestSupport.repoRoot
            .appendingPathComponent("Sample/Project.swift")
        let project = try String(contentsOf: projectURL, encoding: .utf8)
        #expect(project.contains("VULKAN_SWIFT_VALIDATION"))
        #expect(project.contains("debug:"))

        let shimURL = TestSupport.repoRoot
            .appendingPathComponent("Sample/Sources/VolkProbe/shim.c")
        let shim = try String(contentsOf: shimURL, encoding: .utf8)
        #expect(shim.contains("#ifdef VULKAN_SWIFT_VALIDATION"))
        #expect(shim.contains("#endif"))
    }

    @Test("shim requests portability on macOS and iOS")
    func shimPortability() throws {
        let url = TestSupport.repoRoot
            .appendingPathComponent("Sample/Sources/VolkProbe/shim.c")
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("TARGET_OS_OSX || TARGET_OS_IPHONE"))
        #expect(
            content.contains("VK_INSTANCE_CREATE_ENUMERATE_PORTABILITY_BIT_KHR")
        )
        #expect(content.contains("VK_KHR_PORTABILITY_ENUMERATION_EXTENSION_NAME"))
    }

    @Test("sample sets Vulkan manifest environment variables")
    func sampleSetsManifestEnvironment() throws {
        let url = TestSupport.repoRoot
            .appendingPathComponent("Sample/Sources/Sample/main.swift")
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("setenv"))
        #expect(content.contains("VK_ICD_FILENAMES"))
        #expect(content.contains("VK_LAYER_PATH"))
        #expect(content.contains(".bundle"))
        #expect(content.contains("joined(separator: \":\")"))
    }

    @Test("sample compiles Volk from the Vulkan SDK")
    func sampleUsesSdkVolk() throws {
        let url = TestSupport.repoRoot
            .appendingPathComponent("Scripts/check-sample.sh")
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content.contains("include/volk/volk.c"))
        #expect(content.contains("include/volk/volk.h"))
    }
}
