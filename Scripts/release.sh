#!/usr/bin/env bash
# Release the package: bump `packageVersion` in Package.swift, commit it
# locally, tag it, and push the branch and the tag.
#
# Usage:
#   Scripts/release.sh                  # auto-increment the patch component
#   Scripts/release.sh --version 1.1.0  # explicit minor or major bump
#   Scripts/release.sh --dry-run ...    # print the plan without changing anything
#
# The branch push publishes the bump commit, and the tag push triggers the
# release workflow.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

version_arg=""
dry_run=0

usage() {
    sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --version)
            [[ $# -ge 2 ]] || die "--version requires a value"
            version_arg="$2"
            shift 2
            ;;
        --dry-run)
            dry_run=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            die "unknown argument: $1"
            ;;
    esac
done

manifest="$repo_root/Package.swift"
current="$(manifest_package_version)"

manifest_sdk="$(sed -n 's/^let sdkVersion = "\([^"]*\)".*/\1/p' "$manifest")"
[[ -n "$manifest_sdk" ]] || die "could not find 'let sdkVersion' in Package.swift"
config_sdk="$(config_get sdkVersion)"
[[ "$manifest_sdk" == "$config_sdk" ]] \
    || die "Package.swift sdkVersion '$manifest_sdk' does not match configuration '$config_sdk'"

is_bare_semver "$current" \
    || die "current packageVersion '$current' is not bare semver"

# Releases are bare-semver tags merged into HEAD; the legacy 1.4.357.0 tag is
# ignored because it is not a valid SwiftPM version.
latest_tag="$(
    git tag --merged HEAD 2>/dev/null \
        | grep -E '^[0-9]+[.][0-9]+[.][0-9]+$' \
        | sort -t. -k1,1n -k2,2n -k3,3n \
        | tail -n 1 || true
)"

if [[ -n "$version_arg" ]]; then
    target="$version_arg"
    is_bare_semver "$target" \
        || die "VERSION must be bare semver like 1.1.0 (got '$target')"
    if semver_gt "$current" "$target"; then
        die "VERSION '$target' is older than the declared packageVersion '$current'"
    fi
    if [[ -n "$latest_tag" ]] && semver_gt "$latest_tag" "$target"; then
        die "VERSION '$target' is older than the latest tag '$latest_tag'"
    fi
elif [[ -z "$latest_tag" ]]; then
    # First release: tag the version already declared in Package.swift.
    target="$current"
elif semver_gt "$current" "$latest_tag"; then
    # The manifest was already bumped ahead of the latest tag (e.g. a manual
    # minor/major bump): release it as declared.
    target="$current"
else
    # Auto-increment the patch component from the newest released version,
    # or catch up if the branch is behind the latest tag.
    if semver_gt "$latest_tag" "$current"; then
        base="$latest_tag"
    else
        base="$current"
    fi
    IFS=. read -r major minor patch <<< "$base"
    target="$major.$minor.$((patch + 1))"
fi

is_bare_semver "$target" || die "computed target '$target' is not bare semver"

if [[ -n "$(git rev-parse -q --verify "refs/tags/$target")" ]]; then
    die "tag '$target' already exists locally"
fi
if ! git remote get-url origin >/dev/null 2>&1; then
    die "no git remote named 'origin'"
fi
if git ls-remote --tags origin "refs/tags/$target" 2>/dev/null | grep -q .; then
    die "tag '$target' already exists on origin"
fi
if ! git diff --quiet || ! git diff --cached --quiet; then
    die "working tree has uncommitted changes; commit or stash them first"
fi

branch="$(git branch --show-current)"
[[ -n "$branch" ]] || die "not on a branch; check out the branch you want to release"

run() {
    if [[ "$dry_run" == 1 ]]; then
        log "dry-run: $*"
    else
        "$@"
    fi
}

if [[ "$target" != "$current" ]]; then
    if [[ "$dry_run" == 1 ]]; then
        log "dry-run: Package.swift packageVersion $current -> $target"
    else
        sed -i '' "s/^let packageVersion = \"$current\"/let packageVersion = \"$target\"/" \
            "$manifest"
        log "Package.swift: packageVersion $current -> $target"
    fi
    run git add "$manifest"
    run git commit -m "Release $target"
else
    log "Package.swift: packageVersion already $target"
fi

run git tag -a "$target" -m "Release $target"
run git push origin "$branch"
run git push origin "refs/tags/$target"

if [[ "$dry_run" == 0 ]]; then
    log "Released $target"
fi
