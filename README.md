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
needs to carry the judgment calls an LLM has to make. See its README
for install instructions.

An optional judge role — typed verdicts on pane state, task-file
lint, and review classification — is documented in
`resources/judge.md` and backed by
[overseer-judge](https://github.com/photuris/overseer-judge).

## Install

Copy this repo's contents (or symlink it) into wherever your harness
loads Agent Skills from. For Claude Code, that's a directory under
`~/.claude/skills/`.

## License

MIT — see [LICENSE](LICENSE).
