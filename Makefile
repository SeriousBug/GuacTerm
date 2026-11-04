# GuacTerm — build tooling
#
#   make project      regenerate GuacTerm.xcodeproj from project.yml
#   make build        Release build -> dist/GuacTerm.app
#   make run          build, then launch
#   make clean        remove build/ and dist/
#   make dist         Developer ID sign + notarize + staple -> dist/GuacTerm-<version>.zip
#   make themes       regenerate Resources/Themes.json from the pinned upstream commit
#   make themes-check fail if Resources/Themes.json does not match that commit
#
#   make setup-dev    install the git pre-commit hook (./setup-dev.sh)
#   make format       reformat Sources/ and scripts/ in place (swiftformat)
#   make lint         list style violations (swiftlint)
#   make check        what the pre-commit hook runs: format + lint, no rewriting

XCODEGEN ?= xcodegen

SWIFT_SOURCES = Sources scripts/generate-themes.swift

.PHONY: project build run clean dist themes themes-check setup-dev format lint check

project:
	$(XCODEGEN) generate

build:
	./scripts/build.sh

run: build
	open dist/GuacTerm.app

clean:
	rm -rf build dist

dist:
	./scripts/notarize.sh

themes:
	./scripts/themes.sh

themes-check:
	./scripts/themes.sh --check

setup-dev:
	./setup-dev.sh

format:
	swiftformat $(SWIFT_SOURCES)

lint:
	swiftlint lint --strict

check:
	./scripts/pre-commit.sh
