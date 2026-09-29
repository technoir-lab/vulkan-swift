#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_sdk

if ! command -v tuist >/dev/null 2>&1; then
    die "tuist is not installed; run: brew install --cask tuist"
fi

# Stage the SDK's Volk sources into the sample (gitignored symlinks).
root="$(sdk_root)"
volk_dir="$repo_root/Sample/Sources/VolkProbe/volk"
mkdir -p "$volk_dir"
ln -sfn "$root/macOS/include/volk/volk.c" "$volk_dir/volk.c"
ln -sfn "$root/macOS/include/volk/volk.h" "$volk_dir/volk.h"

cd "$repo_root/Sample"

# Tuist forwards TUIST_-prefixed variables to manifest evaluation; the
# manifest normalizes the /macOS platform-tree suffix itself.
export TUIST_VULKAN_SDK="$VULKAN_SDK"
tuist install
tuist generate --no-open

mac_destination="platform=macOS,arch=arm64"
ios_destination="generic/platform=iOS Simulator"
derived_data=".build/DerivedData"

app_dir() {
    local configuration="$1"
    local platform_suffix="${2:-}"
    printf '%s/.build/DerivedData/Build/Products/%s%s/VulkanSwiftSample.app' \
        "$repo_root/Sample" "$configuration" "$platform_suffix"
}

assert_absent() {
    local app="$1"
    local pattern="$2"
    local label="$3"
    if find "$app" -name "$pattern" | grep -q .; then
        die "$label: unexpected '$pattern' in $app"
    fi
}

assert_present() {
    local app="$1"
    local path="$2"
    local label="$3"
    [[ -e "$app/$path" ]] || die "$label: missing $path in $app"
}

run_macos_app() {
    local configuration="$1"
    local expected_validation="$2"
    local app
    app="$(app_dir "$configuration")"
    local output
    if ! output="$(
        sanitize_vulkan_env
        "$app/Contents/MacOS/VulkanSwiftSample" 2>&1
    )"; then
        die "macOS $configuration: KosmicKrisp probe failed: $output"
    fi
    echo "$output" | grep -q "Driver: KosmicKrisp" \
        || die "macOS $configuration: expected driver 'KosmicKrisp', got: $output"
    echo "$output" | grep -q "Validation: $expected_validation" \
        || die "macOS $configuration: expected validation '$expected_validation', got: $output"
    echo "$output" | grep -q "Vulkan version:" \
        || die "macOS $configuration: no Vulkan version in output: $output"
    echo "$output" | grep -q "Device Vulkan version:" \
        || die "macOS $configuration: no device Vulkan version in output: $output"
    log "macOS $configuration: KosmicKrisp, Vulkan 1.4, validation $expected_validation"
}

find_simulator() {
    local runtime_filter="${1:-}"
    xcrun simctl list devices available -j | jq -r --arg filter "$runtime_filter" '
        (.devices | to_entries | map(
            select($filter == "" or (.key | contains($filter)))
            | .value[] | select(.isAvailable) | .udid
        ) | if length == 0 then error("no available simulator") else .[0] end)
    '
}

run_simulator_app() {
    local configuration="$1"
    local expected_driver="$2"
    local expected_validation="$3"
    local platform="$4"
    local app="$5"
    local runtime_filter="$6"

    local udid
    udid="$(find_simulator "$runtime_filter")"
    xcrun simctl boot "$udid" >/dev/null 2>&1 || true
    xcrun simctl bootstatus "$udid" -b >/dev/null
    xcrun simctl uninstall "$udid" io.technoirlab.vulkan-swift-sample \
        >/dev/null 2>&1 || true
    xcrun simctl install "$udid" "$app"

    local container
    container="$(xcrun simctl get_app_container \
        "$udid" io.technoirlab.vulkan-swift-sample data)"
    local report="$container/Library/Caches/vulkan-probe.txt"
    local deadline=$((SECONDS + 30))
    local output
    sanitize_vulkan_env
    xcrun simctl launch "$udid" io.technoirlab.vulkan-swift-sample >/dev/null
    while [[ ! -f "$report" && $SECONDS -lt $deadline ]]; do
        sleep 1
    done
    [[ -f "$report" ]] || die "$platform $configuration: probe timed out"
    output="$(<"$report")"
    echo "$output" | grep -q "Driver: $expected_driver" \
        || die "$platform $configuration: expected driver '$expected_driver', got: $output"
    echo "$output" | grep -q "Validation: $expected_validation" \
        || die "$platform $configuration: expected validation '$expected_validation', got: $output"
    echo "$output" | grep -q "Device Vulkan version:" \
        || die "$platform $configuration: no device Vulkan version in output: $output"
    log "$platform $configuration: $expected_driver, Vulkan 1.4, validation $expected_validation"
}

check_macos_bundle() {
    local configuration="$1"
    local app
    app="$(app_dir "$configuration")"
    assert_present "$app" "Contents/Frameworks/vulkan.framework/Versions/A/vulkan" "macOS $configuration"
    assert_present "$app" "Contents/Frameworks/KosmicKrisp.framework/Versions/A/KosmicKrisp" "macOS $configuration"
    assert_absent "$app" "MoltenVK.framework" "macOS $configuration"
    assert_absent "$app" "MoltenVK_icd.json" "macOS $configuration"
    assert_present "$app" \
        "Contents/Resources/vulkan-swift_VulkanDriverMacOSResources.bundle/Contents/Resources/vulkan/icd.d/libkosmickrisp_icd.json" \
        "macOS $configuration"
    assert_present "$app" \
        "Contents/Resources/vulkan-swift_VulkanValidationMacOSResources.bundle/Contents/Resources/vulkan/explicit_layer.d/VkLayer_khronos_validation.json" \
        "macOS $configuration"
    assert_present "$app" \
        "Contents/Frameworks/VulkanValidationMacOS.framework/Versions/A/Resources/libVkLayer_khronos_validation.dylib" \
        "macOS $configuration"
}

check_ios_bundle() {
    local configuration="$1"
    local app
    app="$(app_dir "$configuration" "-iphonesimulator")"
    assert_present "$app" "Frameworks/vulkan.framework/vulkan" "iOS $configuration"
    assert_present "$app" "Frameworks/MoltenVK.framework/MoltenVK" "iOS $configuration"
    assert_absent "$app" "KosmicKrisp.framework" "iOS $configuration"
    assert_present "$app" \
        "vulkan-swift_VulkanDriverIOSResources.bundle/vulkan/icd.d/MoltenVK_icd.json" \
        "iOS $configuration"
    assert_present "$app" \
        "Frameworks/VkLayer_khronos_validation.framework/VkLayer_khronos_validation" \
        "iOS $configuration"
    assert_present "$app" \
        "vulkan-swift_VulkanValidationIOSResources.bundle/vulkan/explicit_layer.d/VkLayer_khronos_validation.json" \
        "iOS $configuration"
}

build_configuration() {
    local configuration="$1"
    local expected_validation="$2"
    local mac_log=".build/tuist-macos-$configuration.log"
    local ios_log=".build/tuist-ios-$configuration.log"

    if ! tuist xcodebuild build \
        -workspace Sample.xcworkspace \
        -scheme SampleMacOS \
        -configuration "$configuration" \
        -destination "$mac_destination" \
        -derivedDataPath "$derived_data" \
        >"$mac_log" 2>&1; then
        tail -n 60 "$mac_log" >&2
        die "macOS $configuration build failed"
    fi
    if ! tuist xcodebuild build \
        -workspace Sample.xcworkspace \
        -scheme SampleIOS \
        -configuration "$configuration" \
        -destination "$ios_destination" \
        -derivedDataPath "$derived_data" \
        >"$ios_log" 2>&1; then
        tail -n 60 "$ios_log" >&2
        die "iOS $configuration build failed"
    fi

    check_macos_bundle "$configuration"
    check_ios_bundle "$configuration"
    if [[ "${VULKAN_SWIFT_SAMPLE_SKIP_KOSMICKRISP:-0}" == 1 ]]; then
        log "macOS $configuration: KosmicKrisp runtime check skipped (Metal 4 hardware required)"
    else
        run_macos_app "$configuration" "$expected_validation"
    fi
    run_simulator_app "$configuration" "MoltenVK" "$expected_validation" \
        "iOS" "$(app_dir "$configuration" "-iphonesimulator")" "iOS"
}

build_configuration Debug enabled

log "Sample check passed"
