# GuacTerm — build tooling
#
#   make project      regenerate GuacTerm.xcodeproj from project.yml
#   make build        Release build -> dist/GuacTerm.app
#   make run          build, then launch
#   make clean        remove build/ and dist/
#   make dist         Developer ID sign + notarize + staple -> dist/GuacTerm-<version>.zip
#   make themes       regenerate Resources/Themes.json from the pinned upstream commit
#   make themes-check fail if Resources/Themes.json does not match that commit

XCODEGEN ?= xcodegen

.PHONY: project build run clean dist themes themes-check

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
