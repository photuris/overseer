# tuios driver

Concrete mapping of the overseer skill's abstract interface onto
tuios, via the [`multiplexer-driver`][md] CLI (`--harness tuios`).
Install it once per machine (see the README's Install section). The
driver's tuios support is tested on Linux only. This file is verified
against a local `tuios version dev` build. Never improvise `tuios`
syntax beyond what this file documents; the few raw `tuios` commands
below exist because the driver does not wrap them.

[md]: https://github.com/photuris/multiplexer-driver

Set `MULTIPLEXER_DRIVER_HARNESS=tuios` once per shell to drop
`--harness tuios` from every call; the commands below spell it out.
Inside a tuios pane the driver talks to that pane's session; from
anywhere else, see Session and daemon.

## Signal and preconditions

```bash
test "${TUIOS_ENV:-}" = 1 && test -n "${TUIOS_SESSION:-}"
```

`TUIOS_ENV=1` means you are running inside a tuios pane at all, and
`TUIOS_SESSION` names the session you run in. `TUIOS_WINDOW_ID` is
your own handle. Overseer mode is on when the user invoked `/overseer`
in this session. tuios has no `HERDR_OVERSEER` equivalent, and the
launcher sets none.

## Primitive mapping

| Primitive | Command |
|-----------|---------|
| spawn | `multiplexer-driver --harness tuios pane spawn --name <name> --cwd <dir> -- <command...>` (no `--workspace`) |
| split | `multiplexer-driver --harness tuios pane split <handle> --name <name> --direction right\|down -- <command...>` (needs an attached client and tiling on) |
| status | `multiplexer-driver --harness tuios pane status <handle> [--patterns patterns.json]` — native when the pane reports an agent state, heuristic with `--patterns` otherwise, `unknown` with confidence `none` when neither is available |
| read | `multiplexer-driver --harness tuios pane read <handle> --lines N [--ansi]` |
| prompt | `multiplexer-driver --harness tuios pane prompt <handle> --text "<text>"` |
| wait | `multiplexer-driver --harness tuios pane wait <handle> --timeout 12m [--until idle\|working\|blocked]... [--patterns patterns.json]` |
| list | `multiplexer-driver --harness tuios pane list` |
| rename | `multiplexer-driver --harness tuios pane rename <handle> --label <label>` |
| interrupt | `multiplexer-driver --harness tuios pane interrupt <handle>` (Ctrl-C) or `pane kill <handle>` (hard stop) |
| kill | `multiplexer-driver --harness tuios pane kill <handle>` (closes that one window) |
| notify | `multiplexer-driver notify --message "..." [--title "..."]` — the driver's usual fallbacks; tuios has no desktop notification of its own and `--sound` is ignored |

Every subcommand prints JSON to stdout on success (one object, or JSON
Lines for `pane list`). On failure the exit code is nonzero and the
last stderr line is `{"error":{"type":…,"message":…}}`, with tuios's
own error text inside `message`. Branch on the exit code: `2` usage,
`3` the daemon is not running or the session does not exist, `4` no
such window, `5` unsupported on tuios (a refused `pane split`,
`workspace create`, `workspace tag`), `6` started false (below), `7`
wait timed out.

`spawn` and `split` have one more outcome. The driver never checks
that the agent finished starting. It exits `6` and still prints the
handle when the window exists but typing the command line into it
failed:

```json
{"handle":"846d8a9c-0969-4434-8468-8c7da0f32f0d","started":false}
```

Success prints `"started":true`. A `started:false` window is live:
read the stderr error to see which step failed, `read` the window,
then repair it by hand or kill it. If the command line never reached
the shell, send it with `pane prompt <handle> --text "<command
line>"`. Otherwise close the window with `pane kill <handle>`. A
dialog never causes exit `6` here; dialogs show up on `read` after a
`started:true` (see Dialogs). A nonzero exit with no stdout means no
window was created, so a retry does not pile up windows.

## Handles

A handle is a window UUID, such as
`846d8a9c-0969-4434-8468-8c7da0f32f0d`. It stays valid across rename
and split. The window index that `tuios list-windows` prints shifts
when an earlier window closes, and a name is only a label, so never
store or pass either as a handle. Your own handle is
`$TUIOS_WINDOW_ID`.

## Spawn types the line into a shell

`spawn` opens a new window in the session's current workspace, with
the shell and the working directory `--cwd` names, without taking the
user's focus. Then it types the command as one shell line into that
fresh interactive shell and presses Enter. A wrapper or an alias works
if that shell sees it. With no command, you get just the shell.
`pane spawn --workspace` is a usage error (exit `2`): a tuios session
has nine fixed numbered workspaces and `workspace create` is
unsupported (exit `5`). The window is created even on a headless
session, one no client is attached to.

There is no agent-kind launcher, so tuios does not recognize an agent
by the command name `spawn` was given; Status explains how it learns
of one.

Always pass `--add-dir <path>` (as part of the trailing `-- <command
...>`) for every outside repository a task's Read-only list names;
without it the first outside read blocks on a permission prompt (seen
in three consecutive runs).

## Roster resolution

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
the window's foreground process shows the resolved command line:

```bash
tuios explain-agent-detect -s "$TUIOS_SESSION" -w <handle> --json | jq -c .process.argv
```

It prints the argv as a JSON array. While the window shows a plain
shell, it prints the shell. Then `read` the pane again right after the
agent's next reply: Claude Code and Codex print the model in their
status line.

## Status

Three cases, three commands:

```bash
# (a) A pane that reports an agent state: native, no patterns needed.
multiplexer-driver --harness tuios pane status <handle>

# (b) A pane without a state, with a patterns file: heuristic.
multiplexer-driver --harness tuios pane status <handle> --patterns patterns.json

# (c) A pane without a state, no patterns file: unknown, confidence none.
multiplexer-driver --harness tuios pane status <handle>
```

In case (c), `pane wait` exits `2` (usage) until you pass
`--patterns`.

Native status is the agent state tuios holds for the window. The
mapping is:

| tuios state | `status` | `confidence` |
|-------------|----------|--------------|
| `working` | `working` | `native` |
| `idle`, `done` | `idle` | `native` |
| `needs_input`, `errored` | `blocked` | `native` |
| `none`, `unknown` | heuristic with `--patterns`, else `unknown` | `heuristic` or `none` |

A pane gets a state from three sources, and `native` covers all of
them:

- The agent's own hooks, which the user wires once per machine with
  `tuios integration install <harness>` (Claude Code, Codex, and
  others; `tuios doctor agents` checks it). A hook reports a prompt or
  tool call as `working`, an approval request as `needs_input`, and
  the end of a turn as `done`.
- tuios's process detector (source `detect`), which needs no hooks.
  It recognizes known agent CLIs by the window's foreground process
  and publishes `working`. The driver reports that as `working` with
  confidence `native` and lists the agent kind, so `native` does not
  mean the agent's hooks spoke. It cannot see an agent in a container
  or a VM. It shows that a process exists, not that it accepted a
  dispatch: a detected agent can read `working` while a dialog or an
  unsubmitted prompt sits in its input row. Keep the prompt-took check
  of the dispatch ritual (the artifact, or a changed `read`).
- tuios's screen rules (source `screen`), which also need no hooks.
  They read the window's screen tail and can classify an approval menu
  as `needs_input`, which the driver reports as `blocked` with
  confidence `native`. Its title rules (source `osc`) read the window
  title instead and can report `working`. A screen or title rule is a
  guess: it can miss a prompt, and a pane can read `working` or
  `unknown` with a dialog up. `read` the pane before every dispatch
  regardless.

To see what the detector made of a window:

```bash
tuios explain-agent-detect -s "$TUIOS_SESSION" -w <handle> --json | jq -c '{matched, harness_id, matched_rule, evidence}'
```

Never run `integration install` yourself: it edits the user's agent
configuration. `unknown` with confidence `none` does not tell you why:
the agent may be absent, undetected (a container, a launcher the
detector does not know), or reporting nothing. If a Claude Code or
Codex pane reads `unknown` and you expected a state, `read` it, check
`tuios doctor agents`, and tell the user what is missing. Use
`--patterns` meanwhile.

`blocked` covers two states. `needs_input` means the agent waits on a
prompt or an approval, and `errored` means its last turn failed. So
`blocked` on tuios means "read the pane", not "a dialog is up".

A pane that neither hooks nor the detector report on has no agent
state. Then `status` is `unknown` with confidence `none`, and
`pane wait` refuses to run. Pass `--patterns`, written from one real
`read` and never guessed:

```json
{"idle": ["❯\\s*$"], "blocked": ["Trust this folder\\?"]}
```

How the match works, since each point has caused a wrong pattern:

- The patterns run against the window's last 15 lines taken as one
  string. `$` anchors to the end of that whole tail, not to each line.
  Use `(?m)` for per-line anchors (`(?m)^DONE$`).
- `blocked` is checked first, then `idle`; `working` means neither
  matched. A window parked at a prompt your `idle` pattern misses
  reads `working` forever.
- The window echoes what you type, so a pattern that matches your own
  dispatch text fires before the agent runs. Match the agent's prompt
  or a marker that only its output can produce.

Every response carries `confidence`: `native`, `heuristic`, or `none`
(unknown status, no patterns), never two in one answer. Under a
heuristic status, lean on `read` more than `status`, and treat
"unchanged output across two reads" as the strongest signal you get.

## Dispatch ritual

Startup dialogs (folder trust, update prompts, imports) and composer
races eat first prompts on most harnesses. For each dispatch:

1. `read` the target's recent output first — is a dialog sitting at
   the prompt?
2. `prompt` the task-ready nudge, waiting for idle with a generous
   timeout.
3. If the wait reports the agent still `idle`: `read` again. A dialog
   means answer it (see Dialogs). No dialog, and the input row holds
   the text you sent: it is sitting unsubmitted, so press Enter with
   `tuios send-keys -s "$TUIOS_SESSION" -w <handle> Enter`, wait
   briefly, and confirm `working`. Text in the input row that you did
   not send is usually the agent's own greyed-out prompt suggestion,
   not typed input, and a plain-text `read` cannot tell them apart.
   Read the pane with styling preserved (see Dispatch). Dim text means
   the row is empty: do not press Enter on it and do not spend a step
   clearing it. Still not `working`: the dispatch failed — `read` the
   transcript, fix the cause (crashed agent, API error, wrong working
   directory), and re-dispatch from the top. Never assume a dispatch
   took.

Then follow the core skill's dispatch ritual.

## Dispatch

```bash
multiplexer-driver --harness tuios pane read <handle> --lines 20
multiplexer-driver --harness tuios pane prompt <handle> --text "Task ready: .overseer/runs/<run-id>/tasks/003-rate-limit.md. Respond in that file."
```

`prompt` types the text verbatim with `send-text`, then presses Enter
as a separate step, so backslashes, `$HOME`, and quotes arrive
unchanged. Never type prompt text with `tuios send-keys`: it splits
its argument on spaces and commas, so `echo hello` arrives as
`echohello`.

`read` returns plain text by default. To tell an agent's greyed-out
prompt suggestion from typed input (dispatch ritual step 3), read with
styling preserved:

```bash
multiplexer-driver --harness tuios pane read <handle> --lines 12 --ansi
```

Text between `ESC[2m` and the next reset is dim: a suggestion, not
input.

`pane read` prints `{"handle":…,"output":…}`; the pane text is in
`output` (`… | jq -r .output`). The read covers the scrollback, so
`--lines N` returns N lines even when the window is shorter. A line
longer than the window is broken at the window's width, so a long
value can span two lines.

`prompt` only sends and submits — it does not wait. Confirm the
dispatch took (ritual step 3), then wait in one bounded interval of
the health watch. For a pane that reports a state:

```bash
multiplexer-driver --harness tuios pane wait <handle> --until working --timeout 60s
multiplexer-driver --harness tuios pane wait <handle> --timeout 12m   # idle or blocked
```

For a pane without a state, add the patterns file to both (without it
both calls exit `2`):

```bash
multiplexer-driver --harness tuios pane wait <handle> --until working --timeout 60s --patterns patterns.json
multiplexer-driver --harness tuios pane wait <handle> --timeout 12m --patterns patterns.json   # idle or blocked
```

Exit `7` from the first call means the prompt did not take: go back to
ritual step 3. Exit `7` from the second is the health-check point:
`read` the pane, judge it, check file progress, and wait again. A wait
that ends prints the status JSON and exits 0 for `blocked` as well as
`idle`, so check `.status` before treating it as done. A task that
finishes within one poll (about half a second) can slip past the first
wait; check the artifact before treating its exit `7` as a failed
dispatch. Never wait straight for `idle` right after `prompt` — the
agent is still idle in the instant before it starts, so that wait
returns at once. Do not use tuios's own `wait-for` or `ask-agent`; the
driver's wait behaves the same on every harness.

## Dialogs

`prompt` types text and presses Enter; it does not choose a menu
option, and it does not check the pane's state first: it typed into a
pane on `needs_input` without complaint. So never `prompt` a pane on
`needs_input`, and never type at it blindly. Your text would answer
its prompt, and that can approve what it asked for. `read` the pane to
see the dialog, then answer it with key presses. Do not use
`ask-agent` for this: it refuses a pane on `needs_input` and types
nothing.

Look at where the dialog's cursor sits before you press Enter. Claude
Code's folder-trust dialog starts on "No, exit", so a bare `Enter`
quits the agent: move down first. `send-keys` takes all its keys as
one quoted argument, split on spaces and commas; a second argument is
an error and sends nothing.

```bash
tuios send-keys -s "$TUIOS_SESSION" -w <handle> "down enter"
```

Codex's folder-trust dialog starts on "Yes, continue", so a bare
`Enter` accepts it:

```bash
tuios send-keys -s "$TUIOS_SESSION" -w <handle> Enter
```

A misspelled key (`Dwon`) is refused and nothing is sent. `read` once
more after the keys to confirm the dialog is gone.

A trust dialog appears before the agent's hooks run, so only a screen
rule can mark it, and a screen rule can miss it: `pane status` may
read `working` or `unknown` for it. After every spawn, `read` once
before the first prompt.

## Retiring a Claude session

```bash
multiplexer-driver --harness tuios pane prompt <handle> --text /exit
multiplexer-driver --harness tuios pane read <handle> --lines 6
```

Poll `pane read` every two seconds for up to twenty seconds until the
output holds the line `Resume this session with:` (Claude prints it
on exit) and, two seconds after it first appears, has not changed.
That is the exit check. A status of `idle` or `unknown` is not a
check, because an agent at its prompt shows both while it runs.

If twenty seconds pass without that line, or with the line but output
that keeps changing, send `pane interrupt <handle>` twice, 0.3 s apart
(Claude's exit chord), `read` once more, then kill anyway and record
in `STATE.md` that the session was killed without a clean exit. Then:

```bash
multiplexer-driver --harness tuios pane kill <handle>
```

`pane kill` closes that window and nothing else. A second `kill` of
the same handle exits `4`.

## Isolation

```bash
tuios list-agents --all-sessions --json \
  | jq -c --arg repo "$PWD" '.agents[] | select((.cwd // "") | startswith($repo)) | select(.window_id != env.TUIOS_WINDOW_ID) | {session, window_id, name, harness_id, state, cwd}'
```

This finds every window in every session of this daemon that tuios has
identified as an agent (by hooks, process detection, or screen
rules), with its
state and working directory. `pane list` reaches only one session (see
Session and daemon), so do not use it for this check. A window nothing
has identified is not listed, whether it is a plain shell or an agent
the detector missed, so run a second, conservative check. List every
other such window in every session, then `read` each one with its own
session:

```bash
tuios list-agents --all-sessions --all --json | jq -r '.agents[] | select((.harness_id // "") == "") | select(.window_id != env.TUIOS_WINDOW_ID) | "\(.session) \(.window_id)"'
multiplexer-driver --harness tuios --session <session> pane read <handle> --lines 10
```

Output that shows an agent's input box or banner (Claude Code's `❯`
row with its footer, Codex's `› Ask Codex`, a `pi` prompt) is a live
agent of unknown repository. Treat it as another live session in this
repo (worktrees, no shared checkout) unless its visible cwd or title
clearly names a different directory. A plain shell prompt is not a
session.

Given disjoint tasks, two implementers may share the main checkout
only when the first filter prints nothing (or only your own
implementers), the second check finds no live agent, and
`.overseer/active/` holds no lease but yours. Both checks cover every
session of this tuios daemon. A standalone agent in another session
has no lease, so the checks are the only way to see it; an overseer in
T3 Code, Herdr, or tmux, or a daemon with another `XDG_RUNTIME_DIR`,
shows up only as a lease, if at all. Another live session in the
repo, another lease, or three or more concurrent implementers, means
one worktree each, and you own the merge.

Create each worktree with plain git, then spawn the implementer in it.
Do not use `tuios worktree`; it is out of scope for this driver.

```bash
git worktree add <path> -b task/003 main
multiplexer-driver --harness tuios pane spawn --name impl-003 --cwd <path> -- <command>
```

A gitignored ledger does not exist in a new worktree. Do not symlink
it. Claude Code refuses a file reached through a symlink that
resolves outside its working directories, and neither `--add-dir` nor
a permission allow rule lifts that check (tested 2026-10-03; the
symlink cost manual prompt answers in two runs).

- Start the implementer with `--add-dir` naming the main checkout's
  absolute `.overseer` path, and name every ledger file by its
  absolute path in every nudge and brief.
- `--add-dir` takes every following argument up to the next flag as
  a directory, so a "positional" prompt placed after it is swallowed.
  Put it after the other flags, and never directly before a prompt
  argument.
- Copy whatever untracked install the task needs (a `node_modules`,
  say) before the implementer starts.
- For a non-Claude implementer, use that tool's own equivalent and
  confirm one ledger write works before the first dispatch.

A worktree implementer's nudge names the task file by absolute path
(`resources/t3.md` "Ledger paths" does the same for T3):

```
Task ready: /abs/main/checkout/.overseer/runs/<run-id>/tasks/003-rate-limit.md.
Respond in that file.
```

## Topology

Issue each command bare, with no `h=$(...)` capture: the auto-mode
allow rules match a bare command only.

```bash
multiplexer-driver --harness tuios pane spawn --name impl-003 --cwd "$PWD" -- claude --model sonnet
# prints {"handle":"<uuid>","started":true}; copy <uuid> below
multiplexer-driver --harness tuios pane split <uuid> --name impl-004 --direction right -- claude --model sonnet
multiplexer-driver --harness tuios pane split <uuid> --name impl-005 --direction down -- claude --model sonnet
```

- `spawn` works with no client attached. `split` does not: tuios
  needs an attached client and tiling on, and refuses otherwise. The
  driver passes the refusal through as exit `5` with tuios's own text
  (a headless session says to attach a client; a session with tiling
  off says "tiling is not enabled"). It never enables tiling. On exit
  `5`, fall back to `spawn` for that agent, or ask the user to attach
  and turn tiling on.
- A split window inherits the target's working directory; `--cwd` on
  `split` is ignored. To put an implementer in another directory (a
  worktree), use `spawn --cwd`.
- A worktree is one per agent, made with plain `git worktree add` and
  a `spawn` with `--cwd` (see Isolation).
- Give the reviewer its own `spawn`, never a `split` next to an
  implementer; the reviewer never shares.
- Name agents by task: `impl-003`, `verify-003`, `review-r2`,
  `critic`.
- tuios shows each window's agent state itself, so there is no extra
  sidebar call for `STATE.md` updates. Keep `STATE.md` as the record.

## Notify

```bash
multiplexer-driver notify --message "Overseer: plan ready for approval" --title "Overseer"
```

tuios's own `notify` sends a push to the user's phone, not a desktop
alert, so the driver does not use it. The command takes the driver's
usual fallbacks and ignores `--harness`: inside Herdr, Herdr's
notification; otherwise `notify-send` on Linux or `osascript` on
macOS. `--sound` is ignored here. A response of `"sent":false` is not
a failure to retry, and neither is a nonzero exit when `notify-send`
cannot reach a desktop (seen as exit `1`, type `unexpected`); say the
gate message directly in your own reply too.

## Claude Code auto mode

When you run as Claude Code in auto mode, a classifier checks each
shell command. It denies a spawn whose command starts an agent with
approvals off (seen with `codex --yolo`, reason "Create Unsafe
Agents"). The user clears this with allow rules in
`~/.claude/settings.json`. The README's driver section lists them:

```json
"Bash(multiplexer-driver --harness tuios pane spawn:*)",
"Bash(multiplexer-driver --harness tuios pane split:*)"
```

- An allow rule is a prefix match on the whole command. Issue every
  `pane spawn` and `pane split` as a bare command that starts with
  `multiplexer-driver --harness tuios`. A spawn inside an `&&`
  chain, after a `cd`, or after a heredoc does not match, and the
  classifier denies it again (seen in one run). Do not use the
  `MULTIPLEXER_DRIVER_HARNESS` short form for these two commands.
- You cannot add the rules. The classifier denies an edit to your own
  settings as self-modification, and a user request does not clear
  that. On the first denied spawn, stop, give the user the rules, and
  wait.
- Do not retry a denied spawn with other quoting or through another
  command. That is the outcome the classifier denied.

## Session and daemon

A tuios daemon holds sessions; a session holds windows in nine
numbered workspaces. The driver picks the session in this order:
`--session <name>` (or `MULTIPLEXER_DRIVER_SESSION`), else
`$TUIOS_SESSION`, which every tuios pane carries, else the most
recently active session, which is a guess when several are live. Name
the session whenever you run outside a tuios pane:

```bash
tuios ls
multiplexer-driver --harness tuios --session <name> pane list
```

An unknown session or a stopped daemon exits `3`.

The daemon is chosen by `XDG_RUNTIME_DIR`, which the driver never
sets. `--session` does not pick a daemon. The overseer inside a pane
reaches the user's daemon through the environment it inherited. Never
start, stop, or restart that daemon, and never run a
`tuios` command that stops, restarts, or reconfigures it. A private
daemon, for a test, needs fresh `XDG_RUNTIME_DIR` and `XDG_STATE_HOME`
directories under a short path such as `/tmp/tp.XXXXXX` (a unix socket
path has a length limit) in the environment of every command that
should reach it.

`tuios` refuses to draw on `TERM=dumb`, so a noninteractive caller
that attaches a client needs a real `TERM` and a terminal (`script`
gives one).

## Known quirks

- `new-window` creates the window with no command; the driver types
  the command line into its shell, so `read` shows the line echoed
  after the shell prompt.
- `send-keys` is for keys, `send-text` for text. `send-keys` takes one
  argument and splits it on spaces and commas.
- `capture-pane` without `--scrollback` reads only the visible
  screen; the driver always asks for the scrollback, so `--lines N`
  returns N lines.
- A new window's tab label is its shell title (for example
  `joshua@omarchy:/tmp`) until you rename it; the driver's `--name`
  sets the label at spawn.
- `pane prompt` on a pane on `needs_input` types anyway (see Dialogs).
- `raw` runs `tuios <args>` as given and does not add `-s`; pass the
  session yourself. `raw` needs `--` before the arguments.
- `pane kill` of a session's last window leaves the session alive with
  zero windows.
- `workspace create` and `workspace tag` exit `5`; a session's
  workspaces are fixed slots, and `workspace list` shows the ones with
  windows plus the current one.
