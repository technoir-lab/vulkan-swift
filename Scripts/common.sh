#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
config_file="$repo_root/Config/config.json"

log() {
    echo "$*"
}

die() {
    log "Error: $*" >&2
    exit 1
}

# Release-version helpers shared by the release tooling.
manifest_package_version() {
    local version
    version="$(sed -n 's/^let packageVersion = "\([^"]*\)".*/\1/p' "$repo_root/Package.swift")"
    [[ -n "$version" ]] || die "packageVersion not found in Package.swift"
    printf '%s' "$version"
}

is_bare_semver() {
    [[ "$1" =~ ^[0-9]+[.][0-9]+[.][0-9]+$ ]]
}

semver_gt() {
    local a b
    IFS=. read -r -a a <<< "$1"
    IFS=. read -r -a b <<< "$2"
    local i
    for i in 0 1 2; do
        if (( ${a[i]:-0} > ${b[i]:-0} )); then
            return 0
        elif (( ${a[i]:-0} < ${b[i]:-0} )); then
            return 1
        fi
    done
    return 1
}

config_get() {
    jq -r --arg key "$1" '
        getpath($key | split(".")) // error("config key not found: \($key)")
        | if type == "object" or type == "array" then tostring else . end
    ' "$config_file"
}

sdk_root() {
    local sdk="${VULKAN_SDK:-}"
    [[ -n "$sdk" ]] || die "VULKAN_SDK is not set"
    # $VULKAN_SDK always points at the macOS platform tree (…/macOS)
    case "$sdk" in
        */macOS)
            printf '%s' "${sdk%/*}"
            ;;
        *)
            printf '%s' "$sdk"
            ;;
    esac
}

require_sdk() {
    local root
    root="$(sdk_root)"
    [[ -d "$root" ]] || die "Vulkan SDK root not found: $root"
    local missing=0
    local id
    local kind
    local source
    for id in $(artifact_ids); do
        kind="$(artifact_field "$id" kind)"
        source="$(replace_placeholder "$(artifact_field "$id" source)")"
        case "$kind" in
            vendor-xcframework)
                [[ -d "$source" ]] || { log "Error: missing SDK artifact '$id': $source" >&2; missing=1; }
                ;;
            wrapped-dylib|wrapped-bundle)
                [[ -f "$source" ]] || { log "Error: missing SDK artifact '$id': $source" >&2; missing=1; }
                ;;
            *)
                die "unknown artifact kind '$kind' for $id"
                ;;
        esac
    done
    [[ "$missing" == 0 ]] || exit 1
}

artifact_ids() {
    jq -r '.artifacts[].id' "$config_file"
}

artifact_field() {
    jq -r --arg id "$1" --arg field "$2" '
        (.artifacts | map(select(.id == $id))
         | if length == 0 then error("no artifact: \($id)") else .[0] end) as $a
        | $a[$field] // ""
    ' "$config_file"
}

artifact_licenses() {
    jq -r --arg id "$1" '
        (.artifacts | map(select(.id == $id))
         | if length == 0 then error("no artifact: \($id)") else .[0] end) as $a
        | $a.licenses[]?
    ' "$config_file"
}

# Archive names are derived from the artifact id and the SDK version so they
# cannot drift from the central configuration. Release URLs additionally use
# `packageVersion` from Package.swift as the release tag segment and the
# `sdkVersion` constant for the filename suffix.
artifact_archive() {
    printf '%s-%s.zip' "$1" "$(config_get sdkVersion)"
}

artifact_archive_path() {
    printf '%s/Dist/%s' "$repo_root" "$(artifact_archive "$1")"
}

replace_placeholder() {
    local value="$1"
    local root
    root="$(sdk_root)"
    printf '%s' "${value//\$SDK_ROOT/$root}"
}

sanitize_vulkan_env() {
    unset VK_ICD_FILENAMES
    unset VK_DRIVER_FILES
    unset VK_ADD_DRIVER_FILES
    unset VK_ADDITIONAL_DRIVER_FILES
    unset VK_LAYER_PATH
    unset VK_ADD_LAYER_PATH
    unset VK_ADDITIONAL_LAYER_PATH
    unset VK_INSTANCE_LAYERS
    unset VK_IMPLICIT_LAYER_PATH
    unset DYLD_LIBRARY_PATH
    unset DYLD_FALLBACK_LIBRARY_PATH
}
