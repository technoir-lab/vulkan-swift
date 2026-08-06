import Foundation
import ProjectDescription

struct WrapperConfiguration: Decodable {
    struct Platform: Decodable {
        let deploymentTarget: String
    }

    let sdkVersion: String
    let platforms: [String: Platform]

    var macOSDeploymentTarget: String {
        guard let platform = platforms["macOS"] else {
            fatalError("config.json: macOS platform is missing")
        }
        return platform.deploymentTarget
    }
}

let configURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Config/config.json")
let configuration = try JSONDecoder().decode(
    WrapperConfiguration.self,
    from: Data(contentsOf: configURL)
)

let project = Project(
    name: "ValidationWrapper",
    targets: [
        .target(
            name: "VulkanValidationMacOS",
            destinations: .macOS,
            product: .framework,
            bundleId: "io.technoirlab.vulkan-swift.validation",
            deploymentTargets: .macOS(configuration.macOSDeploymentTarget),
            infoPlist: .file(path: "Info.plist"),
            sources: ["Sources/**"],
            resources: [
                .glob(pattern: "Resources/libVkLayer_khronos_validation.dylib"),
            ],
            settings: .settings(
                base: [
                    "ARCHS": "arm64 x86_64",
                    "BUILD_LIBRARY_FOR_DISTRIBUTION": "YES",
                    "CODE_SIGNING_ALLOWED": "NO",
                    "DEFINES_MODULE": "NO",
                    "SKIP_INSTALL": "NO",
                    "VULKAN_SWIFT_SDK_VERSION": .string(configuration.sdkVersion),
                ],
                release: [
                    "GCC_GENERATE_DEBUGGING_SYMBOLS": "NO",
                    "OTHER_LDFLAGS": [
                        "$(inherited)",
                        "-Wl,-S",
                        "-Wl,-x",
                    ],
                ]
            )
        ),
    ]
)
