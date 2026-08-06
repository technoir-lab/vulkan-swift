#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

# The build matrix lives in Config/config.json so adding a target is a config
# edit rather than a Makefile edit. The platforms dictionary is keyed by
# label (for output); each entry may have a SwiftPM triple and Xcode SDK
# name, both omitted for the host build.
build_matrix() {
    jq -r '.platforms | to_entries[] | [
        .key,
        (.value.triple // ""),
        (.value.sdk // "")
    ] | @tsv' "$config_file"
}

while IFS=$'\t' read -r label triple sdk; do
    log "Building $label $triple"
    args=(build)
    if [[ -n "$triple" ]]; then
        args+=(--triple "$triple")
    fi
    if [[ -n "$sdk" ]]; then
        sdk_path="$(xcrun --sdk "$sdk" --show-sdk-path)"
        args+=(--sdk "$sdk_path")
    fi
    swift "${args[@]}"
done < <(build_matrix)
