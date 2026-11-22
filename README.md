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

| Harness | Status | Platforms | Driver |
|---------|--------|-----------|--------|
| tmux | Supported | Linux, macOS | [multiplexer-driver](https://github.com/photuris/multiplexer-driver) |
| Herdr | Supported | Linux, macOS, Windows | [multiplexer-driver](https://github.com/photuris/multiplexer-driver) |
| Herdr desktop app (hc) | Supported | Linux, macOS, Windows | [multiplexer-driver](https://github.com/photuris/multiplexer-driver) |
| T3 Code (0.1.1+) | Supported | Where T3 Code runs | T3 orchestrator MCP tools ([`resources/t3.md`](resources/t3.md)) |
| cmux | Experimental | macOS | [multiplexer-driver](https://github.com/photuris/multiplexer-driver) |
| tuios | Experimental | Linux (the only one tested) | [multiplexer-driver](https://github.com/photuris/multiplexer-driver) |

- **Supported:** the maintainer runs real sessions on this harness. A
  problem with it is a bug, so report it.
- **Experimental:** the driver was checked against one version of the
  harness and has had little use in full runs. It can fail in ways
  the driver file does not describe. Reports are welcome, with no
  promise of a fix.

If you are new, start with tmux or Herdr.

`multiplexer-driver` is a small CLI that implements the deterministic
half of the mapping (the actual commands), so the skill itself only
needs to carry the judgment calls an LLM has to make. See Install
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
| [`multiplexer-driver`](https://github.com/photuris/multiplexer-driver) | required for every harness except T3 Code | runs the harness commands |
| [`overseer-judge`](https://github.com/photuris/overseer-judge) | optional | typed verdicts for the judge role |
| [`overseer`](https://github.com/photuris/overseer-launch) | optional | starts a session from a profile |

## Install

One command installs the driver and the session launcher, clones the
skill, and writes an example profile file. No toolchain is needed: the
binaries are prebuilt.

**Linux and macOS:**

```sh
curl --proto '=https' --tlsv1.2 -LsSf https://raw.githubusercontent.com/photuris/overseer/main/install.sh | sh
```

**Windows** (PowerShell):

```powershell
powershell -ExecutionPolicy Bypass -c "irm https://raw.githubusercontent.com/photuris/overseer/main/install.ps1 | iex"
```

The script does three things:

1. It installs `multiplexer-driver` and `overseer` in `~/.local/bin`
   (`%USERPROFILE%\.local\bin` on Windows).
2. It clones the skill into `~/.claude/skills/overseer` for Claude
   Code, into `~/.agents/skills/overseer` for Codex, or into both. It
   uses the agents it finds on the machine, and Claude Code when it
   finds none.
3. It writes the example profile file to
   `~/.config/overseer/profiles.toml`
   (`%APPDATA%\overseer\profiles.toml` on Windows).

The script does not change a skill directory or a profile file that
already exists. Run it again to update the binaries.

### First run

1. Open a new terminal if an installer added `~/.local/bin` to your
   `PATH`.
2. Edit the profile file. Keep the profiles whose agent commands you
   have, and set `default` to one of them.
   [The session launcher](#4-the-session-launcher-optional) describes
   the format.
3. If the overseer runs as Claude Code in auto mode, add the two allow
   rules that the script printed. See
   [Claude Code in auto mode](#claude-code-in-auto-mode-allow-the-spawn-commands).
4. Start tmux, or open a Herdr pane, and run `overseer`.
5. Give the overseer an implementation task. It loads the skill, writes
   a plan, and waits for your approval before it starts an implementer.

### Options

| `install.sh` | `install.ps1` | Effect |
|--------------|---------------|--------|
| `--with-judge` | `-WithJudge` | Also installs `overseer-judge`. The judge needs a TypeSafe API key, and it sends pane, task, and review text to that API. Add `judge = "overseer-judge"` to a profile to use it. |
| `--no-launch` | `-NoLaunch` | Skips the launcher and the profile file. You then set the roster variables by hand. |
| `--no-skill` | `-NoSkill` | Skips the skill clone. |

The piped form takes the same options: `... | sh -s -- --with-judge`.
On Windows, run the script from a clone of this repository:
`powershell -ExecutionPolicy Bypass -File install.ps1 -WithJudge`.

## Manual install

The setup script runs the steps below. Use them to install one piece
by hand, or to see what the script does.


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
cmux, tuios, or the Herdr desktop app, write that harness name (`tmux`,
`cmux`, `tuios`, `hc`) in both. Under hc, also allow
`"Bash(hc keys:*)"`, which answers startup dialogs. A run that uses worktrees (three or
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

## Update, and what the skill learns

Update the skill with `git -C ~/.claude/skills/overseer pull` (Codex:
`~/.agents/skills/overseer`). Run the install script again to update
the binaries.

The skill never writes what it learns into its own files, so the pull
stays clean. Each run
appends its lessons to `.overseer/LESSONS.md` in the repository it
worked on. When the same problem costs two runs, the overseer writes
it as a rule in a file that is yours:

```
~/.config/overseer/rules.md          # Windows: %APPDATA%\overseer\rules.md
```

The overseer reads that file at the start of every run, in every
repository. You can edit or delete a rule at any time. If a rule would
help other people, open an issue or a pull request with it.

## License

MIT — see [LICENSE](LICENSE).
