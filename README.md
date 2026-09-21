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
| tmux | [overseer-driver](https://github.com/photuris/overseer-driver) |
| Herdr | [overseer-driver](https://github.com/photuris/overseer-driver) |

`overseer-driver` is a small Go CLI that implements the deterministic
half of the mapping (the actual commands), so the skill itself only
needs to carry the judgment calls an LLM has to make. See Install
below.

An optional judge role — typed verdicts on pane state, task-file
lint, and review classification — is documented in
`resources/judge.md` and backed by
[overseer-judge](https://github.com/photuris/overseer-judge).

## Install

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

`overseer-driver` is the CLI that does the deterministic half of the
work (spawn/read/prompt/list/rename/interrupt/status) for whatever
harness you're driving agents through — tmux or Herdr today.

```sh
go install github.com/photuris/overseer-driver/cmd/overseer-driver@latest
```

No Go toolchain? Grab a prebuilt binary from the
[releases page](https://github.com/photuris/overseer-driver/releases/latest)
and put it on your `PATH`.

### 3. The judge (optional)

`overseer-judge` turns a few recurring judgment calls (pane state,
task-file lint, review typing) into fast, typed verdicts. Only needed
if you enable it — see `resources/judge.md`.

```sh
go install github.com/photuris/overseer-judge/cmd/overseer-judge@latest
```

Prebuilt binaries: same pattern, on its
[releases page](https://github.com/photuris/overseer-judge/releases/latest).
It reads its API key from `TYPESAFE_API_KEY` or `~/.config/jev`.

## License

MIT — see [LICENSE](LICENSE).
