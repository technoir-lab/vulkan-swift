#!/usr/bin/env bash
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

mkdir -p "$repo_root/Dist"

# Recreate all archives from scratch so renamed or removed artifacts never
# linger in Dist/ and get uploaded to a release.
rm -f "$repo_root"/Dist/*.zip

for id in $(artifact_ids); do
    local_path="$repo_root/$(artifact_field "$id" local)"
    archive_path="$(artifact_archive_path "$id")"
    [[ -d "$local_path" ]] || die "missing staged artifact: $local_path (run make artifacts)"

    args=(
        "$archive_path"
        "$local_path"
        "$(basename "$local_path")"
    )
    for license_name in $(artifact_licenses "$id"); do
        license_path="$repo_root/Licenses/$license_name"
        [[ -f "$license_path" ]] || die "missing license file: $license_path"
        args+=("$license_path" "Licenses/$license_name")
    done

    python3 "$repo_root/Scripts/deterministic-zip.py" "${args[@]}"
done
