# tmux driver

Concrete mapping of the overseer skill's abstract interface onto tmux,
via the [`multiplexer-driver`][md] CLI (`--harness tmux`). Install it
once per machine (see the README's Install section) — never improvise
raw tmux syntax instead; it exists precisely because that syntax has
sharp edges (literal-mode flags, a trailing `;` parsed as a command
separator, delimiters in listing output, a server-restart race) this
CLI already found and fixed.

[md]: https://github.com/photuris/multiplexer-driver

Unlike Herdr, tmux has no concept of "agent" — only sessions, windows,
panes, and the text inside them — so `status` is a best-effort
approximation, not a lookup. Every other primitive is a thin, tested
wrapper. Every subcommand prints JSON to stdout on success (one object,
or JSON Lines for `pane list`). On failure the exit code is nonzero and
the last stderr line is `{"error":{"type":…,"message":…}}`; branch on
the exit code (`2` usage, `3` tmux not running, `4` no such pane, `7`
wait timed out).

Set `MULTIPLEXER_DRIVER_HARNESS=tmux` once per shell to drop
`--harness tmux` from every call; the commands below spell it out.

## Primitive mapping

| Primitive | Command |
|-----------|---------|
| spawn | `multiplexer-driver --harness tmux pane spawn --name <name> -- <command...>` |
| split | `multiplexer-driver --harness tmux pane split <handle> --name <name> --direction right\|down -- <command...>` |
| status | `multiplexer-driver --harness tmux pane status <handle> --patterns patterns.json` |
| read | `multiplexer-driver --harness tmux pane read <handle> --lines N [--ansi]` |
| prompt | `multiplexer-driver --harness tmux pane prompt <handle> --text "<text>"` |
| wait | `multiplexer-driver --harness tmux pane wait <handle> --timeout 12m --patterns patterns.json [--until idle\|working\|blocked]...` |
| list | `multiplexer-driver --harness tmux pane list` |
| rename | `multiplexer-driver --harness tmux pane rename <handle> --label <label>` |
| interrupt | `multiplexer-driver --harness tmux pane interrupt <handle>` (Ctrl-C) or `pane kill <handle>` (hard stop) |
| notify | `multiplexer-driver notify --message "..." [--title "..."]` — no `--harness`; reaches the user, not tmux |

## Handles

A handle is a tmux pane ID such as `%12`, returned by `spawn`,
`split`, and `pane list` alike. It is stable across renames and window
renumbering — never substitute the name you passed to `--name`.
`rename` sets the pane's label only; the handle keeps working.

## spawn vs. split

`spawn` opens the agent in a new window of the current tmux session
(run the overseer inside tmux; outside it, pass `--workspace <session
id>`). `split` adds a pane beside an existing handle, sharing its
window; use it for the topology below, or whenever you deliberately
want agents grouped rather than in separate windows.

A label or name must not contain control characters (tabs, newlines):
the driver rejects them with exit 2, as tmux does for window names.

## Claude Code auto mode

When you run as Claude Code in auto mode, a classifier checks each
shell command. It denies a spawn whose command starts an agent with
approvals off (seen with `codex --yolo`, reason "Create Unsafe
Agents"). The user clears this with allow rules in
`~/.claude/settings.json`. The README's driver section lists them:

```json
"Bash(multiplexer-driver --harness tmux pane spawn:*)",
"Bash(multiplexer-driver --harness tmux pane split:*)"
```

- An allow rule is a prefix match on the whole command. Issue every
  `pane spawn` and `pane split` as a bare command that starts with
  `multiplexer-driver --harness tmux`. A spawn inside an `&&`
  chain, after a `cd`, or after a heredoc does not match, and the
  classifier denies it again (seen in one run). Do not use the
  `MULTIPLEXER_DRIVER_HARNESS` short form for these two commands.
- You cannot add the rules. The classifier denies an edit to your own
  settings as self-modification, and a user request does not clear
  that. On the first denied spawn, stop, give the user the rules, and
  wait.
- Do not retry a denied spawn with other quoting or through another
  command. That is the outcome the classifier denied.

## Status: best-effort, not a lookup

tmux has no idea whether the process in a pane is idle, thinking, or
stuck; `status` pattern-matches recent output against a config you
supply, not an API tmux exposes:

```bash
multiplexer-driver --harness tmux pane status %3 --patterns patterns.json
```

```json
{"idle": ["\\$\\s*$"], "blocked": ["Trust this folder\\?"]}
```

How the match works, since each point has caused a wrong pattern:

- The patterns run against the pane's last 15 lines taken as one
  string. `$` anchors to the end of that whole tail, which after a
  command finishes is the prompt line, not the command's output. Use
  `(?m)` for per-line anchors (`(?m)^DONE$`).
- `blocked` is checked first, then `idle`; `working` means neither
  matched. A pane parked at a prompt your `idle` pattern misses reads
  `working` forever.
- The pane echoes what you type, so a pattern that matches your own
  dispatch text fires before the command runs. Match the agent's
  prompt or a marker that only its output can produce.

Without `--patterns`, it always returns `{"status":"unknown",
"confidence":"none"}` — the honest answer when nothing has taught it
what a given tool's prompts look like — and `pane wait` refuses to run
(exit 2). Write the patterns the first time you point this at a new
tool by inspecting one real `read` first, never by guessing. Every
response carries `confidence` (`"none"` or `"heuristic"` under this
driver, never `"native"`) — lean on `read` more than `status`, and
treat "unchanged output across two reads" as the strongest signal you
get.

## Roster

The roster arrives as environment variables, each a full shell
command: `OVERSEER_IMPLEMENTER` (implementer), `OVERSEER_REVIEWER`
(reviewer), and `OVERSEER_JUDGE` (judge). Confirm them:

```bash
printf '%s\n' "${OVERSEER_IMPLEMENTER:?not set}" "${OVERSEER_REVIEWER:-none}" "${OVERSEER_JUDGE:-none}"
```

Roster commands are normally literal: the optional `overseer`
launcher sets them from a profile of full commands (format in
`resources/profiles.example.toml`). A shorthand that still arrives (a
kind+model pair, a shell alias, a wrapper function) means the user
bypassed the launcher. Honor the intent rather than treating it as
"unset": resolve it through whatever general-purpose launch method
this driver offers and record the real, resolved command in
`STATE.md`.

After every `spawn`, read the model from the agent's own banner and
record it in the `STATE.md` roster. When the banner has scrolled off,
read the agent's resolved command line (the `ps` snippet in Dispatch).

## Dispatch ritual

Startup dialogs (folder trust, update prompts, imports) and composer
races eat first prompts on most harnesses. For each dispatch:

1. `read` the target's recent output first — is a dialog sitting at
   the prompt?
2. `prompt` the task-ready nudge, waiting for idle with a generous
   timeout.
3. If the wait reports the prompt as stalled, or returns with the agent still
   `idle`: `read` again. A dialog means answer it (see Dispatch). No dialog,
   and the input box holds the text you sent: it is sitting unsubmitted, so
   resubmit it (e.g. a bare Enter), wait briefly, confirm `status` now reads
   `working`. Text in the input box that you did not send is usually the
   agent's own greyed-out prompt suggestion, not typed input, and a plain-text
   `read` cannot tell them apart. Read the pane with styling preserved (see
   Dispatch). Dim text means the box is empty: do not press Enter on it and do
   not spend a step clearing it. Still not `working`: the dispatch failed —
   `read` the transcript, fix the cause (crashed agent, API error, wrong
   working directory), and re-dispatch from the top. Never assume a dispatch
   took.

Then follow the core skill's dispatch ritual.

## Dispatch

```bash
multiplexer-driver --harness tmux pane prompt %3 --text "Task ready: .overseer/runs/<run-id>/tasks/003-rate-limit.md. Respond in that file."
```

`prompt` only sends and submits — it does not wait. With patterns
configured, confirm the dispatch took and then wait in one bounded
interval, per the dispatch ritual and health watch in the core skill:

```bash
multiplexer-driver --harness tmux pane wait %3 --until working --timeout 60s --patterns patterns.json
multiplexer-driver --harness tmux pane wait %3 --timeout 12m --patterns patterns.json   # idle or blocked
```

Exit `7` from the second call is the health-check point: `read` the
pane, judge it, and wait again. A wait that ends prints the status
JSON and exits 0 for `blocked` as well as `idle`, so check `.status`
before treating it as done. A task that finishes within one poll
(about half a second) can slip past the first wait; check the artifact
before treating its exit `7` as a failed dispatch. Never wait straight for `idle` right
after `prompt` — the agent is still idle in the instant before it
starts, so that wait returns at once. Without patterns, poll `read`
instead. Answering a plain tmux dialog (a y/n, a bare Enter) also goes
through `prompt` — tmux has no "reject while blocked" concept the way
Herdr does, so there is no special case here.

To tell a greyed-out prompt suggestion from typed input (dispatch
ritual step 3), read with styling preserved. Text after `ESC[2m` is
dim: a suggestion, not input. tmux can put the closing reset at the
start of the next line, so treat a dim span as ending at the line
break.

```bash
multiplexer-driver --harness tmux pane read %3 --lines 12 --ansi | jq -r .output
```

`pane read` prints `{"handle":…,"output":…}`; the pane text is in
`output`.

Two things `multiplexer-driver` does not wrap, both plain tmux:

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
multiplexer-driver --harness tmux pane list
```

Prints one JSON record per pane on the tmux server (`handle`,
`workspace_label`, `tab_label`, `label`, `cwd`, `agent`), not just the
panes you spawned — a shared machine may be running unrelated
sessions. Filter with `jq`, by your labels or by `cwd` (see Isolation
in the core skill):

```bash
multiplexer-driver --harness tmux pane list \
  | jq -c --arg repo "$PWD" 'select(.cwd != null and (.cwd | startswith($repo)) and .handle != env.TMUX_PANE) | {handle, label, agent, cwd}'
```

This sees one tmux server. An overseer in another harness shows up
only as a lease in `.overseer/active/`; read that too before two
implementers share the main checkout.

## Interrupt

```bash
multiplexer-driver --harness tmux pane interrupt %3   # ask it to stop (Ctrl-C)
multiplexer-driver --harness tmux pane kill %3        # hard stop
```

`kill` closes only the target's own pane, never its whole
session/window — a window can hold sibling panes from other agents
via `split`.

## Notify

```bash
multiplexer-driver notify --message "Overseer: plan ready for approval" --title "Overseer"
```

tmux has no notification primitive; this shells out to the OS
(`notify-send`/`osascript`), best effort. Neither is guaranteed to
exist — a `{"sent":false}` response means treat `notify` as
unsupported and say the gate message directly in your own reply,
never silently skip the human-in-the-loop announcement.

## Topology

```bash
h=$(multiplexer-driver --harness tmux pane spawn --name impl-003 -- claude --model opus | jq -r .handle)
multiplexer-driver --harness tmux pane split "$h" --name impl-004 --direction right -- claude --model opus
multiplexer-driver --harness tmux pane split "$h" --name impl-005 --direction down -- claude --model opus
```

Give the reviewer its own `spawn`, never a `split` into an
implementer's window — mirrors the isolation the core skill asks for.
