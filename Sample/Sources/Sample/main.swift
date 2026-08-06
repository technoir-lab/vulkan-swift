import Darwin
import Foundation
import VolkProbe

func configureVulkanManifestEnvironment() {
    let resourceRoot: URL
#if os(iOS)
    resourceRoot = Bundle.main.bundleURL
#else
    resourceRoot = Bundle.main.resourceURL ?? Bundle.main.bundleURL
#endif

    var icdManifests: [String] = []
    var layerDirectories: [String] = []

    let bundleURLs = (try? FileManager.default.contentsOfDirectory(
        at: resourceRoot,
        includingPropertiesForKeys: nil
    )) ?? []
    for bundleURL in bundleURLs where bundleURL.pathExtension == "bundle" {
        let vulkanRoot = bundleURL.appendingPathComponent("vulkan")

        let icdDirectory = vulkanRoot.appendingPathComponent("icd.d")
        let manifests = (try? FileManager.default.contentsOfDirectory(
            at: icdDirectory,
            includingPropertiesForKeys: nil
        )) ?? []
        for manifest in manifests where manifest.pathExtension == "json" {
            icdManifests.append(manifest.path)
        }

        let layerDirectory = vulkanRoot.appendingPathComponent(
            "explicit_layer.d"
        )
        var isDirectory: ObjCBool = false
        if FileManager.default.fileExists(
            atPath: layerDirectory.path,
            isDirectory: &isDirectory
        ), isDirectory.boolValue {
            layerDirectories.append(layerDirectory.path)
        }
    }

    if !icdManifests.isEmpty {
        let value = icdManifests.joined(separator: ":")
        _ = value.withCString {
            setenv("VK_ICD_FILENAMES", $0, 1)
        }
    }
    if !layerDirectories.isEmpty {
        let value = layerDirectories.joined(separator: ":")
        _ = value.withCString {
            setenv("VK_LAYER_PATH", $0, 1)
        }
    }
}

configureVulkanManifestEnvironment()

let result = vulkan_probe()

func writeSimulatorReport(_ report: String) {
#if os(iOS)
    guard let cacheDirectory = FileManager.default.urls(
        for: .cachesDirectory,
        in: .userDomainMask
    ).first else {
        return
    }
    try? report.write(
        to: cacheDirectory.appendingPathComponent("vulkan-probe.txt"),
        atomically: true,
        encoding: .utf8
    )
#endif
}

if let errorPointer = result.error {
    let error = String(cString: errorPointer)
    if !error.isEmpty {
        let report = "error: \(error)"
        writeSimulatorReport(report)
        fputs("\(report)\n", stderr)
        exit(EXIT_FAILURE)
    }
}

let version = result.vulkanVersion
let major = (version >> 22) & 0x3FF
let minor = (version >> 12) & 0x3FF
let patch = version & 0xFFF

var report = "Vulkan version: \(major).\(minor).\(patch)"
if let driverName = result.driverName {
    report += "\nDriver: \(String(cString: driverName))"
}
report += "\nValidation: \(result.validationEnabled == 1 ? "enabled" : "disabled")"
writeSimulatorReport(report)
print(report)

exit(EXIT_SUCCESS)
