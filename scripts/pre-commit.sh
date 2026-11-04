#!/bin/bash
#
# Check that the tree is formatted and lint clean.
#
#   ./scripts/pre-commit.sh              # the whole project
#   ./scripts/pre-commit.sh <path>...    # only these files or directories
#
# This is what the git pre-commit hook runs (installed by ./setup-dev.sh), and
# what `make check` calls. It never rewrites a file: a commit is either allowed
# or refused, and the refusal says how to fix it. `make format` does the fixing.
#
# Exit status: 0 clean, 1 something to fix, 2 a tool is missing.
#
set -euo pipefail

cd "$(dirname "$0")/.."

# What to check: the arguments, or every Swift file in the project. Sources/ is
# a directory and scripts/ holds the one Swift tool, both passed explicitly so
# that build/ and dist/ are never scanned.
if [[ $# -gt 0 ]]; then
    TARGETS=("$@")
else
    TARGETS=(Sources scripts/generate-themes.swift)
fi

# --------------------------------------------------------------------------- #
# Tools
# --------------------------------------------------------------------------- #

missing=()
command -v swiftformat >/dev/null 2>&1 || missing+=(swiftformat)
command -v swiftlint >/dev/null 2>&1 || missing+=(swiftlint)

if [[ ${#missing[@]} -gt 0 ]]; then
    missing_names="$(printf '%s, ' "${missing[@]}")"
    echo "error: ${missing_names%, } not found, so the commit cannot be checked." >&2
    echo "       install them with: brew install ${missing[*]}" >&2
    echo "       or skip:  git commit --no-verify" >&2
    exit 2
fi

# --------------------------------------------------------------------------- #
# Check
# --------------------------------------------------------------------------- #

status=0

echo "==> Formatting (swiftformat)"
# --lint lists the lines that would change, and by which rule, but writes
# nothing.
if ! swiftformat "${TARGETS[@]}" --lint; then
    status=1
fi

echo "==> Style (swiftlint)"
# --strict turns warnings into failures, so nothing is silently tolerated;
# --quiet drops the per-file progress and keeps the violations.
if ! swiftlint lint --quiet --strict "${TARGETS[@]}"; then
    status=1
fi

if [[ $status -ne 0 ]]; then
    echo ""
    echo "error: commit blocked, the checks above need to pass first." >&2
    echo "" >&2
    echo "  make format   rewrite the formatting (swiftformat)" >&2
    echo "  make lint     list the style violations (swiftlint)" >&2
    echo "" >&2
    echo "then 'git add -u' and commit again. To skip once: git commit --no-verify" >&2
    exit 1
fi

echo "==> Clean"
