# overseer — agent instructions

This repo holds one Agent Skill: `SKILL.md` plus its `resources/`
files. It's meant to be consumed by an agent harness's skill-loading
mechanism (Claude Code's Skill tool, or an equivalent), not run
directly.

## Layout

- `SKILL.md` — the abstract methodology and primitive interface
  (`spawn`/`status`/`read`/`prompt`/`list`/`rename`/`interrupt`/
  `notify`/`layout`). Harness-agnostic; do not add harness-specific
  commands here.
- `resources/<harness>.md` — one file per harness, mapping the
  abstract interface onto that harness's real commands. `tmux.md`,
  `herdr.md`, `hc.md`, `cmux.md`, and `tuios.md` point at the [multiplexer-driver][driver]
  CLI, which implements the mapping deterministically instead of
  leaving it to LLM prose. `cmux.md` and `tuios.md` are experimental:
  each has a note at its top, and the README's Harnesses table gives
  every harness a status. Move one to supported only after full runs
  on it, and change the note and the table together. `judge.md` documents the optional judge role, backed by
  [overseer-judge][judge].
- `resources/spec-pitfalls.md` — the rules that apply to one kind of
  task, grouped by kind. `SKILL.md` tells the overseer to read it
  before it writes a task file. A rule that applies to every task
  stays in `SKILL.md`. A new rule for one kind of task goes here, in
  the group it fits.
- `resources/t3.md` — the T3 Code driver. Unlike `tmux.md` and
  `herdr.md`, it uses no CLI: the overseer runs as a T3 thread and
  calls T3's orchestrator MCP tools directly.
- `resources/t3.example.toml` — the T3 roster format. The skill reads
  `t3.toml` itself. overseer-launch does not read it.
- `resources/profiles.example.toml` — the session-profile format read
  by the optional [overseer-launch][launch] binary (`overseer
  <profile>`), which sets the roster variables before the skill runs.
  It is a twin of that repo's `profiles.example.toml`; change both.
  Not part of the primitive interface.
- `install.sh`, `install.ps1` — setup scripts. They run the companion
  binaries' own release installers in turn (the judge only on
  request), clone this skill into the agent's skills directory, and
  run `overseer init` when there is no profile file. They never change
  a skill directory or a profile file that exists. Keep the two
  scripts the same in flags and behavior.
  `.github/workflows/install.yml` runs both for real on Linux, macOS,
  and Windows; it is the only test of `install.ps1`, so do not merge a
  change to either script without a green run. A binary added to or
  removed from the README's install steps changes both scripts and the
  workflow too.

[driver]: https://github.com/photuris/multiplexer-driver
[judge]: https://github.com/photuris/overseer-judge
[launch]: https://github.com/photuris/overseer-launch

## Keep in sync

A change to the abstract interface (a new primitive, a changed
contract) is a change to every `resources/<harness>.md` file, and
usually to `multiplexer-driver`'s `Driver` trait (`src/driver.rs`) and
its command map too. Don't
edit one side without checking the others.

## Versions

- Each `multiplexer-driver` file names the minimum driver version it
  needs, in its **Version** paragraph. When a file starts to use a
  command or a flag from a newer driver release, raise the minimum in
  that file in the same commit.
- A release of this skill is a tag `vMAJOR.MINOR.PATCH` on `main`,
  with a GitHub release. Raise MAJOR when a change breaks a ledger, a
  roster, or a profile file that exists. Raise MINOR for a new rule
  or a new driver. Raise PATCH for a correction.

## Lessons

A run never writes a lesson into this skill. It appends to
`.overseer/LESSONS.md` in the repository it worked on, and promotes a
repeated friction to the user's local rules file
(`~/.config/overseer/rules.md`). A rule moves from that file into
`SKILL.md` or `resources/spec-pitfalls.md` only by a commit here,
written by hand: remove project names, client names, and run ids that
mean nothing to a stranger first.

## Conventions

- Frontmatter is `name` + `description` only, third person, starting
  with "Use when…" — trigger conditions, never a workflow summary.
- No harness-specific tool references in `SKILL.md` itself (no
  "Claude Code's Skill tool", no MCP server names) — that content
  belongs in a `resources/` file if it's genuinely harness-specific.
