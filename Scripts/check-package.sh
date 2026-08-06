#!/usr/bin/env bash
# Package-level check: dump the manifest in both resolution modes (local and
# remote) so PackageContractTests can assert on both, then run the full Swift
# Testing suite. Requires staged release archives first (make archives).
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

mkdir -p Build
swift package dump-package > Build/package-manifest.json
VULKAN_SWIFT_ARTIFACTS=off swift package dump-package > Build/package-manifest-remote.json
swift test
