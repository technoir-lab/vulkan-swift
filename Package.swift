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
let packageVersion = "1.0.2"
let sdkVersion = "1.4.363.0"
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
            checksum: "7cff8b34d40733f5fa5f135f1843d5f2598ed398c584c9a138946c584e58a9b5"
        ),
        binaryTarget(
            name: "VulkanLoaderIOS",
            localPath: "VulkanLoader-ios.xcframework",
            checksum: "dcccf64bbf9f12ad6be7b9a164af3e5f7792f634793ce1bbda76ee94832891fa"
        ),
        binaryTarget(
            name: "KosmicKrisp",
            localPath: "KosmicKrisp.xcframework",
            checksum: "3c6796f2b9edb7091c7986349ec84d0e61590cb0afd038278ccd316801291809"
        ),
        binaryTarget(
            name: "MoltenVK",
            localPath: "MoltenVK.xcframework",
            checksum: "8a14d9b134d9a0e35470f81bfa07c3e7640e3058da17562363c99e9f1ea77dfc"
        ),
        binaryTarget(
            name: "VulkanValidationIOS",
            localPath: "VulkanValidation-ios.xcframework",
            checksum: "107d298c5eca37e6e518d6f7ca8569fe58695049ff099fd75d064c7264b2773e"
        ),
        binaryTarget(
            name: "VulkanValidationMacOS",
            localPath: "VulkanValidation-macos.xcframework",
            checksum: "9a9e3274446913d989bcaaf1169ccd69b0ebecbc87938c11eb1413ead42b0e5a"
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
                    name: "MoltenVK",
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
