# Purrlo developer entry points (PRD §9): make check | test | e2e | e2e-hardware.
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

PACKAGE := Packages/KeepAliveCore
PROJECT := Purrlo.xcodeproj
DERIVED := build/DerivedData
E2E_PRODUCTS := $(DERIVED)/Build/Products/E2E
XCODEBUILD := xcodebuild -project $(PROJECT) -derivedDataPath $(DERIVED) -destination "platform=macOS,arch=$(shell uname -m)" -quiet

.PHONY: bootstrap generate build build-release build-e2e check-release lint format test e2e e2e-hardware clean

bootstrap:
	brew install xcodegen swiftlint swiftformat
	git config core.hooksPath .githooks

generate:
	xcodegen generate --quiet

build: generate
	$(XCODEBUILD) -scheme Purrlo -configuration Debug build

build-release: generate
	$(XCODEBUILD) -scheme Purrlo -configuration Release build

build-e2e: generate
	$(XCODEBUILD) -scheme Purrlo-E2E -configuration E2E build

# NFR-10: the Release binary contains no E2E test hooks.
check-release: build-release
	scripts/check-release-hooks.sh $(DERIVED)/Build/Products/Release/Purrlo.app

.PHONY: check check-xcode

# Everything CI runs, in one target. The pre-push hook calls it (AGENTS.md).
check: check-xcode lint test check-release e2e

# CI selects the Xcode in .xcode-version; a different local Xcode can pass here and fail there.
check-xcode:
	@want="$$(cat .xcode-version)"; have="$$(xcodebuild -version | awk 'NR == 1 { print $$2 }')"; \
	[ "$$want" = "$$have" ] || { echo "Xcode $$have is selected, but .xcode-version (used by CI) pins $$want"; exit 1; }

lint:
	swiftformat --lint .
	swiftlint lint --strict --quiet

format:
	swiftformat .
	swiftlint lint --fix --quiet

# L1 + L2 with the 85% line-coverage gate on KeepAliveCore (PRD §8), then the static NFR-3 render-thread check.
test:
	swift test --package-path $(PACKAGE) --enable-code-coverage
	scripts/coverage.sh $(PACKAGE) 85
	swift build --package-path $(PACKAGE) -c release --product KeepAliveCore
	scripts/check_render_thread.py $(PACKAGE)/.build/release/KeepAliveCore.build

e2e: build-e2e
	E2E_PRODUCTS="$(abspath $(E2E_PRODUCTS))" scripts/e2e/run-all.sh

e2e-hardware: build-e2e
	E2E_PRODUCTS="$(abspath $(E2E_PRODUCTS))" scripts/e2e/hardware.sh

clean:
	rm -rf build $(PROJECT) $(PACKAGE)/.build
