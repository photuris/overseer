# Herdr driver

Concrete mapping of the overseer skill's abstract interface onto
Herdr, via the [`overseer-driver`][overseer-driver] CLI (`--harness
herdr`). Install it once per machine (`go install
github.com/photuris/overseer-driver/cmd/overseer-driver@latest`, or a
prebuilt binary from its [releases page][overseer-driver-releases]).
This file assumes the `herdr` skill
for general pane/tab/worktree mechanics and covers anything
overseer-driver does not wrap (below) with raw `herdr` commands
instead — never improvise syntax beyond what's documented here.

[overseer-driver]: https://github.com/photuris/overseer-driver
[overseer-driver-releases]: https://github.com/photuris/overseer-driver/releases/latest

## Signal and preconditions

```bash
test "${HERDR_ENV:-}" = 1 && test "${HERDR_OVERSEER:-}" = 1
```

`HERDR_ENV=1` means you are running inside Herdr at all; `HERDR_OVERSEER=1`
means this session is the overseer for the current run. Both must be
set before you orchestrate anything.

## Primitive mapping

| Primitive | Command |
|-----------|---------|
| spawn | `overseer-driver spawn --harness herdr --name <name> -- <command...>` |
| split | `overseer-driver split --harness herdr --target <handle> --name <name> --direction right\|down -- <command...>` |
| status | `overseer-driver status --harness herdr --target <handle>` — always native, no patterns needed |
| read | `overseer-driver read --harness herdr --target <handle> --lines N [--ansi]` |
| prompt | `overseer-driver prompt --harness herdr --target <handle> --text "<text>"` |
| list | `overseer-driver list --harness herdr` |
| rename | `overseer-driver rename --harness herdr --target <handle> --label <label>` |
| interrupt | `overseer-driver interrupt --harness herdr --target <handle> [--kill]` |
| notify | `overseer-driver notify --message "..." [--title "..."] [--sound request]` — prefers Herdr's own notification automatically |

Every driver-backed subcommand prints one JSON object to stdout on
success; a nonzero exit means check stderr — Herdr's own error code
and message (e.g. `agent_blocked`) pass through verbatim.

`spawn` and `split` have one more outcome. When the pane was created
but the agent did not finish starting, they exit nonzero and still
print the handle:

```json
{"handle":"w1:p7","started":false}
```

Success prints `"started":true`. No stdout at all means the pane was
never created. A `started:false` pane is yours to deal with: `read`
it first. A startup dialog (folder trust) is the usual cause, so
answer it (see Dialogs) and carry on. If the command simply exited or
never came up, close the pane with `interrupt --kill`. Never retry a
`spawn` without doing one or the other, or the tabs pile up.

## Handles

A handle is always a Herdr pane ID (`w1:p2`) — Herdr's own stable
public identifier, valid as a target whether or not the pane holds a
Herdr-recognized agent, and unchanged by `rename` (which sets the
pane's label only).

## Known-kind agents vs. raw fallback

`spawn`/`split` only know how to launch a fixed list of agent kinds
(`claude`, `codex`, `gemini`, `pi`, … — see `herdr agent start
--help` for the exact set) as `command[0]`; that's when you get a
Herdr-recognized agent with native `status` and working `prompt`.
Anything else — a shell alias or wrapper around one of those tools,
say — is launched as a raw process instead, automatically, with no
extra steps on your part: just `spawn`/`split` it by its real command
as usual. The tradeoff: `spawn` does not wait for an agent to appear
in a raw-fallback pane. Herdr's detection is screen-based, so an alias
that launches a known agent (`claude-opus`, `codex`) is normally
recognized a few seconds later, and `status` and `prompt` then work
(seen across one full run). Poll `status` until it reads `idle`
before the first `prompt`. A program whose UI Herdr does not know (a
plain shell, a script) is never recognized: `read` it and answer it
with raw `herdr pane run <pane> "<text>"` / `herdr pane send-text`
instead (see the `herdr` skill).

## Roster resolution

`OVERSEER_IMPLEMENTER` may be a kind+model shorthand rather than a
runnable command (seen twice: `claude-opus`). Honor the intent:
`overseer-driver spawn --harness herdr --name impl-003 -- claude
--model opus` and record the banner's model in the roster; do not
treat the unresolvable shorthand as "unset". When the banner has
scrolled off (seen in two runs), the pane's process shows the
resolved command line, e.g. `claude --model claude-opus-5`:

```bash
herdr pane process-info --pane <handle>
```

Always pass `--add-dir <path>` (as part of the trailing `-- <command
...>`) for every outside repository a task's Read-only list names;
without it the first outside read blocks on a permission prompt (seen
in three consecutive runs).

## Dialogs

`prompt` cannot answer a folder-trust or approval dialog — Herdr
itself rejects a real prompt submission with `agent_blocked` while
one is showing, by design, and overseer-driver's `prompt` does not
work around that. Read the pane (`overseer-driver read`) to see the
dialog, then answer it with raw key presses Herdr's own CLI covers.
Look at where the dialog's cursor sits before you press Enter. Codex's
folder-trust dialog starts on "Yes, continue", so `enter` accepts it.
Claude Code's starts on "No, exit", so a bare `enter` quits the
agent: move down first.

```bash
herdr agent send-keys impl-003 enter        # cursor already on "yes"
herdr agent send-keys impl-003 down enter   # cursor starts on "no"
```

`status` reporting `blocked` is your signal to look. `agent start`
has reported an error while the launched tool was still drawing its
banner (seen in two consecutive runs) — if a `spawn`/`split` call
fails right after launch, `read` before trusting the error.

## Dispatch

```bash
overseer-driver read --harness herdr --target impl-003 --lines 20
overseer-driver prompt --harness herdr --target impl-003 --text "Task ready: .overseer/tasks/003-rate-limit.md. Respond in that file."
```

`read` returns plain text by default. To tell an agent's greyed-out
prompt suggestion from typed input (dispatch ritual step 3), read
with styling preserved:

```bash
overseer-driver read --harness herdr --target impl-003 --lines 12 --ansi
```

Text between `ESC[2m` and the next reset is dim: a suggestion, not
input.

`prompt` only sends and submits — it does not wait, unlike raw
Herdr's own `agent prompt --wait`. Poll `status` afterward (native and
reliable here) in bounded intervals per the dispatch ritual in the
core skill, rather than reaching for `--wait` yourself outside this
CLI.

## Topology

```bash
resp=$(overseer-driver spawn --harness herdr --name impl-003 -- claude --model opus)
overseer-driver split --harness herdr --target "$(echo "$resp" | jq -r .handle)" --name impl-004 --direction right -- claude --model opus
overseer-driver split --harness herdr --target "$(echo "$resp" | jq -r .handle)" --name impl-005 --direction down -- claude --model opus
```

- Give the reviewer its own `spawn` (own tab), never a `split` into an
  implementer's tab; the reviewer never shares.
- Name agents by task: `impl-003`, `verify-003`, `review-r2`,
  `critic`.
- At every `STATE.md` update, report the same state to the sidebar so
  the user can read it without opening a pane — not wrapped by
  overseer-driver, call Herdr directly:

```bash
herdr pane report-metadata "$HERDR_PANE_ID" --source overseer --token task=003 --token phase=review
```

  Report `task` and `phase` on implementer panes too (`phase` is one of
  `impl`, `verify`, `review`, `fix`, `accepted`).

## Isolation

```bash
overseer-driver list --harness herdr
```

Given disjoint tasks, two implementers may share the main checkout
only when this shows no other live session working in that repo.
Another live session in the repo, or three or more concurrent
implementers, means one Herdr worktree each, and you own the merge.

## Notify

```bash
overseer-driver notify --message "Overseer: plan ready for approval" --title "Overseer" --sound request
```

`--sound request` is for the three human-in-the-loop gates and
nothing else. Herdr can report success while showing nothing at all —
if the user has notifications turned off, the response comes back
`{"sent":false,"reason":"disabled",...}`; that is not a failure to
retry, it means say the gate message directly in your own reply too.
