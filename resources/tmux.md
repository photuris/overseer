# tmux driver

Concrete mapping of the overseer skill's abstract interface onto tmux,
via the [`overseer-driver`][overseer-driver] CLI (`--harness tmux`).
Install it once per machine (`go install
github.com/photuris/overseer-driver/cmd/overseer-driver@latest`, or a
prebuilt binary once published) — never improvise raw tmux syntax
instead; it exists precisely because that syntax has sharp edges
(literal-mode flags, blank-line padding, a server-restart race) this
CLI already found and fixed once.

[overseer-driver]: https://github.com/photuris/overseer-driver

Unlike Herdr, tmux has no concept of "agent" — only sessions, windows,
panes, and the text inside them — so `status` is a best-effort
approximation, not a lookup. Every other primitive is a thin, tested
wrapper; every driver-backed subcommand prints one JSON object to
stdout on success, and a nonzero exit means check stderr, not stdout.

## Primitive mapping

| Primitive | Command |
|-----------|---------|
| spawn | `overseer-driver spawn --harness tmux --name <name> -- <command...>` |
| split | `overseer-driver split --harness tmux --target <handle> --name <name> --direction right\|down -- <command...>` |
| status | `overseer-driver status --harness tmux --target <handle> [--patterns patterns.json]` |
| read | `overseer-driver read --harness tmux --target <handle> --lines N [--ansi]` |
| prompt | `overseer-driver prompt --harness tmux --target <handle> --text "<text>"` |
| list | `overseer-driver list --harness tmux` |
| rename | `overseer-driver rename --harness tmux --target <handle> --label <label>` |
| interrupt | `overseer-driver interrupt --harness tmux --target <handle> [--kill]` |
| notify | `overseer-driver notify --message "..." [--title "..."]` — no `--harness`; reaches the user, not tmux |

## Handles

A handle is always a full `session:window.pane` address (e.g.
`impl-003:1.2`), returned by `spawn`, `split`, and `list` alike —
never assume it is just the session name you passed to `--name`.
`rename` sets the pane's title only; the handle keeps working
afterward, no re-resolution needed.

## spawn vs. split

`spawn` isolates a new agent in its own session — the default, and
what you want for most implementers. `split` adds one alongside an
existing handle instead, sharing its window; use it for the topology
below, or whenever you deliberately want agents grouped rather than
isolated.

## Status: best-effort, not a lookup

tmux has no idea whether the process in a pane is idle, thinking, or
stuck; `status` pattern-matches recent output against a config you
supply, not an API tmux exposes:

```bash
overseer-driver status --harness tmux --target impl-003:1.1 --patterns patterns.json
```

```json
{"idle": ["\\$\\s*$"], "blocked": ["Trust this folder\\?"]}
```

Without `--patterns`, it always returns `{"status":"unknown",
"confidence":"none"}` — the honest answer when nothing has taught it
what a given tool's prompts look like. Write the patterns the first
time you point this at a new tool by inspecting one real `read`
first, never by guessing. Every response carries `confidence`
(`"none"` or `"heuristic"` under this driver, never `"native"`) — lean
on `read` more than `status`, and treat "unchanged output across two
reads" as the strongest signal you get.

## Dispatch

```bash
overseer-driver prompt --harness tmux --target impl-003:1.1 --text "Task ready: .overseer/tasks/003-rate-limit.md. Respond in that file."
```

`prompt` only sends and submits — it does not wait. Poll `read` or
`status` yourself afterward, per the dispatch ritual in the core
skill. Answering a plain tmux dialog (a y/n, a bare Enter) also goes
through `prompt` — tmux has no "reject while blocked" concept the way
Herdr does, so there is no special case here.

To tell a greyed-out prompt suggestion from typed input (dispatch
ritual step 3), read with styling preserved. Text after `ESC[2m` is
dim: a suggestion, not input. tmux can put the closing reset at the
start of the next line, so treat a dim span as ending at the line
break.

```bash
overseer-driver read --harness tmux --target <handle> --lines 12 --ansi
```

Two things `overseer-driver` does not wrap, both plain tmux:

```bash
# A dialog whose cursor starts on the refusing option (Claude Code's
# folder trust starts on "No, exit"): move first, then confirm.
tmux send-keys -t <handle> Down Enter

# The agent's resolved command line, when its banner has scrolled off.
pid=$(tmux display-message -p -t <handle> '#{pane_pid}')
ps -o args= -p "$pid" --ppid "$pid"
```

## List

```bash
overseer-driver list --harness tmux
```

Lists every pane on the tmux server, not just ones you spawned — a
shared machine may be running unrelated sessions. Filter by your own
naming convention rather than assuming every listed handle is yours.

## Interrupt

```bash
overseer-driver interrupt --harness tmux --target impl-003:1.1          # ask it to stop
overseer-driver interrupt --harness tmux --target impl-003:1.1 --kill   # hard stop
```

`--kill` closes only the target's own pane, never its whole
session/window — a session can hold sibling panes from other agents
via `split`.

## Notify

```bash
overseer-driver notify --message "Overseer: plan ready for approval" --title "Overseer"
```

tmux has no notification primitive; this shells out to the OS
(`notify-send`/`osascript`), best effort. Neither is guaranteed to
exist — a `{"sent":false}` response means treat `notify` as
unsupported and say the gate message directly in your own reply,
never silently skip the human-in-the-loop announcement.

## Topology

```bash
overseer-driver spawn --harness tmux --name impl-003 -- claude --model opus
overseer-driver split --harness tmux --target impl-003:1.1 --name impl-004 --direction right -- claude --model opus
overseer-driver split --harness tmux --target impl-003:1.1 --name impl-005 --direction down -- claude --model opus
```

Give the reviewer its own `spawn`, never a `split` into an
implementer's window — mirrors the isolation the core skill asks for.
