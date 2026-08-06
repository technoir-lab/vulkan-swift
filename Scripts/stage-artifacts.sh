#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

require_sdk
root="$(sdk_root)"

mkdir -p "$repo_root/Artifacts"
mkdir -p "$repo_root/Build"
mkdir -p "$repo_root/Dist"

build_framework_wrapper() {
    local id="$1"
    local source="$2"
    local local_path="$3"
    local framework_name
    framework_name="$(artifact_field "$id" framework)"
    [[ -n "$framework_name" ]] || die "missing framework name for $id"

    local project_dir="$repo_root/Tools/ValidationWrapper"
    local resource_dir="$project_dir/Resources"
    local resource="$resource_dir/$(basename "$source")"
    local build_dir="$repo_root/Build/$framework_name"
    local derived_data="$build_dir/DerivedData"
    local framework="$derived_data/Build/Products/Release/$framework_name.framework"
    local wrapped_tmp="$repo_root/Build/$(basename "$local_path" .xcframework).tmp.xcframework"
    local generated_project="$project_dir/ValidationWrapper.xcodeproj"
    local generated_workspace="$project_dir/ValidationWrapper.xcworkspace"

    (
        trap 'rm -rf "$resource_dir" "$build_dir" "$wrapped_tmp" "$generated_project" "$generated_workspace"' EXIT
        [[ -d "$project_dir" ]] || die "missing Tuist wrapper project: $project_dir"
        rm -rf "$resource_dir" "$build_dir" "$wrapped_tmp" \
            "$generated_project" "$generated_workspace"
        mkdir -p "$resource_dir"
        cp -L "$source" "$resource"
        cd "$project_dir"
        tuist generate --no-open
        tuist xcodebuild build \
            -workspace ValidationWrapper.xcworkspace \
            -scheme "$framework_name" \
            -configuration Release \
            -destination "generic/platform=macOS" \
            -derivedDataPath "$derived_data"

        [[ -d "$framework" ]] \
            || die "Tuist wrapper framework missing: $framework"
        # The generated framework Info.plist embeds the build machine and
        # toolchain versions, which would make the release archive
        # non-reproducible. Keep only the stable bundle metadata.
        local info_plist="$framework/Resources/Info.plist"
        local plist_key
        for plist_key in \
            BuildMachineOSBuild \
            DTCompiler \
            DTPlatformBuild \
            DTPlatformName \
            DTPlatformVersion \
            DTSDKBuild \
            DTSDKName \
            DTXcode \
            DTXcodeBuild
        do
            plutil -remove "$plist_key" "$info_plist" >/dev/null 2>&1 || true
        done
        xcodebuild -create-xcframework \
            -framework "$framework" \
            -output "$wrapped_tmp" >/dev/null

        local staged_resource
        staged_resource="$(find "$wrapped_tmp" -type f -name "$(basename "$source")" -print -quit)"
        [[ -n "$staged_resource" ]] || die "validation bundle missing from $id"
        local source_hash
        local staged_hash
        source_hash="$(shasum -a 256 "$source" | awk '{print $1}')"
        staged_hash="$(shasum -a 256 "$staged_resource" | awk '{print $1}')"
        [[ "$source_hash" == "$staged_hash" ]] || die "validation bundle bytes changed in $id"

        rm -rf "$local_path"
        mv "$wrapped_tmp" "$local_path"
        [[ -d "$local_path" && ! -L "$local_path" ]] \
            || die "wrapped artifact is not a directory: $local_path"
        log "Wrapped framework: $local_path"
    )
}

build_dylib_wrapper() {
    local source="$1"
    local local_path="$2"
    local regular_dir="$repo_root/Build/regular"
    local regular_copy="$regular_dir/$(basename "$source")"
    local wrapped_tmp="$repo_root/Build/$(basename "$local_path" .xcframework).tmp.xcframework"

    # The SDK ships some dylibs as symlinks. Wrap a regular byte-identical
    # copy so the archive contains a real file.
    mkdir -p "$regular_dir"
    cp -L "$source" "$regular_copy"
    rm -rf "$wrapped_tmp"
    xcodebuild -create-xcframework \
        -library "$regular_copy" \
        -output "$wrapped_tmp" >/dev/null
    rm -f "$regular_copy"
    rm -rf "$local_path"
    mv "$wrapped_tmp" "$local_path"
    [[ -d "$local_path" && ! -L "$local_path" ]] \
        || die "wrapped artifact is not a directory: $local_path"
    log "Wrapped dylib: $local_path"
}

stage() {
    local id
    local kind
    local source
    local local_path
    for id in $(artifact_ids); do
        kind="$(artifact_field "$id" kind)"
        source="$(replace_placeholder "$(artifact_field "$id" source)")"
        local_path="$repo_root/$(artifact_field "$id" local)"
        case "$kind" in
            vendor-xcframework)
                rm -rf "$local_path"
                ditto "$source" "$local_path"
                [[ -d "$local_path" && ! -L "$local_path" ]] \
                    || die "vendor artifact is not a directory: $local_path"
                log "Copied framework: $local_path"
                ;;
            wrapped-dylib)
                build_dylib_wrapper "$source" "$local_path"
                ;;
            wrapped-bundle)
                build_framework_wrapper "$id" "$source" "$local_path"
                ;;
            *)
                die "unknown artifact kind '$kind' for $id"
                ;;
        esac
    done
}

stage
