# vulkan-swift

SwiftPM package that transports the Vulkan loader, the KosmicKrisp and
MoltenVK drivers, optional validation layers, and their loader manifests.

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

- macOS: `libvulkan.1.dylib`, `libvulkan_kosmickrisp.dylib`, and
  `MoltenVK.framework` land in `Contents/Frameworks`; the KosmicKrisp and
  MoltenVK ICD manifests are in
  `<Pkg>_VulkanDriverMacOSResources.bundle/vulkan/icd.d/`.
- iOS: `vulkan.xcframework` + `MoltenVK.xcframework` land in `Frameworks/`;
  the MoltenVK ICD manifest is in
  `<Pkg>_VulkanDriverIOSResources.bundle/vulkan/icd.d/`.
- Validation: macOS ships a `VulkanValidationMacOS.framework` wrapper whose
  resources contain `libVkLayer_khronos_validation.dylib`; iOS ships
  `VkLayer_khronos_validation.xcframework`. The platform layer manifest is in
  `vulkan/explicit_layer.d/` inside the validation resource bundle.
