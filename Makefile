SHELL := sh
.DEFAULT_GOAL := help

# Resolve the package's binary targets from the locally staged artifacts so
# building and testing never depend on the release assets being published.
# Consumers (no VULKAN_SWIFT_ARTIFACTS) still get remote URLs.
export VULKAN_SWIFT_ARTIFACTS ?= Artifacts

.PHONY: all artifacts archives build test test-signing check check-sample \
	dist ci clean release check-package-version help

all: check ## Run all checks

artifacts: ## Stage and sign SDK artifacts
	@Scripts/stage-artifacts.sh

build: artifacts ## Build the SwiftPM platform matrix
	@Scripts/build-package.sh

archives: artifacts ## Create deterministic release archives
	@Scripts/archive-artifacts.sh

test: archives ## Run signing and package contract tests
	@$(MAKE) test-signing
	@Scripts/check-package.sh

test-signing: ## Run signing regression tests
	@python3 -B Tests/SigningTests.py

check: test check-sample ## Run tests and sample runtime checks

check-sample: artifacts ## Build and run the sample app
	@Scripts/check-sample.sh

dist: archives ## Create release archives in Dist

release: ## Commit the release version, tag, and push
	@if [ -n "$(VERSION)" ]; then \
		Scripts/release.sh --version "$(VERSION)"; \
	else \
		Scripts/release.sh; \
	fi

check-package-version: ## Verify VERSION matches the package version
	@Scripts/check-package-version.sh "$(VERSION)"

ci: build check ## Build and run all CI checks

clean: ## Remove generated build outputs and artifacts
	@swift package clean
	@rm -rf Build Dist Artifacts \
		Sample/.build \
		Sample/Sample.xcodeproj \
		Sample/Sample.xcworkspace \
		Sample/Sources/VolkProbe/volk \
		Tools/ValidationWrapper/ValidationWrapper.xcodeproj \
		Tools/ValidationWrapper/ValidationWrapper.xcworkspace \
		Tools/ValidationWrapper/Resources

help: ## Show this help
	@printf 'Available targets:\n'
	@color=''; reset=''; \
	if [ -t 1 ] && [ "$${TERM:-dumb}" != dumb ] && [ -z "$${NO_COLOR:-}" ]; then \
		color=$$(printf '\033[36m'); reset=$$(printf '\033[0m'); \
	fi; \
	awk -v color="$$color" -v reset="$$reset" '/^[[:alnum:]_-]+:/ { target = $$0; sub(/:.*/, "", target); description = $$0; if (sub(/.*##[[:space:]]*/, "", description) == 0) description = ""; printf "  %s%s%s%*s %s\n", color, target, reset, 23 - length(target), "", description }' $(MAKEFILE_LIST)
	@printf '\nPass an explicit release version with VERSION, e.g. make release VERSION=1.2.3\n'
