// swift-tools-version: 6.3

// Tuist dependency manifest for the sample. The sample consumes the parent
// vulkan-swift package through Tuist's XcodeProj-based integration; the
// Tuist project itself is described in Project.swift.

import PackageDescription

let package = Package(
    name: "SampleDependencies",
    dependencies: [
        .package(path: ".."),
    ]
)
