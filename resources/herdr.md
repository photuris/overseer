# Herdr driver

Concrete mapping of the overseer skill's abstract interface onto
Herdr, via the [`multiplexer-driver`][md] CLI (`--harness herdr`).
Install it once per machine (see the README's Install section). This
file assumes the `herdr` skill for general pane/tab/worktree mechanics
and covers anything multiplexer-driver does not wrap (below) with raw
`herdr` commands instead — never improvise syntax beyond what's
documented here.

[md]: https://github.com/photuris/multiplexer-driver

Set `MULTIPLEXER_DRIVER_HARNESS=herdr` once per shell to drop
`--harness herdr` from every call; the commands below spell it out.
Inside a Herdr pane the driver talks to that pane's session; from
anywhere else, pass `--session <name>` (or set
`MULTIPLEXER_DRIVER_SESSION`).

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
| spawn | `multiplexer-driver --harness herdr pane spawn --name <name> -- <command...>` |
| split | `multiplexer-driver --harness herdr pane split <handle> --name <name> --direction right\|down -- <command...>` |
| status | `multiplexer-driver --harness herdr pane status <handle>` — always native, no patterns needed |
| read | `multiplexer-driver --harness herdr pane read <handle> --lines N [--ansi]` |
| prompt | `multiplexer-driver --harness herdr pane prompt <handle> --text "<text>"` |
| wait | `multiplexer-driver --harness herdr pane wait <handle> --timeout 12m [--until idle\|working\|blocked]...` |
| list | `multiplexer-driver --harness herdr pane list` |
| rename | `multiplexer-driver --harness herdr pane rename <handle> --label <label>` |
| interrupt | `multiplexer-driver --harness herdr pane interrupt <handle>` (Ctrl-C) or `pane kill <handle>` (hard stop) |
| notify | `multiplexer-driver notify --message "..." [--title "..."] [--sound request]` — prefers Herdr's own notification automatically |

Every subcommand prints JSON to stdout on success (one object, or JSON
Lines for `pane list`). On failure the exit code is nonzero and the
last stderr line is `{"error":{"type":…,"message":…}}`, with Herdr's
own error code and message (e.g. `agent_blocked`) inside `message`.
Branch on the exit code: `2` usage, `3` Herdr session not running, `4`
no such pane or workspace, `6` started false (below), `7` wait timed
out.

`spawn` and `split` have one more outcome. When the pane was created
but the agent did not finish starting, they exit `6` and still print
the handle:

```json
{"handle":"w1:p7","started":false}
```

Success prints `"started":true`. No stdout at all means the pane was
never created. A `started:false` pane is yours to deal with: `read`
it first. A startup dialog (folder trust) is the usual cause, so
answer it (see Dialogs) and carry on. If the command simply exited or
never came up, close the pane with `pane kill`. Never retry a
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
record it in the `STATE.md` roster.

With the `overseer` launcher the roster is literal commands. A
kind+model shorthand (seen twice: `claude-opus`) means the user set
the variables by hand. Honor the intent:
`multiplexer-driver --harness herdr pane spawn --name impl-003 --
claude --model opus`, record the banner's model in the roster, and do
not treat the unresolvable shorthand as "unset"; `overseer init`
(README, install step 4) is the fix for next time. When the banner has
scrolled off (seen in two runs), the pane's process shows the
resolved command line, e.g. `claude --model claude-opus-5`:

```bash
herdr pane process-info --pane <handle>
```

Always pass `--add-dir <path>` (as part of the trailing `-- <command
...>`) for every outside repository a task's Read-only list names;
without it the first outside read blocks on a permission prompt (seen
in three consecutive runs).

## Claude Code auto mode

When you run as Claude Code in auto mode, a classifier checks each
shell command. It denies a spawn whose command starts an agent with
approvals off (seen with `codex --yolo`, reason "Create Unsafe
Agents"). The user clears this with allow rules in
`~/.claude/settings.json`. The README's driver section lists them:

```json
"Bash(multiplexer-driver --harness herdr pane spawn:*)",
"Bash(multiplexer-driver --harness herdr pane split:*)"
```

- An allow rule is a prefix match on the whole command. Issue every
  `pane spawn` and `pane split` as a bare command that starts with
  `multiplexer-driver --harness herdr`. A spawn inside an `&&`
  chain, after a `cd`, or after a heredoc does not match, and the
  classifier denies it again (seen in one run). Do not use the
  `MULTIPLEXER_DRIVER_HARNESS` short form for these two commands.
- You cannot add the rules. The classifier denies an edit to your own
  settings as self-modification, and a user request does not clear
  that. On the first denied spawn, stop, give the user the rules, and
  wait.
- Do not retry a denied spawn with other quoting or through another
  command. That is the outcome the classifier denied.
- A Claude Code implementer can stop before its commit on a transient
  tool error such as "Bash classifier errored on three attempts"
  (seen twice in run fix-1). That is not degradation: with a coherent
  transcript, re-prompt it once with the task nudge (the core skill's
  health watch has the general rule).
- The worktree path in Isolation starts agents with `herdr agent
  start`. It needs its own rule, `Bash(herdr agent start:*)`.

## Dialogs

`prompt` cannot answer a folder-trust or approval dialog — Herdr
itself rejects a real prompt submission with `agent_blocked` while
one is showing, by design, and the driver's `pane prompt` does not
work around that. Read the pane (`pane read`) to see the dialog, then answer it with raw key presses Herdr's own CLI covers.
Look at where the dialog's cursor sits before you press Enter. Codex's
folder-trust dialog starts on "Yes, continue", so `enter` accepts it.
Claude Code's starts on "No, exit", so a bare `enter` quits the
agent: move down first.

```bash
herdr agent send-keys <handle> enter        # cursor already on "yes"
herdr agent send-keys <handle> down enter   # cursor starts on "no"
```

`status` reporting `blocked` is your signal to look. `agent start`
has reported an error while the launched tool was still drawing its
banner (seen in two consecutive runs) — if a `spawn`/`split` call
fails right after launch, `read` before trusting the error.

## Retiring a Claude session

A Claude Code session exits only on a double ctrl+c with an empty input
line. Clear the input first, then send both ctrl+c presses about 0.3 s
apart; at 0.7 s or more the second press sometimes lands outside the
exit window. Address the pane id, not the agent name.
`herdr agent send-keys <name>` has returned ok without reaching the pane
(seen in runs 053 and 054).

```bash
herdr pane send-keys wF:pA ctrl+u; sleep 0.4
herdr pane send-keys wF:pA ctrl+c; sleep 0.3
herdr pane send-keys wF:pA ctrl+c
herdr pane process-info --pane wF:pA   # argv must now be the shell
```

Always confirm with `process-info` before reusing the pane: `herdr agent
start` refuses a pane that still runs the old agent (`agent_pane_busy`).

## Dispatch ritual

Startup dialogs (folder trust, update prompts, imports) and composer
races eat first prompts on most harnesses. For each dispatch:

1. `read` the target's recent output first — is a dialog sitting at
   the prompt?
2. `prompt` the task-ready nudge, waiting for idle with a generous
   timeout.
3. If the wait reports the prompt as stalled, or returns with the agent still
   `idle`: `read` again. A dialog means answer it (see Dialogs). No dialog, and
   the input box holds the text you sent: it is sitting unsubmitted, so
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
multiplexer-driver --harness herdr pane read <handle> --lines 20
multiplexer-driver --harness herdr pane prompt <handle> --text "Task ready: .overseer/tasks/003-rate-limit.md. Respond in that file."
```

`read` returns plain text by default. To tell an agent's greyed-out
prompt suggestion from typed input (dispatch ritual step 3), read
with styling preserved:

```bash
multiplexer-driver --harness herdr pane read <handle> --lines 12 --ansi
```

Text between `ESC[2m` and the next reset is dim: a suggestion, not
input.

`pane read` prints `{"handle":…,"output":…}`; the pane text is in
`output` (`… | jq -r .output`).

`prompt` only sends and submits — it does not wait. Confirm the
dispatch took (ritual step 3), then wait in one bounded interval of the
health watch, with `pane wait` (native status, no patterns needed):

```bash
multiplexer-driver --harness herdr pane wait <handle> --until working --timeout 60s
multiplexer-driver --harness herdr pane wait <handle> --timeout 12m   # idle or blocked
```

Exit `7` from the first call means the prompt did not take: go back to
ritual step 3. Exit `7` from the second is the health-check point:
`read` the pane, judge it, check file progress, and wait again. A wait that ends prints the status
JSON and exits 0 for `blocked` as well as `idle`, so check `.status`
before treating it as done. A task that finishes within one poll
(about half a second) can slip past the first wait; check the artifact
before treating its exit `7` as a failed dispatch. Never
wait straight for `idle` right after `prompt` — the agent is still idle
in the instant before it starts, so that wait returns at once. Do not
use raw Herdr's own `agent prompt --wait` or `agent wait`; the driver's
wait behaves the same on every harness.

## Topology

```bash
h=$(multiplexer-driver --harness herdr pane spawn --name impl-003 -- claude --model opus | jq -r .handle)
multiplexer-driver --harness herdr pane split "$h" --name impl-004 --direction right -- claude --model opus
multiplexer-driver --harness herdr pane split "$h" --name impl-005 --direction down -- claude --model opus
```

- Give the reviewer its own `spawn` (own tab), never a `split` into an
  implementer's tab; the reviewer never shares.
- Name agents by task: `impl-003`, `verify-003`, `review-r2`,
  `critic`.
- At every `STATE.md` update, report the same state to the sidebar so
  the user can read it without opening a pane — the driver tags
  workspaces, not panes, so call Herdr directly:

```bash
herdr pane report-metadata "$HERDR_PANE_ID" --source overseer --token task=003 --token phase=review
```

  Report `task` and `phase` on implementer panes too (`phase` is one of
  `impl`, `verify`, `review`, `fix`, `accepted`).

## Isolation

```bash
multiplexer-driver --harness herdr pane list \
  | jq -c --arg repo "$PWD" 'select(.agent != null and .cwd != null and (.cwd | startswith($repo)) and .handle != env.HERDR_PANE_ID) | {handle, workspace_label, agent, status, cwd}'
```

Each record is one pane with its agent, status, and working
directory, so this prints every other live agent working in the repo.
Given disjoint tasks, two implementers may share the main checkout
only when this prints nothing (or only your own implementers).
Another live session in the repo, or three or more concurrent
implementers, means one Herdr worktree each, and you own the merge.

Create each worktree from your own workspace, never from a path:

```bash
resp=$(herdr worktree create --workspace "$HERDR_WORKSPACE_ID" --branch task/003 --base main --no-focus)
pane=$(echo "$resp" | jq -r .result.root_pane.pane_id)   # the new workspace's shell pane
herdr agent start impl-003 --kind claude --pane "$pane" \
  --timeout 60000 -- --model opus --add-dir "$PWD/.overseer"
```

The worktree opens as its own workspace; the implementer starts in
that workspace's root pane (`herdr agent start`, not `spawn`, which
would land in your workspace and the main checkout). The checkout path
is `.result.worktree.path`.

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
Task ready: /abs/main/checkout/.overseer/tasks/003-rate-limit.md.
Respond in that file.
```

`--cwd` resolves the repo's parent workspace by scanning the sidebar
for the first workspace whose first-tab pane happens to sit in that
repo. That can be another project's workspace with a shell parked in
your repo; Herdr then stamps it as the repo's parent and nests your
workspace, and every other workspace on the repo, under it in the
sidebar (seen in one run, and it persists across restarts).
`--workspace` pins the parent to the caller and never scans.

## Notify

```bash
multiplexer-driver notify --message "Overseer: plan ready for approval" --title "Overseer" --sound request
```

`--sound request` is for the three human-in-the-loop gates and
nothing else. Herdr can report success while showing nothing at all —
if the user has notifications turned off, the response comes back
`{"sent":false,"reason":"disabled",...}`; that is not a failure to
retry, it means say the gate message directly in your own reply too.

## Windows

Herdr runs natively on Windows, and so does multiplexer-driver
(Herdr only; there is no tmux there). Panes are assumed to run
PowerShell: a command that is not a known agent kind is sent as a
PowerShell command line, and an argument that is empty, contains `"`,
or ends with `\` is rejected (exit 2) because Windows PowerShell 5.1
cannot pass it reliably. Known agent kinds (`claude`, `codex`, …) are
launched by argv and are unaffected. In PowerShell, quote a bare `--`
(`'--'`) when you pass it to a function of your own; PowerShell
swallows an unquoted one.
