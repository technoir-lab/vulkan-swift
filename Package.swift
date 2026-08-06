// swift-tools-version: 6.3

import Foundation
import PackageDescription

// Binary targets resolve either to the locally staged XCFrameworks or to the
// released binary URLs below. Local mode is activated ONLY by
// VULKAN_SWIFT_ARTIFACTS (the Makefile exports it as "Artifacts"): the value
// is used directly as a package-root-relative path, so it must point inside
// the package — absolute/outside-package paths are not supported. Unset,
// empty, or "off" selects the remote URLs and checksums.
func localArtifactsDirectory() -> String? {
    guard let env = ProcessInfo.processInfo.environment["VULKAN_SWIFT_ARTIFACTS"],
        !env.isEmpty, env != "off"
    else { return nil }
    var dir = env
    while dir.hasSuffix("/") { dir.removeLast() }
    return dir
}

let artifactsDirectory = localArtifactsDirectory()

// SwiftPM package version, kept in sync with the release git tag by
// Scripts/release.sh. sdkVersion mirrors the SDK version from the central
// configuration so both values appear exactly once per binary URL.
let packageVersion = "1.0.0"
let sdkVersion = "1.4.357.0"
let repository = "https://github.com/technoir-lab/vulkan-swift"

func binaryTarget(
    name: String,
    localPath: String,
    checksum: String
) -> Target {
    let url = "\(repository)/releases/download/\(packageVersion)/\(name)-\(sdkVersion).zip"
    if let dir = artifactsDirectory {
        return .binaryTarget(name: name, path: "\(dir)/\(localPath)")
    }
    return .binaryTarget(name: name, url: url, checksum: checksum)
}

let package = Package(
    name: "vulkan-swift",
    platforms: [
        .macOS("26.0"),
        .iOS("26.0"),
    ],
    products: [
        .library(
            name: "VulkanDriver",
            type: .static,
            targets: ["VulkanDriver"]
        ),
        .library(
            name: "VulkanValidation",
            type: .static,
            targets: ["VulkanValidation"]
        ),
    ],
    targets: [
        binaryTarget(
            name: "VulkanLoaderMacOS",
            localPath: "VulkanLoader-macos.xcframework",
            checksum: "88e4811c084cfd549ea861fd8d3e41bc5c0160a81114c76bd7a954b9ad9b36e2"
        ),
        binaryTarget(
            name: "VulkanLoaderIOS",
            localPath: "VulkanLoader-ios.xcframework",
            checksum: "6ccf33aec00e058c73c41c76f75c33c94161814d97c23826eaa24ce42ff46ff6"
        ),
        binaryTarget(
            name: "KosmicKrisp",
            localPath: "KosmicKrisp.xcframework",
            checksum: "82c9b1a91458fdb7fe1b374cdba7bf39a57bf1bd52d40e010ac7d2bcdf6b9ca0"
        ),
        binaryTarget(
            name: "MoltenVK",
            localPath: "MoltenVK.xcframework",
            checksum: "d8c189a57c194c1b56e9e84b6c0528cbed8cbf7214c886afeb7f183314daf116"
        ),
        binaryTarget(
            name: "VulkanValidationIOS",
            localPath: "VulkanValidation-ios.xcframework",
            checksum: "c2477359470684616d6b919713e264f4cc96a6d28cfb66ed6afcad470e54c650"
        ),
        binaryTarget(
            name: "VulkanValidationMacOS",
            localPath: "VulkanValidation-macos.xcframework",
            checksum: "d0a33b15f0d0b815018236fbd8ab55b8455e187a8017cbccd89f4befcece7a4e"
        ),
        .target(
            name: "VulkanDriverMacOSResources",
            sources: ["Empty.swift"],
            resources: [.copy("vulkan")]
        ),
        .target(
            name: "VulkanDriverIOSResources",
            sources: ["Empty.swift"],
            resources: [.copy("vulkan")]
        ),
        .target(
            name: "VulkanValidationMacOSResources",
            sources: ["Empty.swift"],
            resources: [.copy("vulkan")]
        ),
        .target(
            name: "VulkanValidationIOSResources",
            sources: ["Empty.swift"],
            resources: [.copy("vulkan")]
        ),
        .target(
            name: "VulkanDriver",
            dependencies: [
                .target(
                    name: "VulkanLoaderMacOS",
                    condition: .when(platforms: [.macOS])
                ),
                .target(
                    name: "MoltenVK",
                    condition: .when(platforms: [.macOS, .iOS])
                ),
                .target(
                    name: "KosmicKrisp",
                    condition: .when(platforms: [.macOS])
                ),
                .target(
                    name: "VulkanDriverMacOSResources",
                    condition: .when(platforms: [.macOS])
                ),
                .target(
                    name: "VulkanLoaderIOS",
                    condition: .when(platforms: [.iOS])
                ),
                .target(
                    name: "VulkanDriverIOSResources",
                    condition: .when(platforms: [.iOS])
                ),
            ],
            sources: ["Empty.swift"]
        ),
        .target(
            name: "VulkanValidation",
            dependencies: [
                .target(
                    name: "VulkanValidationMacOS",
                    condition: .when(platforms: [.macOS])
                ),
                .target(
                    name: "VulkanValidationMacOSResources",
                    condition: .when(platforms: [.macOS])
                ),
                .target(
                    name: "VulkanValidationIOS",
                    condition: .when(platforms: [.iOS])
                ),
                .target(
                    name: "VulkanValidationIOSResources",
                    condition: .when(platforms: [.iOS])
                ),
            ],
            sources: ["Empty.swift"]
        ),
        .testTarget(
            name: "ContractTests",
            dependencies: []
        ),
    ]
)
