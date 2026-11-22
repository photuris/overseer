# overseer

An Agent Skill for running a multi-agent coding workflow: one
expensive, high-capability model plans, specifies, and reviews, while
cheaper agents do the implementation work, coordinating through files
instead of through the overseer as a message bus.

It runs in tmux, Herdr, or T3 Code, with Claude Code, Codex, or any
agent that loads Agent Skills as the overseer.

## What it catches

Give a feature to a coding agent and it reports "done, all tests
pass". The skill is built around the ways that report is wrong.

| What goes wrong | What the overseer does |
|-----------------|------------------------|
| The tests were not run, or not on the final code | It runs each acceptance command itself and puts the output in the task file. A transcript is not evidence. |
| A new test passes with or without the change | Before work starts, it runs each acceptance command on the untouched code. A check that already passes there is a defect in the spec. For each new test, the implementer names a one-line change to the code that makes the test fail, and the reviewer replays it. |
| The agent built something beside what was asked | Each task lists the files it may change. A change outside the list is a review finding. |
| The plan was wrong before any code existed | A plan critic reads the plan and the task files before you approve them. |
| Review goes in circles | Each finding has an id and a status. A rebuttal needs evidence. The number of open blocking findings must fall each round, or the overseer stops the loop and decides. |
| An agent stalls, or reports done with nothing committed | It checks the task file and `git log` before it believes a status, and samples the output of each working agent. |
| The session restarts and its context is gone | The plan, each task, each review round, and the run state are files in `.overseer/`. A new session reads them and continues. |
| Two runs collide in one repository | Each run holds a lease that names what it will change. |

The plan critic and the review rows need a reviewer in your profile.
The example profiles have one.

You decide at three points: you approve the plan, you settle a
deadlock the overseer cannot settle, and you accept the result. The
overseer decides everything else and tells you what it decided.

## What a run leaves behind

A run writes one folder in your repository. Git ignores it by
default: the overseer adds `.overseer/` to `.git/info/exclude`, a
local file, so your `.gitignore` does not change. To keep the folder
in history, tell the overseer at the start of a run. The names below
are made up; the layout and the formats are the real ones.

```
.overseer/
  active/2026-11-20-rate-limit.md    the lease: this run is live
  LESSONS.md                         what each run learned
  runs/2026-11-20-rate-limit/
    PLAN.md                          the plan you approved
    STATE.md                         who is running, what is done
    tasks/001-limiter-core.md        spec, acceptance, result, proof
    tasks/002-limiter-config.md
    review/plan.md                   the plan critic's findings
    review/round-1.md                review findings and replies
```

A task file is the whole contract with an implementer. This is part
of one after the task was accepted:

```markdown
# 001 limiter-core
Status: accepted
## Files
Allowed: src/limiter.py, tests/test_limiter.py
Read-only: src/config.py
## Acceptance
Command: uv run pytest tests/test_limiter.py -q
Expect: exit 0, "12 passed" (change check: fails at BASE)
## Result
BASE: 4e1f0a2. Commit: abc1234.
test_burst fails when limiter.py:41 reads 1 in place of `burst`. Ran it.
## Verification
$ uv run pytest tests/test_limiter.py -q
12 passed in 0.41s
```

A review round is a list of findings that each get a reply:

```markdown
### R1-01: Limiter ignores the burst setting

- file: src/limiter.py
- severity: blocking
- status: resolved

`src/limiter.py:41` reads `rate` and never reads `burst`, so a burst
of 20 is throttled like a burst of 1. Repro: `uv run pytest -k burst`.

- response: fixed in abc1234. The limiter now reads `burst` from
  config; `tests/test_limiter.py::test_burst` covers it.

---

verdict: changes
```

[`SKILL.md`](SKILL.md) is the full method.

## Install

One command installs the driver and the session launcher, clones the
skill, and writes an example profile file. The binaries are prebuilt,
so no compiler is needed. You need `git`, `curl`, and `jq`. The
driver files use `jq` in their commands.

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
   rules that the script printed. The script names the harness of the
   terminal it ran in. Change the name if you will use another
   (`tmux`, `herdr`, `hc`). See
   [Claude Code in auto mode](#claude-code-in-auto-mode-allow-the-spawn-commands).
4. Start tmux, or open a Herdr pane, and run `overseer`.
5. Under tmux, tell the agent that overseer mode is on: type
   `/overseer`, or "Load the overseer skill". Under Herdr the launcher
   marks the session itself.
6. Give the overseer an implementation task. It writes a plan and
   waits for your approval before it starts an implementer.

**T3 Code** needs no driver and no launcher. Clone the skill
([Manual install](#manual-install), step 1). Copy
[`resources/t3.example.toml`](resources/t3.example.toml) to
`~/.config/overseer/t3.toml` and edit it. Then type
`/overseer <profile>` in a T3 thread. The overseer needs `python3`
3.11 or later to read that file. [`resources/t3.md`](resources/t3.md)
has the details.

### Options

| `install.sh` | `install.ps1` | Effect |
|--------------|---------------|--------|
| `--with-judge` | `-WithJudge` | Also installs `overseer-judge`. The judge needs a TypeSafe API key, and it sends pane, task, and review text to that API. Add `judge = "overseer-judge"` to a profile to use it. |
| `--no-launch` | `-NoLaunch` | Skips the launcher and the profile file. You then set the roster variables by hand. |
| `--no-skill` | `-NoSkill` | Skips the skill clone. |

The piped form takes the same options: `... | sh -s -- --with-judge`.
On Windows, run the script from a clone of this repository:
`powershell -ExecutionPolicy Bypass -File install.ps1 -WithJudge`.

## Harnesses

The skill's mechanics are written against a small abstract interface —
`spawn`, `status`, `read`, `prompt`, `list`, `rename`, `interrupt`,
`notify`, `layout` — rather than any one terminal harness. Each
supported harness gets its own `resources/<harness>.md` file mapping
that interface onto real commands.

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
above.

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

**Windows** (PowerShell; Herdr and the Herdr desktop app only):

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

On Windows the command runs under `cmd /C`, where single quotes do
not quote: write `\"` around the prompt inside the TOML string.

Claude Code also takes the slash command there, `claude '/overseer'`;
use the sentence if your version shows it as plain text. The agent
takes one paid turn at startup and the roster check runs before you
type a task. The
[launcher README](https://github.com/photuris/overseer-launch#loading-the-skill-at-startup)
has the other agents and a lighter system-prompt variant.

## Update, and what the skill learns

Update the skill with `git -C ~/.claude/skills/overseer pull` (Codex:
`~/.agents/skills/overseer`). Run the install script again to update
the binaries. Each driver file names the oldest `multiplexer-driver`
it works with, and the overseer checks that at the start of a run. If
it tells you the driver is too old, run the install script again.

Releases of the skill are git tags, listed on the
[releases page](https://github.com/photuris/overseer/releases). The
install script gives you the newest commit. To stay on one release,
clone it by tag. The clone needs an empty destination, so run the
install script with `--no-skill`, or remove the directory first:

```sh
git clone --depth 1 --branch <tag> https://github.com/photuris/overseer ~/.claude/skills/overseer
```

In a bug report, give both versions:

```sh
git -C ~/.claude/skills/overseer log -1 --format='%h %cs'
multiplexer-driver --version
```

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
