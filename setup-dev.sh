#!/bin/bash
#
# Set up this checkout for development.
#
#   ./setup-dev.sh              install the pre-commit hook
#   ./setup-dev.sh --uninstall  remove the hook again
#
# The hook is a small shim: it runs scripts/pre-commit.sh, which is where the
# checks live. Updating the checks therefore never means reinstalling the hook,
# and the hook works the same in every worktree of this repository.
#
# Only this repository is touched. If core.hooksPath is already configured, that
# path is used instead of .git/hooks, and this says so.
#
# Nothing is downloaded or installed. When the tools the checks need are missing,
# their names and the command that installs them are printed, and that is all.
#
set -euo pipefail

cd "$(dirname "$0")"
REPO_ROOT="$PWD"

# Marks a hook as ours, so it is safe to replace and to remove.
MARKER="# guacterm pre-commit hook"

usage() {
    sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'
}

UNINSTALL=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --uninstall) UNINSTALL=1 ;;
        -h|--help)
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
command -v swiftformat >/dev/null 2>&1 || missing+=(swiftformat)
command -v swiftlint >/dev/null 2>&1 || missing+=(swiftlint)

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

cat > "$HOOK" <<EOF
#!/bin/sh
$MARKER
# Installed by ./setup-dev.sh. The checks live in scripts/pre-commit.sh;
# edit that instead, it is the same script 'make check' runs.
exec "\$(git rev-parse --show-toplevel)/scripts/pre-commit.sh" "\$@"
EOF
chmod +x "$HOOK"

echo "==> Installed $HOOK"
echo "    every commit now runs scripts/pre-commit.sh first."
echo "    'make format' fixes formatting, 'git commit --no-verify' skips once."
