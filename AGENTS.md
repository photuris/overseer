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
  abstract interface onto that harness's real commands. `tmux.md` and
  `herdr.md` point at the [multiplexer-driver][driver] CLI, which
  implements the mapping deterministically instead of leaving it to
  LLM prose. `judge.md` documents the optional judge role, backed by
  [overseer-judge][judge].
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
- `install.sh`, `install.ps1` — setup scripts that run the three
  companion binaries' own release installers in turn. They hold no
  install logic of their own. `.github/workflows/install.yml` runs
  both for real on Linux, macOS, and Windows; it is the only test of
  `install.ps1`, so do not merge a change to either script without a
  green run. A binary added to or removed from the README's install
  steps changes both scripts and the workflow too.

[driver]: https://github.com/photuris/multiplexer-driver
[judge]: https://github.com/photuris/overseer-judge
[launch]: https://github.com/photuris/overseer-launch

## Keep in sync

A change to the abstract interface (a new primitive, a changed
contract) is a change to every `resources/<harness>.md` file, and
usually to `multiplexer-driver`'s `Driver` trait (`src/driver.rs`) and
its command map too. Don't
edit one side without checking the others.

## Conventions

- Frontmatter is `name` + `description` only, third person, starting
  with "Use when…" — trigger conditions, never a workflow summary.
- No harness-specific tool references in `SKILL.md` itself (no
  "Claude Code's Skill tool", no MCP server names) — that content
  belongs in a `resources/` file if it's genuinely harness-specific.
