# GuacTerm — build tooling
#
#   make project      regenerate GuacTerm.xcodeproj from project.yml
#   make build        Release build -> dist/GuacTerm.app
#   make run          build, then launch
#   make clean        remove build/ and dist/
#   make dist         Developer ID sign + notarize + staple -> dist/GuacTerm-<version>.zip
#   make dmg          build, then package dist/GuacTerm-<version>.dmg
#   make appcast      sign dist/GuacTerm-<version>.zip and write the feed -> dist/appcast.xml
#   make release      dist + dmg + appcast, then publish them as a GitHub release
#   make icon         regenerate the app icon PNGs from Resources/logo.svg
#   make themes       regenerate Resources/Themes.json from the pinned upstream commit
#   make themes-check fail if Resources/Themes.json does not match that commit
#
#   make setup-dev    install the git pre-commit hook (./scripts/setup-dev.sh)
#   make format       reformat Swift and shell sources in place
#   make lint         list style violations (swiftlint, shellcheck)
#   make check        what the pre-commit hook runs: format + lint, no rewriting

XCODEGEN ?= xcodegen

SWIFT_SOURCES = Sources scripts/generate-themes.swift
SHELL_SOURCES = $(wildcard scripts/*.sh)

.PHONY: project build run dmg icon clean dist appcast release themes themes-check setup-dev format lint check

project:
	$(XCODEGEN) generate

build:
	./scripts/build.sh

run: build
	open dist/GuacTerm.app

clean:
	rm -rf build dist

dmg:
	./scripts/dmg.sh

icon:
	./scripts/make-icon.sh

dist:
	./scripts/notarize.sh

appcast:
	./scripts/appcast.sh

release:
	./scripts/release.sh

themes:
	./scripts/themes.sh

themes-check:
	./scripts/themes.sh --check

setup-dev:
	./scripts/setup-dev.sh

format:
	swiftformat $(SWIFT_SOURCES)
	shfmt -w $(SHELL_SOURCES)

lint:
	swiftlint lint --strict
	shellcheck $(SHELL_SOURCES)

check:
	./scripts/pre-commit.sh
