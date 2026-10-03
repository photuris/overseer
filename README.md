# overseer

An Agent Skill for running a multi-agent coding workflow: one
expensive, high-capability model plans, specifies, and reviews, while
cheaper agents do the implementation work, coordinating through files
instead of through the overseer as a message bus.

The skill's mechanics are written against a small abstract interface —
`spawn`, `status`, `read`, `prompt`, `list`, `rename`, `interrupt`,
`notify`, `layout` — rather than any one terminal harness. Each
supported harness gets its own `resources/<harness>.md` file mapping
that interface onto real commands.

## Harnesses

| Harness | Driver |
|---------|--------|
| tmux | [multiplexer-driver](https://github.com/photuris/multiplexer-driver) |
| Herdr | [multiplexer-driver](https://github.com/photuris/multiplexer-driver) |
| T3 Code (0.0.46+) | T3 orchestrator MCP tools ([`resources/t3.md`](resources/t3.md)) |

`multiplexer-driver` is a small CLI that implements the deterministic
half of the mapping (the actual commands), so the skill itself only
needs to carry the judgment calls an LLM has to make. It runs on Linux
and macOS for both harnesses, and on Windows for Herdr. See Install
below.

An optional judge role — typed verdicts on pane state, task-file
lint, and review classification — is documented in
`resources/judge.md` and backed by
[overseer-judge](https://github.com/photuris/overseer-judge).

An optional launcher starts a session from a named profile of role
commands, in place of setting the roster variables by hand:
[overseer-launch](https://github.com/photuris/overseer-launch).

| Binary | Needed | Role |
|--------|--------|------|
| [`multiplexer-driver`](https://github.com/photuris/multiplexer-driver) | required for tmux and Herdr | runs the harness commands |
| [`overseer-judge`](https://github.com/photuris/overseer-judge) | optional | typed verdicts for the judge role |
| [`overseer`](https://github.com/photuris/overseer-launch) | optional | starts a session from a profile |

## Install

Four pieces: the skill, the driver (required), the judge (optional),
and the session launcher (optional). Each is one copy-paste command,
and one setup script installs the three binaries together. No
toolchain is needed: the binaries are prebuilt.

### 1. The skill itself

Agent Skills have no package registry — installing one means putting
its directory where your harness looks for skills. There's no
`/plugin install` shortcut for a plain skill repo like this one (that
command needs a `.claude-plugin/marketplace.json` the repo doesn't
have); a clone is the standard, fully-supported way in.

**Claude Code** — user-level (all projects):

```sh
git clone https://github.com/photuris/overseer ~/.claude/skills/overseer
```

Project-local instead (`git clone ... .claude/skills/overseer` from
the project root) works the same way if you'd rather scope it to one
repo.

**Codex** — Agent Skills is an [open spec][agentskills] Codex also
reads, from `~/.agents/skills/` at user level (or
`<repo>/.agents/skills/` for one project):

```sh
git clone https://github.com/photuris/overseer ~/.agents/skills/overseer
```

Restart the harness (or start a new session) if it doesn't pick the
skill up immediately.

[agentskills]: https://agentskills.io

### All three binaries at once

The setup script in this repository runs the installers from steps 2
to 4 in turn and prints the versions. Use it in place of those steps.

**Linux and macOS:**

```sh
curl --proto '=https' --tlsv1.2 -LsSf https://raw.githubusercontent.com/photuris/overseer/main/install.sh | sh
```

**Windows** (PowerShell):

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/photuris/overseer/main/install.ps1 | iex"
```

The binaries go in `~/.local/bin` (`%USERPROFILE%\.local\bin` on
Windows). If an installer added that directory to your `PATH`, open a
new terminal before you use them.

To skip an optional binary, run the script from your clone of the
skill with a flag: `sh install.sh --no-judge` or `--no-launch`, and on
Windows `powershell -ExecutionPolicy Bypass -File install.ps1
-NoJudge` or `-NoLaunch`. The piped form takes the same flags:
`... | sh -s -- --no-judge`.

The script does not install the skill (step 1) and does not write a
profile file. With the launcher installed, run `overseer init` next,
as step 4 describes.

### 2. The driver (required)

T3 Code users can skip this step.

`multiplexer-driver` does the deterministic half of the work (spawn,
read, prompt, wait, list, rename, interrupt, status) for whatever
harness you drive agents through. Install the prebuilt binary:

**Linux and macOS:**

```sh
curl --proto '=https' --tlsv1.2 -LsSf https://github.com/photuris/multiplexer-driver/releases/latest/download/multiplexer-driver-installer.sh | sh
```

**Windows** (PowerShell; Herdr only):

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://github.com/photuris/multiplexer-driver/releases/latest/download/multiplexer-driver-installer.ps1 | iex"
```

Both put the binary in `~/.local/bin` (`%USERPROFILE%\.local\bin` on
Windows) and add that directory to your `PATH` if needed. If the
installer added it, open a new terminal, or run the reload command the
installer prints, before the next step. Check with
`multiplexer-driver --version`.
Archives and checksums are on the
[releases page](https://github.com/photuris/multiplexer-driver/releases/latest);
with a Rust toolchain you can also build from source:
`cargo install --git https://github.com/photuris/multiplexer-driver --locked`.

#### Claude Code in auto mode: allow the spawn commands

Do this once if the overseer runs as Claude Code in auto mode. Skip it
otherwise.

In auto mode a classifier checks each shell command before it runs. It
denies a command that starts an agent with approvals turned off, such
as a reviewer set to `codex --yolo`. The run then stops at the first
spawn. Two allow rules in `~/.claude/settings.json` prevent that:

```json
{
  "permissions": {
    "allow": [
      "Bash(multiplexer-driver --harness herdr pane spawn:*)",
      "Bash(multiplexer-driver --harness herdr pane split:*)"
    ]
  }
}
```

Add the two lines to the `allow` array you already have. For tmux,
write `--harness tmux` in both. A run that uses worktrees (three or
more implementers at once under Herdr) starts agents with
`herdr agent start`, so add `"Bash(herdr agent start:*)"` for that
case.

Add the rules yourself, before the first run. Claude Code does not let
the overseer change its own permissions, even at your request.

The rules skip the classifier for every command the driver starts.
The roster commands you set are then the only limit on what runs.

### 3. The judge (optional)

`overseer-judge` turns a few recurring judgment calls (pane state,
task-file lint, review typing) into fast, typed verdicts. Only needed
if you enable it — see `resources/judge.md`. It reads its API key
from `TYPESAFE_API_KEY` or `~/.config/jev`. Install the prebuilt
binary:

**Linux and macOS:**

```sh
curl --proto '=https' --tlsv1.2 -LsSf https://github.com/photuris/overseer-judge/releases/latest/download/overseer-judge-installer.sh | sh
```

**Windows** (PowerShell):

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://github.com/photuris/overseer-judge/releases/latest/download/overseer-judge-installer.ps1 | iex"
```

Both put the binary in `~/.local/bin` (`%USERPROFILE%\.local\bin` on
Windows) and add that directory to your `PATH` if needed. If the
installer added it, open a new terminal, or run the reload command the
installer prints, before the next step. Check with
`overseer-judge --version`.
Archives and checksums are on the
[releases page](https://github.com/photuris/overseer-judge/releases/latest);
with a Rust toolchain you can also build from source:
`cargo install --git https://github.com/photuris/overseer-judge --locked`.

### 4. The session launcher (optional)

Without this step you set the roster by hand before starting the
overseer: `OVERSEER_IMPLEMENTER`, `OVERSEER_REVIEWER`, and
`OVERSEER_JUDGE` as full commands, plus `HERDR_OVERSEER=1` under
Herdr. That keeps working unchanged.

[overseer-launch](https://github.com/photuris/overseer-launch) replaces
the hand-set variables with named profiles in one TOML file, so
`overseer claude` inside a Herdr pane or tmux window exports the roster
and starts that profile's overseer there. Install the prebuilt binary:

**Linux and macOS:**

```sh
curl --proto '=https' --tlsv1.2 -LsSf https://github.com/photuris/overseer-launch/releases/latest/download/overseer-launch-installer.sh | sh
```

**Windows** (PowerShell):

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://github.com/photuris/overseer-launch/releases/latest/download/overseer-launch-installer.ps1 | iex"
```

Both put the `overseer` binary in `~/.local/bin`
(`%USERPROFILE%\.local\bin` on Windows) and add that directory to
your `PATH` if needed. If the installer added it, open a new
terminal, or run the reload command the installer prints, before the
next step. Check with `overseer --version`. Archives and checksums are
on the
[releases page](https://github.com/photuris/overseer-launch/releases/latest);
with a Rust toolchain you can also build from source:
`cargo install --git https://github.com/photuris/overseer-launch --locked`.

Then write the example file and edit it:

```sh
overseer init          # ~/.config/overseer/profiles.toml
```

The format is in [`resources/profiles.example.toml`](resources/profiles.example.toml):
one table per profile naming the `overseer`, `implementer`, and
optional `reviewer` and `judge` commands, each a full command with a
pinned model, never a shell alias. `overseer <name>` launches one;
`overseer` alone launches the file's `default`; `overseer <name>
--print` shows what would launch.

To have the overseer load this skill at launch, instead of when the
first implementation task arrives, end the profile's `overseer`
command with a starting prompt. `claude`, `codex`, and `pi` all take
one as a trailing argument:

```toml
[profiles.claude]
overseer = "claude 'Load the overseer skill and confirm the roster.'"
```

Claude Code also takes the slash command there, `claude '/overseer'`;
use the sentence if your version shows it as plain text. The agent
takes one paid turn at startup and the roster check runs before you
type a task. The
[launcher README](https://github.com/photuris/overseer-launch#loading-the-skill-at-startup)
has the other agents and a lighter system-prompt variant.

## License

MIT — see [LICENSE](LICENSE).
