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

[driver]: https://github.com/photuris/multiplexer-driver
[judge]: https://github.com/photuris/overseer-judge

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
