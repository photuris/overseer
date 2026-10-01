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

`multiplexer-driver` is a small CLI that implements the deterministic
half of the mapping (the actual commands), so the skill itself only
needs to carry the judgment calls an LLM has to make. It runs on Linux
and macOS for both harnesses, and on Windows for Herdr. See Install
below.

An optional judge role — typed verdicts on pane state, task-file
lint, and review classification — is documented in
`resources/judge.md` and backed by
[overseer-judge](https://github.com/photuris/overseer-judge).

## Install

Four pieces: the skill, the driver (required), the judge (optional),
and the session launcher (optional). Each is one copy-paste command.
No toolchain is needed: the binaries are prebuilt.

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
Windows) and add that directory to your `PATH` if needed. Check with
`multiplexer-driver --version`. Archives and checksums are on the
[releases page](https://github.com/photuris/multiplexer-driver/releases/latest);
with a Rust toolchain you can also build from source:
`cargo install --git https://github.com/photuris/multiplexer-driver --locked`.

### 3. The judge (optional)

`overseer-judge` turns a few recurring judgment calls (pane state,
task-file lint, review typing) into fast, typed verdicts. Only needed
if you enable it — see `resources/judge.md`. It reads its API key
from `TYPESAFE_API_KEY` or `~/.config/jev`. Install the prebuilt
binary into the same `~/.local/bin` (install the driver first, so that
directory is on your `PATH`):

**Linux and macOS:**

```sh
v=$(curl -fsSL https://api.github.com/repos/photuris/overseer-judge/releases/latest | sed -n 's/.*"tag_name": *"v\([^"]*\)".*/\1/p')
os=$(uname -s | tr '[:upper:]' '[:lower:]'); arch=$(uname -m)
case $arch in x86_64) arch=amd64;; aarch64|arm64) arch=arm64;; esac
mkdir -p ~/.local/bin
curl -fsSL "https://github.com/photuris/overseer-judge/releases/download/v$v/overseer-judge_${v}_${os}_${arch}.tar.gz" | tar -xz -C ~/.local/bin overseer-judge
```

**Windows** (PowerShell):

```powershell
$v = (Invoke-RestMethod https://api.github.com/repos/photuris/overseer-judge/releases/latest).tag_name.TrimStart('v')
$arch = if ($env:PROCESSOR_ARCHITECTURE -eq 'ARM64') { 'arm64' } else { 'amd64' }
$tmp = Join-Path $env:TEMP 'overseer-judge'
Invoke-WebRequest "https://github.com/photuris/overseer-judge/releases/download/v$v/overseer-judge_${v}_windows_$arch.zip" -OutFile "$tmp.zip"
Expand-Archive "$tmp.zip" -DestinationPath $tmp -Force
$bin = Join-Path $HOME '.local\bin'
New-Item -ItemType Directory -Force $bin | Out-Null
Copy-Item (Join-Path $tmp 'overseer-judge.exe') $bin
```

With a Go toolchain:
`go install github.com/photuris/overseer-judge/cmd/overseer-judge@latest`.

### 4. Session profiles (optional)

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

Then write the example file and edit it:

```sh
overseer init          # ~/.config/overseer/profiles.toml
```

The format is in [`resources/profiles.example.toml`](resources/profiles.example.toml):
one table per profile naming the `overseer`, `implementer`, and
optional `reviewer` and `judge` commands, each a full command with a
pinned model, never a shell alias. `overseer <name>` launches one;
`overseer` alone launches the file's `default`; `overseer <name>
--print` shows what would launch. With a Rust toolchain:
`cargo install --git https://github.com/photuris/overseer-launch --locked`.

## License

MIT — see [LICENSE](LICENSE).
