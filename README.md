# vulkan-swift

SwiftPM package that transports the Vulkan loader, KosmicKrisp on macOS,
MoltenVK on iOS, optional validation layers, and their loader manifests.

## Usage

Add the package to your SwiftPM dependencies, substituting the latest release
version for `<version>`:

```swift
.package(url: "https://github.com/technoir-lab/vulkan-swift", from: "<version>")
```

Then depend on the `VulkanDriver` product, and on `VulkanValidation` when you
want the validation layer.

Set `VK_ICD_FILENAMES` (colon-separated ICD manifest files) and `VK_LAYER_PATH` (colon-separated layer
directories) before Vulkan initialization so the loader finds the manifests
embedded in the resource bundles.

## Products

- `VulkanDriver` — static, declaration-free product. Links the platform Vulkan
  loader and ICD, and embeds the ICD manifest resource bundle.
- `VulkanValidation` — static, declaration-free product. Links the platform
  validation artifact and embeds its manifest resource bundle.

Packaging:

- macOS: `vulkan.framework` and `KosmicKrisp.framework` land in
  `Contents/Frameworks`; the KosmicKrisp ICD manifest is in
  `Contents/Resources/<Pkg>_VulkanDriverMacOSResources.bundle/Contents/Resources/vulkan/icd.d/`.
- iOS: `vulkan.xcframework` + `MoltenVK.xcframework` land in `Frameworks/`;
  the MoltenVK ICD manifest is in
  `<Pkg>_VulkanDriverIOSResources.bundle/vulkan/icd.d/`.
- Validation: macOS ships a `VulkanValidationMacOS.framework` wrapper whose
  resources contain `libVkLayer_khronos_validation.dylib`; iOS ships
  `VkLayer_khronos_validation.xcframework`. The platform layer manifest is in
  `vulkan/explicit_layer.d/` inside the validation resource bundle.

Manifest library paths target the standard Xcode app layout. Preserve the
resource bundles as built, and use `Bundle(url:)?.resourceURL` to locate their
contents: macOS bundles have a nested `Contents/Resources` directory, while iOS
bundles keep resources at their root. No manifest rewriting or bundle flattening
is needed for this layout. Consumers that arrange libraries and resources
differently must provide matching manifest paths.

KosmicKrisp uses Metal 4 on macOS 26 or later and supports Vulkan 1.4.
`make check-sample` requests Vulkan 1.4 and verifies the loader and physical
device API versions with KosmicKrisp on macOS and MoltenVK on the iOS
Simulator, with validation enabled.

GitHub-hosted macOS runners expose a virtual GPU without Metal 4 support.
CI and release workflows set `VULKAN_SWIFT_SAMPLE_SKIP_KOSMICKRISP=1` to
skip that driver's runtime probe while retaining all sample builds, bundle
checks, and the iOS Simulator runtime probe. Run `make check-sample` locally on a
Metal 4-capable Mac to exercise KosmicKrisp; the default runs every probe.

Staging preserves SDK payloads, then adds deterministic ad-hoc signatures to
unsigned runtime Mach-O binaries and frameworks across all shipped Apple
platform slices. Nested code is signed before its enclosing framework; outer
XCFramework containers, static libraries, object files, and data are not signed.
Existing signatures are never replaced, even when invalid or present on only
one architecture. Signed enclosing bundles are left entirely unchanged to
preserve their resource seals. Only newly signed executables and new framework
resource seals may differ from the staged copies. Signing uses no timestamp
service; release checksums cover the resulting signed artifacts. Device apps
still need their normal application signing when embedding these frameworks.

`make test-signing` exercises signature preservation, nested/versioned
frameworks, runtime-only selection, and repeatable signing using local compiler
fixtures. It is also included in `make test`.
