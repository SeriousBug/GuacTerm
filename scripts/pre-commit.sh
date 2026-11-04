#!/bin/bash
#
# Check that the tree is formatted and lint clean.
#
#   ./scripts/pre-commit.sh              # the whole project
#   ./scripts/pre-commit.sh <path>...    # only these files or directories
#
# This is what the git pre-commit hook runs (installed by ./scripts/setup-dev.sh), and
# what `make check` calls. It never rewrites a file: a commit is either allowed
# or refused, and the refusal says how to fix it. `make format` does the fixing.
#
# Exit status: 0 clean, 1 something to fix, 2 a tool is missing.
#
set -euo pipefail

cd "$(dirname "$0")/.."

# What to check: the arguments, or the whole project. Swift sources are the
# Sources/ directory and the one Swift tool in scripts/; shell sources are the
# scripts in scripts/. Both are passed explicitly so that build/ and dist/ are
# never scanned. An argument goes to the shell checks when
# it ends in .sh, and to the Swift ones otherwise.
if [[ $# -gt 0 ]]; then
    SWIFT_TARGETS=()
    SHELL_TARGETS=()
    for target in "$@"; do
        case "$target" in
            *.sh) SHELL_TARGETS+=("$target") ;;
            *) SWIFT_TARGETS+=("$target") ;;
        esac
    done
else
    SWIFT_TARGETS=(Sources scripts/generate-themes.swift)
    SHELL_TARGETS=(scripts/*.sh)
fi

# --------------------------------------------------------------------------- #
# Tools
# --------------------------------------------------------------------------- #

missing=()
command -v swiftformat >/dev/null 2>&1 || missing+=(swiftformat)
command -v swiftlint >/dev/null 2>&1 || missing+=(swiftlint)
if [[ ${#SHELL_TARGETS[@]} -gt 0 ]]; then
    command -v shfmt >/dev/null 2>&1 || missing+=(shfmt)
    command -v shellcheck >/dev/null 2>&1 || missing+=(shellcheck)
fi

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

if [[ ${#SWIFT_TARGETS[@]} -gt 0 ]]; then
    echo "==> Formatting (swiftformat)"
    # --lint lists the lines that would change, and by which rule, but writes
    # nothing.
    if ! swiftformat "${SWIFT_TARGETS[@]}" --lint; then
        status=1
    fi

    echo "==> Style (swiftlint)"
    # --strict turns warnings into failures, so nothing is silently tolerated;
    # --quiet drops the per-file progress and keeps the violations.
    if ! swiftlint lint --quiet --strict "${SWIFT_TARGETS[@]}"; then
        status=1
    fi
fi

if [[ ${#SHELL_TARGETS[@]} -gt 0 ]]; then
    echo "==> Shell formatting (shfmt)"
    # -d prints a diff of what would change, and writes nothing. The settings
    # come from .editorconfig, so this agrees with what an editor does.
    if ! shfmt -d "${SHELL_TARGETS[@]}"; then
        status=1
    fi

    echo "==> Shell style (shellcheck)"
    # The defaults warn about everything that is likely to be a bug. Files are
    # read as the interpreter in their shebang, so nothing here is specific to
    # bash.
    if ! shellcheck "${SHELL_TARGETS[@]}"; then
        status=1
    fi
fi

if [[ $status -ne 0 ]]; then
    echo ""
    echo "error: commit blocked, the checks above need to pass first." >&2
    echo "" >&2
    echo "  make format   rewrite the formatting (swiftformat, shfmt)" >&2
    echo "  make lint     list the style violations (swiftlint, shellcheck)" >&2
    echo "" >&2
    echo "then 'git add -u' and commit again. To skip once: git commit --no-verify" >&2
    exit 1
fi

echo "==> Clean"
