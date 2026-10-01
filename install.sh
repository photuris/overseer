#!/bin/sh
# Installs the overseer skill's companion binaries from their latest
# GitHub releases:
#
#   multiplexer-driver   required   runs the harness commands
#   overseer-judge       optional   typed verdicts for the judge role
#   overseer             optional   starts a session from a profile
#
# Each binary has its own installer, published with its release. This
# script only runs those installers in turn, then prints the versions.
# It does not install the skill itself: clone this repository into your
# agent's skills directory for that (see README.md).
#
# Usage: install.sh [--no-judge] [--no-launch]
#
# Piped: curl -LsSf <raw url of this file> | sh -s -- --no-judge

set -eu

usage() {
    cat <<'USAGE'
Usage: install.sh [--no-judge] [--no-launch]

Installs multiplexer-driver, overseer-judge, and overseer into
~/.local/bin from their latest GitHub releases.

  --no-judge    skip overseer-judge
  --no-launch   skip overseer (the session launcher)
  -h, --help    print this help
USAGE
}

judge=1
launch=1

for arg in "$@"; do
    case $arg in
        --no-judge) judge=0 ;;
        --no-launch) launch=0 ;;
        -h | --help)
            usage
            exit 0
            ;;
        *)
            echo "install.sh: unknown option: $arg" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if ! command -v curl >/dev/null 2>&1; then
    echo "install.sh: curl is required" >&2
    exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# Runs the release installer of the GitHub project photuris/$1. The
# installer is downloaded to a file first: `curl | sh` would hide a
# failed download, because sh exits 0 on empty input. `--retry` covers
# a transient 5xx from the release host (seen once in CI).
install() {
    echo "==> $1"
    curl --proto '=https' --tlsv1.2 -LsSf --retry 3 \
        "https://github.com/photuris/$1/releases/latest/download/$1-installer.sh" \
        -o "$tmp/$1-installer.sh"
    sh "$tmp/$1-installer.sh"
}

# Prints the version of binary $1. A new binary may not be on PATH in
# this shell yet, so the install directory is tried first.
version() {
    if [ -x "$HOME/.local/bin/$1" ]; then
        "$HOME/.local/bin/$1" --version
    elif command -v "$1" >/dev/null 2>&1; then
        "$1" --version
    else
        echo "install.sh: $1 was not found after its installer ran" >&2
        exit 1
    fi
}

install multiplexer-driver
[ "$judge" = 1 ] && install overseer-judge
[ "$launch" = 1 ] && install overseer-launch

echo "==> installed"
version multiplexer-driver
[ "$judge" = 1 ] && version overseer-judge
[ "$launch" = 1 ] && version overseer

echo
echo "If an installer added ~/.local/bin to your PATH, open a new terminal"
echo "before you use these."
if [ "$launch" = 1 ]; then
    echo "Next: run 'overseer init' to write the example profile file."
fi
