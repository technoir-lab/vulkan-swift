import ProjectDescription
import Foundation

// Tuist manifest for the sample app. `tuist generate` produces the git-ignored
// Sample.xcodeproj / Sample.xcworkspace; the sample links the parent
// vulkan-swift SwiftPM package through Tuist's XcodeProj-based integration
// (dependencies declared in Sample/Package.swift, consumed via .external).

struct SampleConfiguration: Decodable {
    struct Platform: Decodable {
        let deploymentTarget: String
    }

    let platforms: [String: Platform]

    var macOSDeploymentTarget: String {
        deploymentTarget(for: "macOS")
    }

    var iOSDeploymentTarget: String {
        deploymentTarget(for: "iOS device")
    }

    private func deploymentTarget(for key: String) -> String {
        guard let platform = platforms[key] else {
            fatalError(
                "config.json: platform '\(key)' is missing; found: "
                    + platforms.keys.sorted().joined(separator: ", ")
            )
        }
        return platform.deploymentTarget
    }
}

let configURL = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .deletingLastPathComponent()
    .appendingPathComponent("Config/config.json")
let configuration = try JSONDecoder().decode(
    SampleConfiguration.self,
    from: Data(contentsOf: configURL)
)

// Tuist only forwards TUIST_-prefixed variables to manifest evaluation.
let sdkEnv = ProcessInfo.processInfo.environment["TUIST_VULKAN_SDK"]
    ?? ProcessInfo.processInfo.environment["VULKAN_SDK"]
    ?? ""
guard !sdkEnv.isEmpty else {
    fatalError(
        "TUIST_VULKAN_SDK (or VULKAN_SDK) must be set to generate "
            + "the sample project"
    )
}

let sdkRoot: String
if sdkEnv.hasSuffix("/macOS") {
    sdkRoot = String(sdkEnv.dropLast("/macOS".count))
} else {
    sdkRoot = sdkEnv
}

let sdkMacOSInclude = FileManager.default.fileExists(
    atPath: sdkRoot + "/macOS/include"
) ? sdkRoot + "/macOS/include" : sdkRoot + "/include"
let sdkIOSInclude = FileManager.default.fileExists(
    atPath: sdkRoot + "/iOS/include"
) ? sdkRoot + "/iOS/include" : sdkRoot + "/include"

func volkProbeTarget(
    name: String,
    destinations: Destinations,
    include: String,
    deploymentTargets: DeploymentTargets
) -> Target {
    .target(
        name: name,
        destinations: destinations,
        product: .staticLibrary,
        bundleId: "io.technoirlab.\(name)",
        deploymentTargets: deploymentTargets,
        sources: ["Sources/VolkProbe/**"],
        headers: .headers(
            public: ["Sources/VolkProbe/include/**"]
        ),
        settings: .settings(
            base: [
                "CLANG_C_LANGUAGE_STANDARD": "c17",
                "GCC_PRECOMPILE_PREFIX_HEADER": "NO",
                "HEADER_SEARCH_PATHS": [
                    include,
                    "$(SRCROOT)/Sources/VolkProbe/include",
                ],
            ],
            debug: [
                "GCC_PREPROCESSOR_DEFINITIONS": [
                    "$(inherited)",
                    "VULKAN_SWIFT_VALIDATION=1",
                ],
            ]
        )
    )
}

func appTarget(
    name: String,
    destinations: Destinations,
    deploymentTarget: DeploymentTargets,
    infoPlist: InfoPlist,
    runpath: String,
    dependencies: [TargetDependency]
) -> Target {
    .target(
        name: name,
        destinations: destinations,
        product: .app,
        bundleId: "io.technoirlab.vulkan-swift-sample",
        deploymentTargets: deploymentTarget,
        infoPlist: infoPlist,
        sources: ["Sources/Sample/**"],
        scripts: [
            .post(
                script: """
                    resources_dir="${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}"
                    for bundle in "${resources_dir}"/*.bundle; do
                        [ -d "$bundle" ] || continue
                        nested="$bundle/Contents/Resources"
                        if [ -d "$nested" ]; then
                            ditto "$nested" "$bundle"
                            rm -rf "$bundle/Contents"
                        fi
                    done
                    """,
                name: "Flatten Vulkan resource bundles",
                basedOnDependencyAnalysis: false
            ),
        ],
        dependencies: dependencies,
        settings: .settings(
            base: [
                "PRODUCT_NAME": "VulkanSwiftSample",
                "LD_RUNPATH_SEARCH_PATHS": [
                    "$(inherited)",
                    runpath,
                ],
                "CODE_SIGN_STYLE": "Manual",
                "CODE_SIGN_IDENTITY": "-",
                "SWIFT_INCLUDE_PATHS": [
                    "$(inherited)",
                    "$(SRCROOT)/Sources/VolkProbe/Modules",
                ],
            ]
        )
    )
}

let project = Project(
    name: "Sample",
    targets: [
        volkProbeTarget(
            name: "VolkProbeMacOS",
            destinations: .macOS,
            include: sdkMacOSInclude,
            deploymentTargets: .macOS(configuration.macOSDeploymentTarget)
        ),
        volkProbeTarget(
            name: "VolkProbeIOS",
            destinations: .iOS,
            include: sdkIOSInclude,
            deploymentTargets: .iOS(configuration.iOSDeploymentTarget)
        ),
        appTarget(
            name: "SampleMacOS",
            destinations: .macOS,
            deploymentTarget: .macOS(configuration.macOSDeploymentTarget),
            infoPlist: .default,
            runpath: "@executable_path/../Frameworks",
            dependencies: [
                .target(name: "VolkProbeMacOS"),
                .external(name: "VulkanDriver"),
                .external(name: "VulkanValidation"),
            ]
        ),
        appTarget(
            name: "SampleIOS",
            destinations: .iOS,
            deploymentTarget: .iOS(configuration.iOSDeploymentTarget),
            infoPlist: .extendingDefault(with: [
                "UILaunchScreen": [:],
            ]),
            runpath: "@executable_path/Frameworks",
            dependencies: [
                .target(name: "VolkProbeIOS"),
                .external(name: "VulkanDriver"),
                .external(name: "VulkanValidation"),
            ]
        ),
    ]
)
