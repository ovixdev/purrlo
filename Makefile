# Purrlo developer entry points (PRD §9): make test | e2e | e2e-hardware.
SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c

PACKAGE := Packages/KeepAliveCore
PROJECT := Purrlo.xcodeproj
DERIVED := build/DerivedData
E2E_PRODUCTS := $(DERIVED)/Build/Products/E2E
XCODEBUILD := xcodebuild -project $(PROJECT) -derivedDataPath $(DERIVED) -destination "platform=macOS,arch=$(shell uname -m)" -quiet

.PHONY: bootstrap generate build build-release build-e2e lint format test e2e e2e-hardware clean

bootstrap:
	brew install xcodegen swiftlint swiftformat

generate:
	xcodegen generate --quiet

build: generate
	$(XCODEBUILD) -scheme Purrlo -configuration Debug build

build-release: generate
	$(XCODEBUILD) -scheme Purrlo -configuration Release build

build-e2e: generate
	$(XCODEBUILD) -scheme Purrlo-E2E -configuration E2E build

lint:
	swiftformat --lint .
	swiftlint lint --strict --quiet

format:
	swiftformat .
	swiftlint lint --fix --quiet

# L1 + L2 with the 85% line-coverage gate on KeepAliveCore (PRD §8).
test:
	swift test --package-path $(PACKAGE) --enable-code-coverage
	scripts/coverage.sh $(PACKAGE) 85

e2e: build-e2e
	E2E_PRODUCTS="$(abspath $(E2E_PRODUCTS))" scripts/e2e/run-all.sh

e2e-hardware: build-e2e
	E2E_PRODUCTS="$(abspath $(E2E_PRODUCTS))" scripts/e2e/hardware.sh

clean:
	rm -rf build $(PROJECT) $(PACKAGE)/.build
