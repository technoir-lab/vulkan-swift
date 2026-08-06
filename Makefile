SHELL := /bin/bash

# Resolve the package's binary targets from the locally staged artifacts so
# building and testing never depend on the release assets being published.
# Consumers (no VULKAN_SWIFT_ARTIFACTS) still get remote URLs.
export VULKAN_SWIFT_ARTIFACTS ?= Artifacts

.PHONY: all artifacts archives build test check check-sample \
	dist ci clean release check-package-version

all: check

artifacts:
	@Scripts/stage-artifacts.sh

build: artifacts
	@Scripts/build-package.sh

archives: artifacts
	@Scripts/archive-artifacts.sh

test: archives
	@Scripts/check-package.sh

check: test check-sample

check-sample: artifacts
	@Scripts/check-sample.sh

dist: archives

release:
	@if [ -n "$(VERSION)" ]; then \
		Scripts/release.sh --version "$(VERSION)"; \
	else \
		Scripts/release.sh; \
	fi

check-package-version:
	@Scripts/check-package-version.sh "$(VERSION)"

ci: build check

clean:
	swift package clean
	rm -rf Build Dist Artifacts \
		Sample/.build \
		Sample/Sample.xcodeproj \
		Sample/Sample.xcworkspace \
		Sample/Sources/VolkProbe/volk \
		Tools/ValidationWrapper/ValidationWrapper.xcodeproj \
		Tools/ValidationWrapper/ValidationWrapper.xcworkspace \
		Tools/ValidationWrapper/Resources
