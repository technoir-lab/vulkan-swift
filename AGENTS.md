# AGENTS.md

SwiftPM package that ships the Vulkan loader, KosmicKrisp/MoltenVK drivers, and validation layers as binary artifacts. It declares **no API** — targets are `Empty.swift` placeholders; the real content is `Config/config.json`, `Scripts/`, and `Tests/`. See `Makefile`, `.github/workflows/ci.yaml`, and `.github/workflows/release.yaml` for the full pipeline.

## Prerequisites

- macOS 26+, Xcode 26+ with a Swift 6.3+ toolchain, Python 3, Tuist (`brew install --cask tuist`), jq (`brew install jq`; preinstalled on CI runners).
- Vulkan SDK at `$VULKAN_SDK` matching `Config/config.json` `sdkVersion` (`1.4.357.0`), with the Volk, iOS, and Kosmic components (`com.lunarg.vulkan.volk`, `com.lunarg.vulkan.ios`, `com.lunarg.vulkan.kosmic`, as installed by CI). The variable points at the SDK root or its `.../macOS` platform tree; scripts normalize via `sdk_root()`. Artifact sources use both `$SDK_ROOT/macOS` and `$SDK_ROOT/iOS`.
- Nothing is vendored: `Artifacts/`, `Build/`, `Dist/`, `Derived/`, and all xcodeproj/workspace files are generated and gitignored.

## Commands (all through the Makefile)

- `make artifacts` — stage SDK binaries into `Artifacts/` (vendor XCFrameworks copied; macOS loader/KosmicKrisp dylibs wrapped; the macOS validation bundle carried as a resource in a wrapper framework built by `Tools/ValidationWrapper`), then add ad-hoc signatures to unsigned runtime code. Requires `VULKAN_SDK`, Tuist, and Python 3.
- `make build` — SwiftPM builds for the platform matrix (macOS, iOS device, iOS Simulator) from `config.json`.
- `make test` — runs `make archives`, then `make test-signing`, then `Scripts/check-package.sh`, which writes local and remote package manifest dumps into `Build/` before running the Swift contract tests. PackageContractTests read those dumps.
- `make test-signing` — Python signing regression tests using local compiler fixtures and macOS codesign; does not require staging SDK artifacts.
- `make check-sample` — Tuist-generated sample app (macOS + iOS Simulator, Debug only) that runs the real Vulkan stack and asserts drivers/validation.
- `make check` — signing tests, contract tests, and sample runtime check; `make ci` also runs the SwiftPM platform matrix and is the CI entry point.
- `make dist` — deterministic release zips in `Dist/`.
- `make release [VERSION=x.y.z]` — choose the release version, update `packageVersion` in Package.swift and commit locally if it changes, create an annotated git tag, and push the branch and the tag. Without `VERSION`, the first release or a version already ahead of the latest merged release tag uses the declared version; otherwise the patch increments. Pass `VERSION` for an explicit version. Branch-push CI runs only on `main`; the tag-triggered release workflow independently runs `make ci` before publishing.
- `make check-package-version VERSION=x.y.z` — verify that a tag is bare semver and matches `packageVersion`; the release workflow calls this on tag pushes.

## Gotchas

- `swift test` alone does not prepare its inputs: ArtifactTests require `Dist/*.zip`, and PackageContractTests require the local and remote manifest dumps in `Build/`. Always use `make test` to regenerate these and run the signing tests too.
- The package resolves its binary targets from staged `Artifacts/` XCFrameworks only when `VULKAN_SWIFT_ARTIFACTS` is set (the Makefile exports it as `Artifacts`) — the mere existence of `./Artifacts` does NOT activate local mode. A bare `swift test`/`tuist install` without the env var resolves remote URLs regardless of whether `./Artifacts` exists, like a consumer — that still needs published releases or a warm cache.
- Swift contract tests use **Swift Testing** (`@Test`, `#expect`, `#require`), not XCTest. `Tests/SigningTests.py` uses Python `unittest`.
- `Scripts/sign-unsigned.py` signs unsigned runtime Mach-O binaries and frameworks in staged copies, with nested code signed first and timestamps disabled. Existing signatures and signed enclosing bundles are preserved, even with invalid or partial signatures. XCFramework containers, static libraries, object files, and data are not signed. Release checksums cover the resulting signed artifacts.
- `Config/config.json` is the single source of truth for the Vulkan SDK version (`sdkVersion`), platform matrix, and artifact source/staging paths/licenses. `Package.swift` owns the six binary-target URLs (built from `packageVersion` and its `sdkVersion` constant), SwiftPM-required checksums, and the SwiftPM package version (`packageVersion`); contract tests enforce that the manifest `sdkVersion` mirrors config.json. **SDK bumps update config.json, the `sdkVersion` constant and checksums in Package.swift, and the pinned SDK version assertion in `Tests/ContractTests/ConfigurationTests.swift`; release bumps update `packageVersion`**. The tag-triggered release workflow runs `make ci` before publishing.
- Release tags are bare-semver SwiftPM versions; the release workflow verifies the tag matches `packageVersion` and uploads `Dist/*.zip` under that tag. URLs point at `releases/download/<packageVersion>/<name>-<sdkVersion>.zip`, where `<name>` is the binary target name; archive filenames keep the SDK-version suffix (`<name>-<sdkVersion>.zip`), so the same binaries are re-uploaded unchanged across package releases for the same SDK. Before tagging, the SDK suffix and checksums in Package.swift must match the assets that will be uploaded.
- Remote binary targets mean fresh environments need the GitHub release assets published or a warm SwiftPM/Tuist cache before `swift test` / `tuist install` can resolve.
- Platform split: macOS ships the KosmicKrisp ICD dylib and MoltenVK XCFramework; iOS ships MoltenVK only. Manifests under `Sources/*/vulkan/` are embedded SwiftPM resources.
- Sample: `Sample/Sources/VolkProbe/volk/` is a gitignored symlink to SDK Volk sources (staged by `Scripts/check-sample.sh`). Build it with `tuist xcodebuild build` (Tuist 4's build action) — plain `tuist build` is a different command group.
- New SwiftPM targets must follow the platform-conditional dependency pattern in `Package.swift` (`condition: .when(platforms:)`).
