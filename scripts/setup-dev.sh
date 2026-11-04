#!/bin/bash
#
# Set up this checkout for development.
#
#   ./scripts/setup-dev.sh              install the pre-commit hook
#   ./scripts/setup-dev.sh --uninstall  remove the hook again
#
# The hook is a small shim: it runs scripts/pre-commit.sh, which is where the
# checks live. Updating the checks therefore never means reinstalling the hook,
# and the hook works the same in every worktree of this repository.
#
# Only this repository is touched. If core.hooksPath is already configured, that
# path is used instead of .git/hooks, and this says so.
#
# The checks need swiftformat and swiftlint for the Swift sources, and for the
# shell scripts shfmt and shellcheck. Nothing is downloaded or installed here: a
# missing tool is named with the command that installs it, and that is all.
#
set -euo pipefail

# The repository root is one level up, and everything below is relative to it,
# so the script works the same from any directory and in any worktree.
cd "$(dirname "$0")/.."
REPO_ROOT="$PWD"

# Marks a hook as ours, so it is safe to replace and to remove.
MARKER="# guacterm pre-commit hook"

usage() {
    # Every line of the comment block at the top, without the '#' in front.
    sed -n '/^#!/d; /^set /q; p' "$0" | sed 's/^# \{0,1\}//'
}

UNINSTALL=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --uninstall) UNINSTALL=1 ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "error: unknown argument '$1' (try --help)" >&2
            exit 2
            ;;
    esac
    shift
done

if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "error: $REPO_ROOT is not a git checkout, there is nowhere to install a hook." >&2
    exit 1
fi

# --------------------------------------------------------------------------- #
# Where git looks for hooks
# --------------------------------------------------------------------------- #

HOOKS_DIR="$(git rev-parse --git-path hooks)"
if [[ "$HOOKS_DIR" != /* ]]; then
    HOOKS_DIR="$REPO_ROOT/$HOOKS_DIR"
fi

HOOKS_PATH="$(git config --get core.hooksPath || true)"
if [[ -n "$HOOKS_PATH" ]]; then
    case "$HOOKS_PATH" in
        /*) HOOKS_DIR="$HOOKS_PATH" ;;
        *) HOOKS_DIR="$REPO_ROOT/$HOOKS_PATH" ;;
    esac
    echo "note: core.hooksPath is set, installing into $HOOKS_DIR"
fi

HOOK="$HOOKS_DIR/pre-commit"

# --------------------------------------------------------------------------- #
# Uninstall
# --------------------------------------------------------------------------- #

if [[ "$UNINSTALL" -eq 1 ]]; then
    if [[ -f "$HOOK" ]] && grep -qF "$MARKER" "$HOOK"; then
        rm -f "$HOOK"
        echo "==> Removed $HOOK"
    else
        echo "==> No GuacTerm hook at $HOOK, nothing to remove"
    fi
    exit 0
fi

# --------------------------------------------------------------------------- #
# Tools
# --------------------------------------------------------------------------- #

missing=()
for tool in swiftformat swiftlint shfmt shellcheck; do
    command -v "$tool" >/dev/null 2>&1 || missing+=("$tool")
done

if [[ ${#missing[@]} -gt 0 ]]; then
    missing_names="$(printf '%s, ' "${missing[@]}")"
    echo "warning: ${missing_names%, } not found, so the hook will refuse commits." >&2
    echo "         install them with: brew install ${missing[*]}" >&2
    echo "" >&2
fi

# --------------------------------------------------------------------------- #
# Install
# --------------------------------------------------------------------------- #

mkdir -p "$HOOKS_DIR"

# Never silently throw away someone else's hook: keep it next to ours.
if [[ -f "$HOOK" ]] && ! grep -qF "$MARKER" "$HOOK"; then
    BACKUP="$HOOK.backup-$(date +%Y%m%d-%H%M%S)"
    mv "$HOOK" "$BACKUP"
    echo "==> Kept the previous hook as $BACKUP"
fi

cat >"$HOOK" <<EOF
#!/bin/sh
$MARKER
# Installed by ./scripts/setup-dev.sh. The checks live in scripts/pre-commit.sh;
# edit that instead, it is the same script 'make check' runs.
exec "\$(git rev-parse --show-toplevel)/scripts/pre-commit.sh" "\$@"
EOF
chmod +x "$HOOK"

echo "==> Installed $HOOK"
echo "    every commit now runs scripts/pre-commit.sh first."
echo "    'make format' fixes formatting, 'git commit --no-verify' skips once."
