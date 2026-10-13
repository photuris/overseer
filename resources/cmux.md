# cmux driver

Concrete mapping of the overseer skill's abstract interface onto
cmux, via the [`multiplexer-driver`][md] CLI (`--harness cmux`).
Install it once per machine (see the README's Install section). cmux
runs on macOS only. This file is verified against cmux 0.64.22. Never
improvise `cmux` syntax beyond what this file documents; the few raw
`cmux` commands below exist because the driver does not wrap them.

[md]: https://github.com/photuris/multiplexer-driver

Set `MULTIPLEXER_DRIVER_HARNESS=cmux` once per shell to drop
`--harness cmux` from every call; the commands below spell it out.
Inside a cmux terminal the driver talks to that cmux; from anywhere
else, see Socket access.

## Signal and preconditions

```bash
test -n "${CMUX_SOCKET_PATH:-}"
```

A set `CMUX_SOCKET_PATH` means you are running inside cmux at all.
Overseer mode is on when the user invoked `/overseer` in this session.
cmux has no `HERDR_OVERSEER` equivalent, and the launcher sets none.

## Primitive mapping

| Primitive | Command |
|-----------|---------|
| spawn | `multiplexer-driver --harness cmux pane spawn --name <name> --cwd <dir> -- <command...>` (no `--workspace`) |
| split | `multiplexer-driver --harness cmux pane split <handle> --name <name> --direction right\|down -- <command...>` |
| status | `multiplexer-driver --harness cmux pane status <handle> [--patterns patterns.json]` — native when cmux's agent hooks report, heuristic with `--patterns` otherwise, `unknown` with confidence `none` when neither is available |
| read | `multiplexer-driver --harness cmux pane read <handle> --lines N` (no `--ansi`) |
| prompt | `multiplexer-driver --harness cmux pane prompt <handle> --text "<text>"` |
| wait | `multiplexer-driver --harness cmux pane wait <handle> --timeout 12m [--until idle\|working\|blocked]... [--patterns patterns.json]` |
| list | `multiplexer-driver --harness cmux pane list` |
| rename | `multiplexer-driver --harness cmux pane rename <handle> --label <label>` |
| interrupt | `multiplexer-driver --harness cmux pane interrupt <handle>` (Ctrl-C) or `pane kill <handle>` (hard stop) |
| notify | `multiplexer-driver notify --message "..." [--title "..."]` — uses `cmux notify` inside cmux; `--sound` is ignored |

Every subcommand prints JSON to stdout on success (one object, or JSON
Lines for `pane list`). On failure the exit code is nonzero and the
last stderr line is `{"error":{"type":…,"message":…}}`, with cmux's
own error text inside `message`. Branch on the exit code: `2` usage,
`3` cmux not reachable, `4` no such surface or workspace, `5`
unsupported on cmux (`pane read --ansi`, `workspace tag`), `6` started
false (below), `7` wait timed out.

`spawn` and `split` have one more outcome. The driver never checks
that the agent finished starting. It exits `6` and still prints the
handle when the workspace or surface exists but a later setup step
failed: for `spawn` the `rename-tab`; for `split` the paste of the
command line or the `rename-tab`:

```json
{"handle":"9368A7E3-DCC1-4510-8DD6-DB8A819770F8","started":false}
```

Success prints `"started":true`. A `started:false` surface is live:
read the stderr error to see which step failed, `read` the surface,
then repair it by hand or kill it. Rename it with `pane rename
<handle> --label <name>`. If the command line never reached the
shell, send it with `pane prompt <handle> --text "<command line>"`.
Otherwise close the surface with `pane kill <handle>`. A dialog never
causes exit `6` here; dialogs show up on `read` after a
`started:true` (see Dialogs).

A nonzero exit with no stdout can still have created a workspace:
cmux's `new-workspace` may have succeeded while the follow-up `tree`
lookup failed, leaving no handle to print. Before any retry, list the
workspaces. If one titled `<name>` exists, close it, or the
workspaces pile up:

```bash
multiplexer-driver --harness cmux workspace list
multiplexer-driver --harness cmux workspace close <workspace_id>
```

## Handles

A handle is a terminal surface UUID, such as
`9368A7E3-DCC1-4510-8DD6-DB8A819770F8`. It stays valid across rename,
move, and split. cmux's short refs (`surface:N`, `workspace:N`) are
positions that shift when something closes, so never store or pass
one as a handle. `pane list` prints the workspace UUID beside every
handle; a few raw `cmux` commands below need it.

## Spawn opens a workspace

A cmux surface is a tab hidden behind its siblings. A workspace is a
sidebar row, and cmux decorates that row with the agent's state. So
`spawn` opens a new workspace for each agent, and one agent per
workspace keeps every agent visible. `pane spawn --workspace` is a
usage error on cmux (exit `2`). To group two implementers, use `pane
split` (see Topology).

The command runs as a shell line typed into a fresh interactive
shell. A wrapper or an alias works if that shell sees it. There is no
agent-kind launcher, so cmux does not recognize an agent by its
command name; Status explains how it learns of one.

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
the resolved command line of an agent with cmux hooks is in the
`cmux sessions` store:

```bash
cmux sessions --json --surface <handle> | jq -r '[.sessions[] | select(.active_for_surface and .stored_pid_exists)] | sort_by(.updated_at_unix) | last | if . == null then "null" else (.launch_arguments | join(" ")) end'
```

It prints the joined command, or the word `null` (exit `0`) when the
store is empty or the session is inactive. On `null`, `read` the pane
again right after the agent's next reply: Claude Code and Codex print
the model in their status line.

## Status

Three cases, three commands:

```bash
# (a) An agent with cmux hooks: native, no patterns needed.
multiplexer-driver --harness cmux pane status <handle>

# (b) An agent without hooks, with a patterns file: heuristic.
multiplexer-driver --harness cmux pane status <handle> --patterns patterns.json

# (c) An agent without hooks, no patterns file: unknown, confidence none.
multiplexer-driver --harness cmux pane status <handle>
```

In case (c), `pane wait` exits `2` (usage) until you pass
`--patterns`.

Native status comes from cmux's agent hooks, read through `cmux
sessions`. Claude Code gets the hooks automatically when started from
a cmux shell (cmux's `claude` wrapper, on by default as
`automation.claudeCodeIntegration`). Codex, Pi, OpenCode, Gemini, and
the others need this once per machine:

```bash
cmux hooks setup <agent>
```

`cmux hooks setup` with no name installs for every agent on `PATH`.
The mapping is `running` -> `working`, `idle` -> `idle`, `needsInput`
-> `blocked`.

`needsInput` also fires when an agent has sat idle at its prompt for
about a minute (Claude's idle notification). So `blocked` on cmux
means "read the pane", not "a dialog is up".

An agent without hooks, or one started before `cmux hooks setup`, has
no session. Then `status` is `unknown` with confidence `none`, and
`pane wait` refuses to run. Pass `--patterns`, written from one real
`read` and never guessed:

```json
{"idle": ["❯\\s*$"], "blocked": ["Trust this folder\\?"]}
```

How the match works, since each point has caused a wrong pattern:

- The patterns run against the surface's last 15 lines taken as one
  string. `$` anchors to the end of that whole tail, not to each line.
  Use `(?m)` for per-line anchors (`(?m)^DONE$`).
- `blocked` is checked first, then `idle`; `working` means neither
  matched. A surface parked at a prompt your `idle` pattern misses
  reads `working` forever.
- The surface echoes what you type, so a pattern that matches your own
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
   means answer it (see Dialogs). Text in the input row that you sent
   means the prompt sat unsubmitted, so press Enter with `cmux
   send-key --surface <handle> enter`, wait briefly, and confirm
   `working`. Text you did not send is the agent's greyed-out
   suggestion. cmux's plain-text read cannot mark it as dim (there is
   no `--ansi` here), so never press Enter on it. Still not `working`:
   the dispatch failed — `read` the transcript, fix the cause (crashed
   agent, API error, wrong working directory), and re-dispatch from
   the top. Never assume a dispatch took.

Then follow the core skill's dispatch ritual.

## Dispatch

```bash
multiplexer-driver --harness cmux pane read <handle> --lines 20
multiplexer-driver --harness cmux pane prompt <handle> --text "Task ready: .overseer/runs/<run-id>/tasks/003-rate-limit.md. Respond in that file."
```

`prompt` delivers the text verbatim through cmux's paste path and
presses Return, so backslashes, `$HOME`, and quotes arrive unchanged.
Never send prompt text with raw `cmux send`, which turns `\n` and `\t`
into Enter and Tab.

`pane read` prints `{"handle":…,"output":…}`; the pane text is in
`output` (`… | jq -r .output`). `pane read --ansi` is unsupported on
cmux (exit `5`): cmux returns plain text only, so a greyed-out prompt
suggestion and typed input look the same. When the input row holds
text you did not send, assume it is the agent's suggestion unless the
words are yours, and never press Enter on it.

`prompt` only sends and submits — it does not wait. Confirm the
dispatch took (ritual step 3), then wait in one bounded interval of
the health watch. For an agent with cmux hooks:

```bash
multiplexer-driver --harness cmux pane wait <handle> --until working --timeout 60s
multiplexer-driver --harness cmux pane wait <handle> --timeout 12m   # idle or blocked
```

For an agent without hooks, add the patterns file to both (without it
both calls exit `2`):

```bash
multiplexer-driver --harness cmux pane wait <handle> --until working --timeout 60s --patterns patterns.json
multiplexer-driver --harness cmux pane wait <handle> --timeout 12m --patterns patterns.json   # idle or blocked
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
returns at once.

## Dialogs

`prompt` pastes text and presses Return; it does not choose a menu
option. Read the pane (`pane read`) to see the dialog, then answer it
with raw key presses. Look at where the dialog's cursor sits before
you press Enter. Claude Code's folder-trust dialog starts on "No,
exit", so a bare `enter` quits the agent: move down first.

```bash
cmux send-key --surface <handle> down
cmux send-key --surface <handle> enter
```

Codex's folder-trust dialog starts on "Yes, continue", so a bare
`enter` accepts it:

```bash
cmux send-key --surface <handle> enter
```

cmux 0.64.22 has no draft guard: `send-key` and `prompt` type over a
draft or into a dialog without complaint. Newer builds refuse and
print the reason on stderr; then `read` the pane and answer the dialog
as above.

`pane status` reads `blocked` for a dialog only when the agent's hooks
report it. A trust dialog appears before the hooks run, so after every
spawn, `read` once before the first prompt.

## Retiring a Claude session

```bash
multiplexer-driver --harness cmux pane prompt <handle> --text /exit
multiplexer-driver --harness cmux pane read <handle> --lines 6
```

Poll `pane read` every two seconds for up to twenty seconds until the
output holds the line `Resume this session with:` (Claude prints it
on exit; verified) and, two seconds after it first appears, has not
changed. That is the exit check. An empty `sessions` array or an
`unknown` status is not a check, because an agent without hooks shows
both while it runs.

If twenty seconds pass without that line, or with the line but output
that keeps changing, send `pane interrupt <handle>` twice, 0.3 s apart
(Claude's exit chord), `read` once more, then kill anyway and record
in `STATE.md` that the session was killed without a clean exit. Then:

```bash
multiplexer-driver --harness cmux pane kill <handle>
```

`pane kill` closes the surface. When it is the last surface of its
workspace, cmux refuses ("Cannot close the last surface") and the
driver closes the workspace instead, which is what a spawned agent's
workspace needs.

## Isolation

```bash
multiplexer-driver --harness cmux pane list \
  | jq -c --arg repo "$PWD" 'select(.agent != null and .cwd != null and (.cwd | startswith($repo)) and .handle != env.CMUX_SURFACE_ID) | {handle, workspace_label, agent, status, cwd}'
```

This finds every agent that reports through cmux's hooks; those
records always carry `cwd`. An agent without hooks lists as a plain
shell (`agent` and `cwd` null), so run a second, conservative check.
List every other shell surface, then `read` each one:

```bash
multiplexer-driver --harness cmux pane list | jq -r 'select(.agent == null and .handle != env.CMUX_SURFACE_ID) | .handle'
multiplexer-driver --harness cmux pane read <handle> --lines 10
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
`.overseer/active/` holds no lease but yours. `pane list` sees only
cmux; an overseer in T3 Code, Herdr, or tmux shows up only as a lease.
Another live session in the repo, another lease, or three or more
concurrent implementers, means one worktree each, and you own the
merge.

Create each worktree with git, then spawn the implementer in it:

```bash
git worktree add <path> -b task/003 main
multiplexer-driver --harness cmux pane spawn --name impl-003 --cwd <path> -- <command>
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
multiplexer-driver --harness cmux pane spawn --name impl-003 --cwd "$PWD" -- claude --model sonnet
# prints {"handle":"<uuid>","started":true}; copy <uuid> below
multiplexer-driver --harness cmux pane split <uuid> --name impl-004 --direction right --cwd "$PWD" -- claude --model sonnet
multiplexer-driver --harness cmux pane split <uuid> --name impl-005 --direction down --cwd "$PWD" -- claude --model sonnet
```

- Give the reviewer its own `spawn` (own workspace), never a `split`
  into an implementer's; the reviewer never shares.
- Name agents by task: `impl-003`, `verify-003`, `review-r2`,
  `critic`.
- At every `STATE.md` update, report task and phase to the sidebar so
  the user can read it without opening a surface. The workspace id is
  in the agent's `pane list` record:

```bash
cmux workspace-action --action set-description --description "task=003 phase=review" --workspace <workspace_id>
```

  `workspace status set` is the user's, never the overseer's.

## Notify

```bash
multiplexer-driver notify --message "Overseer: plan ready for approval" --title "Overseer"
```

Inside cmux this reaches cmux's notification panel and banner and
prints `{"sent":true,"method":"cmux"}`. `--sound` is ignored on cmux.
If the response says `"sent":false`, that is not a failure to retry;
say the gate message directly in your own reply too.

## Claude Code auto mode

When you run as Claude Code in auto mode, a classifier checks each
shell command. It denies a spawn whose command starts an agent with
approvals off (seen with `codex --yolo`, reason "Create Unsafe
Agents"). The user clears this with allow rules in
`~/.claude/settings.json`. The README's driver section lists them:

```json
"Bash(multiplexer-driver --harness cmux pane spawn:*)",
"Bash(multiplexer-driver --harness cmux pane split:*)"
```

- An allow rule is a prefix match on the whole command. Issue every
  `pane spawn` and `pane split` as a bare command that starts with
  `multiplexer-driver --harness cmux`. A spawn inside an `&&`
  chain, after a `cd`, or after a heredoc does not match, and the
  classifier denies it again (seen in one run). Do not use the
  `MULTIPLEXER_DRIVER_HARNESS` short form for these two commands.
- You cannot add the rules. The classifier denies an edit to your own
  settings as self-modification, and a user request does not clear
  that. On the first denied spawn, stop, give the user the rules, and
  wait.
- Do not retry a denied spawn with other quoting or through another
  command. That is the outcome the classifier denied.

## Socket access

`automation.socketControlMode` defaults to `cmuxOnly`: only processes
started inside cmux connect. The overseer runs inside cmux, so there
is nothing to do.

To drive cmux from another terminal (the multiplexer-driver live test,
or an overseer in Herdr or tmux), set `password` mode with a
`socketPassword` in `~/.config/cmux/cmux.json`, then reload:

```bash
cmux reload-config
```

The CLI reads the saved password itself; `CMUX_SOCKET_PASSWORD` or
`--password` override it. `--session <path>` on the driver is `cmux
--socket <path>`. Do not use `allowAll`: it is unsafe on a shared Mac.

## Known quirks (0.64.22)

- `new-split` has no `--command`; the driver pastes the command line
  into the new surface instead.
- `rename-tab` and `close-surface` need `--workspace`; the driver
  looks it up.
- `new-workspace` prints `OK workspace:N`, not JSON; the driver
  resolves the ref to a UUID at once.
- `CMUX_QUIET=1` silences the deprecation notices cmux prints on
  stderr. The driver sets it on every child; set it yourself for a raw
  `cmux` call.
- `cmux sessions` reads a file and works without the socket.
- `surface.input_state` and `cmux paste` from newer cmux docs do not
  exist in this build.
