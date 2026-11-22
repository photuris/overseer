#!/bin/sh
# Sets up the overseer skill on this machine:
#
#   multiplexer-driver   required   runs the harness commands
#   overseer             optional   starts a session from a profile
#   the skill            optional   cloned into your agent's skills directory
#   overseer-judge       opt-in     typed verdicts for the judge role
#
# Each binary has its own installer, published with its release. This
# script runs those installers in turn, clones the skill, writes the
# example profile file if there is none, and prints the next steps.
#
# Usage: install.sh [--with-judge] [--no-launch] [--no-skill]
#
# Piped: curl -LsSf <raw url of this file> | sh -s -- --with-judge

set -eu

usage() {
    cat <<'USAGE'
Usage: install.sh [--with-judge] [--no-launch] [--no-skill]

Installs multiplexer-driver and overseer into ~/.local/bin from their
latest GitHub releases, clones the skill into your agent's skills
directory, and writes the example profile file if there is none.

  --with-judge  also install overseer-judge (needs a TypeSafe API key,
                and sends pane, task, and review text to that API)
  --no-launch   skip overseer (the session launcher) and the profile file
  --no-skill    skip the skill clone
  -h, --help    print this help
USAGE
}

judge=0
launch=1
skill=1

for arg in "$@"; do
    case $arg in
        --with-judge) judge=1 ;;
        --no-launch) launch=0 ;;
        --no-skill) skill=0 ;;
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

if [ "$skill" = 1 ] && ! command -v git >/dev/null 2>&1; then
    echo "install.sh: git is required to clone the skill (--no-skill skips it)" >&2
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

# Prints the skills directories to install into, one per line: Codex's
# when Codex is present, Claude Code's when Claude Code is present or
# when neither agent was found.
skill_dirs() {
    found=0

    if command -v codex >/dev/null 2>&1 || [ -d "$HOME/.codex" ]; then
        echo "$HOME/.agents/skills"
        found=1
    fi

    if [ "$found" = 0 ] || command -v claude >/dev/null 2>&1 ||
        [ -d "$HOME/.claude" ]; then
        echo "$HOME/.claude/skills"
    fi
}

# Clones the skill into skills directory $1. A path that already exists
# (a clone, a symbolic link to a checkout, a copy) is never changed.
install_skill() {
    dest="$1/overseer"

    if [ -e "$dest" ] || [ -L "$dest" ]; then
        echo "$dest already exists, left as it is"
        echo "  (update a clone with: git -C $dest pull)"
        return
    fi

    mkdir -p "$1"
    git clone --quiet --depth 1 https://github.com/photuris/overseer "$dest"
    echo "$dest"
}

install multiplexer-driver
[ "$launch" = 1 ] && install overseer-launch
[ "$judge" = 1 ] && install overseer-judge

if [ "$skill" = 1 ]; then
    echo "==> skill"
    skill_dirs | while IFS= read -r dir; do
        install_skill "$dir"
    done
fi

# The launcher's default location (its `default_path`). `overseer init`
# refuses to replace a file, so it runs only when there is none.
profiles="${XDG_CONFIG_HOME:-$HOME/.config}/overseer/profiles.toml"

if [ "$launch" = 1 ]; then
    echo "==> profiles"
    if [ -e "$profiles" ]; then
        echo "$profiles already exists, left as it is"
    else
        "$HOME/.local/bin/overseer" init >/dev/null
        echo "$profiles"
    fi
fi

echo "==> installed"
version multiplexer-driver
[ "$launch" = 1 ] && version overseer
[ "$judge" = 1 ] && version overseer-judge

# The allow rules name the harness. Herdr and its desktop app set a
# variable in every pane; anything else is taken to be tmux.
harness=tmux
[ "${HERDR_ENV:-}" = 1 ] && harness=herdr
[ -n "${HC_TERMINAL_ID:-}" ] && harness=hc

echo
echo "Next:"
echo "  1. Open a new terminal if an installer added ~/.local/bin to your PATH."
if [ "$launch" = 1 ]; then
    echo "  2. Edit $profiles: keep the agent commands you have."
    echo "  3. Inside tmux or Herdr, run: overseer"
else
    echo "  2. Set OVERSEER_IMPLEMENTER and OVERSEER_REVIEWER, then start your agent"
    echo "     inside tmux or Herdr."
fi
echo
echo "If the overseer runs as Claude Code in auto mode, add these to"
echo "permissions.allow in ~/.claude/settings.json before the first run:"
echo "  \"Bash(multiplexer-driver --harness $harness pane spawn:*)\","
echo "  \"Bash(multiplexer-driver --harness $harness pane split:*)\""
