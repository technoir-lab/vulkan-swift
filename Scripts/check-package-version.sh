#!/usr/bin/env bash
# Verify that a release tag is bare semver and matches the packageVersion
# declared in Package.swift. Used by the release workflow on tag pushes and
# locally before publishing: `make check-package-version VERSION=1.0.0`.
set -euo pipefail

source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

tag="${1:-}"
[[ -n "$tag" ]] || die "usage: check-package-version.sh <tag>"

expected="$(manifest_package_version)"
is_bare_semver "$expected" \
    || die "packageVersion '$expected' is not bare semver"
is_bare_semver "$tag" \
    || die "tag '$tag' is not bare semver"
[[ "$tag" == "$expected" ]] \
    || die "tag '$tag' does not match packageVersion '$expected'"

log "tag '$tag' matches packageVersion"
