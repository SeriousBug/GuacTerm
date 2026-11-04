# GuacTerm — build tooling
#
#   make project   regenerate GuacTerm.xcodeproj from project.yml
#   make build     Release build -> dist/GuacTerm.app
#   make run       build, then launch
#   make clean     remove build/ and dist/
#   make dist      Developer ID sign + notarize + staple -> dist/GuacTerm-<version>.zip

XCODEGEN ?= xcodegen

.PHONY: project build run clean dist

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
