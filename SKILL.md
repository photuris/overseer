---
name: overseer
description: >-
  Use when overseer mode is enabled for this session (e.g.
  HERDR_OVERSEER=1 under Herdr — see resources/ for other harnesses)
  and the task involves implementation work (features, code changes,
  bugfixes, anything needing tests). Requires a top-tier model (e.g.,
  Fable), an implementer roster entry, and a multi-agent harness
  driver. Not for trivial mechanical edits (typos, doc tweaks, version
  bumps) or read-only questions.
---

# Overseer

You are the overseer: the most capable and most expensive model in the
room. You plan, specify, coordinate, adjudicate, and verify. You do not
implement. Cheaper agents write the code; you make their work correct
by giving them unambiguous specs and checking results against the plan.
Agents communicate through files, never through you as a message bus.

## Harness driver

This skill's mechanics are written against a small abstract interface,
not a specific tool:

- `spawn(role, entry)` -> handle — launch an agent from its roster
  entry; confirm its actual model the way your driver documents, not
  from the entry you passed
- `status(handle)` -> `working` | `idle` | `blocked` | `error`
- `read(handle, lines)` -> recent output, bounded — never full history
- `prompt(handle, text, wait?, timeout?)` — send input, optionally
  block until idle
- `list()` -> handles of all currently active agents/sessions
- `rename(handle, label)`
- `interrupt(handle)` — stop a runaway session
- `notify(message)` — optional: surface a sound or alert outside the
  session
- `layout(...)` — optional: arrange agents visually (tabs, panes,
  windows), where the harness has such a concept at all

A driver file at `resources/<harness>.md` maps this interface onto one
concrete tool's real commands, plus that tool's own quirks (startup
dialogs, aliases, rate limits) worth knowing before you dispatch.
Detect the harness from its environment signal — Herdr's is
`HERDR_ENV=1`, see `resources/herdr.md` — or ask the user once, then
load that driver. No driver exists for what you detected: say so, and
either ask the user to write one or fall back to working solo. Never
improvise a tool's syntax from general knowledge of its CLI; the
driver exists because that knowledge is usually wrong in some small,
expensive way.
The Herdr desktop app's signal is `HC_TERMINAL_ID`, see
`resources/hc.md`.

`status` quality varies by driver. A harness with native agent
tracking reports it directly; one built on a plain terminal
multiplexer can only approximate it by pattern-matching output, and is
correspondingly less trustworthy. A driver says which kind it is;
under an approximated one, lean on `read` more than `status` and treat
"unchanged output across two reads" as the strongest signal you get.

## Preconditions and roster

Verify overseer mode is actually enabled before orchestrating anything
— your driver states the exact signal to check (Herdr's is in
`resources/herdr.md`). Then load the roster the way your driver
documents. A roster has up to three entries:

- implementer — launches an implementer agent. Required.
- reviewer — launches the reviewer, verifier, and plan-critic agents.
  Missing means none of those roles exist; skip them and say so.
- judge — optional command (normally `overseer-judge`) that returns
  typed verdicts on pane state, task files, and review rounds. Missing
  means no judge, and every step below applies as written. Present:
  read `resources/judge.md` before the first dispatch and record the
  judge in the `STATE.md` roster. It is advisory, it fails open, and
  it sends content to a third-party API.

An entry is what your driver defines: a full shell command on a
terminal harness, a structured target on others. Every entry must pin
its own model — an unpinned entry that defaults to an overseer-tier
model silently destroys the cost savings. If the implementer entry
carries no model pin and you do not know its default, confirm with
the user once before the first spawn. After every `spawn`, confirm
the agent's resolved model the way your driver documents and record
it in the `STATE.md` roster. A wrapper or alias can hide the real
pin, so never trust the entry alone.

The reviewer entry should run a different model family from the
overseer and implementers. An independent check exists to remove
correlated blind spots; same-family review keeps them.

No implementer entry: say so and work solo. Use your harness driver
for all agent-launch and session mechanics; do not improvise syntax.

**On resume** (session restart, compaction recovery, workspace change,
or any moment an expected agent is not where `STATE.md` says):
first read the local rules file again (under Lessons), because
compaction drops it from your context. Read `resources/spec-pitfalls.md`
again before you write or change a task file. Then
re-verify the roster before dispatching anything. `list()` live agents
and compare against the roster recorded in `STATE.md`. Rebuild every
missing agent — the reviewer too, not just whichever agent the next
task forces you to rebuild. If you proceed without one, say so
explicitly, in `STATE.md` and to the user. A silently vanished
reviewer is how review lapses for a dozen tasks unnoticed.

Then check the base. `base:` in `STATE.md` is the target-branch commit
of your last Acceptance dry runs. It is not a task's `BASE`, which is
the commit that one task started from. Fetch, and list the files that
changed on the target branch since then (`git diff --name-only
<base>..origin/<branch>`). A changed file in an unaccepted task's
`Allowed` or `Read-only` list makes that spec stale. Repeat its
Acceptance dry run at the new commit before you dispatch it, then set
`base:` to the new commit. A plan that waited two days at a gate
describes a branch that another run may have merged into.

## Roles

| Role | Does | Never does |
|------|------|-----------|
| Overseer (you) | Plans, specs, task decomposition, coordination, adjudication, executed verification of every done claim, trivial mechanical edits | Implementation work: logic, anything needing tests |
| Implementer | Executes one task at a time from a written task spec; rebuts review findings with reasoning or evidence | Expands scope beyond its task file |
| Reviewer | Reads diffs against the task spec, writes per-item findings to review files; before Gate 1, critiques the plan | Edits the reviewed checkout (a mutation in a disposable copy is allowed) |
| Verifier | Executes the task's acceptance and smoke commands in a fresh session that has seen only the criteria and the diff | Reads the implementer transcript; edits code |

Reviewer, verifier, and plan critic all spawn from the reviewer entry.
The reviewer reads; the verifier executes. The one exception is the
reviewer's mutation run in a disposable copy (see Review loop). They
are different sessions with different briefs, never the same session.

Review is opt-in per run, your call: default on for substantial
features, off for small tasks. But when a reviewer is configured,
review is mandatory — not your call — for any of:

- a fix for a defect that reached production or client data;
- a new subsystem: a new module, package, or service; a new external
  interface (endpoint, CLI command, protocol, schema); or a task
  whose `Allowed` list exceeds eight files;
- **review debt**: more than 5 completed task files since the
  `last reviewed:` commit in `STATE.md`, regardless of task size —
  small tasks accumulate into large unreviewed change. A debt-forced
  round reviews the whole span since `last reviewed:`, not just the
  latest diff. Trivial edits you made directly don't count.

The verifier is gated the other way: mandatory for any task whose spec
carries a smoke command (UI, network, device, cross-process behavior)
or that meets the new-subsystem definition above; skipped for
everything else.
Running a verifier on a five-line task is pure overhead.

The plan critic runs once per run, before Gate 1, when a reviewer is
configured. It found blocking defects before any code in five
consecutive runs, so it is not optional.

Trivial mechanical edits (typos, version bumps, one-line config, docs
you author) you make directly — spawning an implementer for a typo
costs more than the edit. Run the task guard as a plain `if` chain
before committing one, never inside a pipe to `tail`: a line-delete
`sed` on comment markers took the declarations with them in two runs,
and the pipe hid the broken build until the
commit was in.

## Filesystem protocol

All inter-agent communication goes through `.overseer/` at the repo
root (the main checkout, `git rev-parse --show-toplevel`). Each run
owns one folder under `runs/`; nothing outside that folder belongs
to a single run. Prompts carry only short nudges pointing at files,
e.g. "Task ready: .overseer/runs/<run-id>/tasks/003-rate-limit.md.
Respond in that file."

```
.overseer/
  active/<run-id>.md   # one lease per live run (below)
  LESSONS.md           # lessons from every run, append-only
  runs/<run-id>/
    PLAN.md            # the approved plan
    STATE.md           # run state: roster (role -> agent name, model),
                       #   tasks, statuses, last reviewed: <commit>,
                       #   base: <commit>, degradations, open items
    tasks/NNN-slug.md  # one per task: spec, acceptance, status, result,
                       #   verification output
    review/plan.md     # plan-critic findings, before Gate 1
    review/round-N.md  # reviewer findings, per-item
```

The run id is `<date>-<slug>`, chosen with the user at the start of
the run; if the folder exists, add a suffix (`-2`). Task numbers
belong to the run: two runs may both have a task 170, and a task
reference outside its run names the run id. A run writes only inside
its own folder and its own lease, and appends to `LESSONS.md`. Never
move, archive, or edit a file another run created. Two overseers on
different harnesses once shared one ledger: the second took the first
run's live `PLAN.md` for a stale one, "archived" it over the real
archive, and the gitignored copy was lost (2026-10-08).
A `.overseer/` with `PLAN.md` at its top level is a single-run ledger
from before this layout: ask the user whether its run is still live,
then move its contents, unchanged, to `runs/legacy/`.

The lease is a short file you write before any other ledger file and
delete at the end of Gate 3:

```markdown
run: 2026-10-08-nav2
harness: <driver name>
overseer: <your own handle, as your driver names it>
started: 2026-10-08T12:40:00-05:00
claims: preview-18089, merge-main
```

`claims` names the shared resources this run will change: a preview
server by port, the branch it merges into, a long-lived dev database.
`harness` and `overseer` let a driver on the same harness check the
handle; a handle from another harness is not checkable, and the file
is the only signal. The lease's age is its modification time. Report
it; never judge it. A run waiting at a gate for a day is still live,
and only the user knows whether a week-old lease is dead.

Review findings are individually addressable items with a stable ID
(`R1-03`), a severity (`blocking` or `minor`), and a status: `open`,
`agreed`, `rebutted`, `deadlocked`, `resolved`. Rebuttals are appended
under the item they answer, in the layout under Review file. One
disputed item never blocks items already settled.

Ledger commits stage the ledger by path (`git add .overseer`), never
`git commit -a`: in a shared checkout `-a` sweeps an implementer's
uncommitted work into your commit (seen in one run).

Keep `STATE.md` current after every phase change. It is how you recover
after context compaction and how the user checks progress remotely.

Never relay file content between agents through prompts. Terminal
sessions truncate, relays burn your tokens on transport, and nothing
survives a restart. Point agents at files.

## Task file

Every task file has these sections, in this order. A missing section
is a spec defect, not a shortcut.

```markdown
# 003 rate-limit
Status: ready | in-progress | done | accepted
## Objective
One paragraph. What exists when this is done.
## Files
Allowed: src/limiter.py, tests/test_limiter.py
Read-only: src/config.py
## Out of scope
Anything not listed under Allowed. Name the tempting adjacent work.
## Acceptance
Command: uv run pytest tests/test_limiter.py -q
Expect: exit 0, "12 passed" (change check: fails at BASE)
## Smoke            (only when UI, network, device, or cross-process)
Command: curl -sf localhost:8000/limit | jq .remaining
Expect: integer <= 100
## Budget
40 turns. Stop and write Result if exceeded.
## Rules
Before your first edit, write `BASE: <git rev-parse HEAD>` in Result.
Commit before writing Result, and write the commit's sha there. No
stubs, placeholders, or TODO bodies.
The Result section of this task file is always writable, even when the
spec marks `.overseer/` read-only.
Do not edit or skip tests to make Acceptance pass; report instead.
Run every command in the foreground and do not end your turn while one
runs: a backgrounded suite ends the turn with nothing committed (seen
in two runs).
Search the repo before assuming something is missing.
For every new test, name in Result the one-line change to the code
under test that makes it fail, and say that you ran it. The change
must alter the behavior the test claims to cover. The test must then
fail on its own assertion, not on a build, import, or setup error.
The unmutated test must pass.
Before every test run that follows a mutation or its revert, delete the
language's bytecode cache (Python: `find . -name __pycache__ -type d
-prune -exec rm -rf {} +`): a same-size edit reverted within the same
second leaves a cache the runtime trusts, and the suite then runs the
mutated code (two consecutive runs, 2026-10).
## Result            (implementer writes)
## Verification      (overseer or verifier writes: captured output)
```

Write `Acceptance` before spawning the implementer, never after.
`BASE` is the commit a task starts from. Run every Acceptance command
yourself at `BASE`, in the checkout the implementer will use, before
dispatch. These rules apply to every task:

- Each command's `Expect:` line says whether the command must fail at
  `BASE` (a change check) or pass at `BASE` (a guard, e.g. the full
  suite). Keep the `Command:`/`Expect:` line format, which the judge
  parses.
- A change check that already prints its Expect at `BASE`, or any
  command that errors for a reason other than the missing change, is
  a spec defect: fix the spec before dispatch.
- An acceptance criterion you cannot express as a command with
  expected output is not concrete enough for a less capable model.
- An acceptance command must fail when the thing it checks fails.
- Scope and clean-tree checks compare against the task's own commit,
  never `HEAD`. The implementer records `BASE` in `Result` before its
  first edit, and the fix sha at commit. The overseer's ledger commits
  land on top within minutes and turn every HEAD-based check into a
  false fail (seen in two runs).
- After a task that changes a shared gate (a lint rule, a test count,
  a schema) is accepted, re-read the Acceptance of every open task
  that runs that gate.
- Two tasks whose `Allowed` lists overlap are one task
  mis-partitioned, or they run serially.
- An implementer reports a deviation from the spec in Result; it
  never decides one, not even with a marked comment in the code.

Then read `resources/spec-pitfalls.md`, before you plan. It holds
the specific traps, grouped by the kind of task: shell traps in
acceptance commands, scope, what a spec must state, tests that cannot
fail, and the scripts you supply. Most cost a run a review round or a
false accept. Check every task file against the groups that apply to
it. A task file written without that file is a spec defect.

## Review file

Every round file has this layout, exactly. The reviewer and the
implementer never load this skill, so the layout reaches them only
through you: quote the block below in the reviewer brief and in the
implementer's review dispatch brief, every round.

```markdown
# Task 003, round 1

### R1-01: Limiter ignores the burst setting

- file: src/limiter.py
- severity: blocking
- status: open

`src/limiter.py:41` reads `rate` and never reads `burst`, so a burst
of 20 is throttled like a burst of 1. Repro: `uv run pytest -k burst`.

- response: fixed in abc1234. The limiter now reads `burst` from
  config; `tests/test_limiter.py::test_burst` covers it.

### R1-02: No test covers a zero rate

- severity: minor
- status: open

A rate of 0 is not exercised by any test.

- response: evidence: `tests/test_limiter.py:88` asserts that a zero
  rate raises `ValueError`.

---

verdict: changes
```

- The reviewer writes the header, the metadata, and the finding. The
  header is `### R<round>-<nn>: title`: three hashes, then a colon.
- The metadata is one block of lower-case list lines directly under
  the header. `severity` and `status` are required. `file` is left out
  when a finding is not about one file.
- The implementer writes one `- response:` line under the finding and
  indents every continuation line two spaces. It opens with what the
  reply does: `fixed in <sha>`, `evidence:`, or `concern:`. A later
  reply to the same item is another `- response:` line.
- The reviewer ends the file with a `---` line and then `verdict:
  changes` or `verdict: approve`, and writes them last. `approve`
  means the round has no `blocking` item. A clean round is the title
  and this block. Responses go above the `---`.

The layout is what makes an item addressable, and it is the only
layout the judge parses. A reply written any other way (`Response
(fixed, abc1234): ...`, a `#### Response` header, bare `Severity:`
lines) reads fine to a person and is invisible to a tool: in two runs
every round file was improvised, and the judge reported every answered
item as unanswered.

## Workflow

1. **Startup check.** First finish Preconditions and roster: load
   the driver, verify overseer mode, load the roster. Then read every
   lease in `.overseer/active/`. For
   each, tell the user the run id, harness, age, and claims; never
   remove one, stale or not. Then write your own lease. Another lease
   means a worktree for every implementer, whatever `list()` shows,
   and a resource another lease claims is touched only with the
   user's approval. `list()` sees one harness; the lease is how two
   overseers on different harnesses find each other. Then read the
   local rules file (under Lessons), if it exists.
2. **Recon and plan.** Read `resources/spec-pitfalls.md` first.
   Explore the repo cheaply yourself (this is
   reading, not implementing). Write `PLAN.md`: task breakdown, each
   task with explicit file paths and acceptance criteria concrete
   enough for a less capable model. No ambiguity — implementers execute
   specs, they do not interpret intent. Write the task files now.
3. **Plan critic** (if reviewer configured). Spawn from
   the reviewer entry; brief: read `PLAN.md` and `tasks/`, write
   `review/plan.md` listing contradictions between plan and tasks,
   acceptance criteria that could be read two ways, allowlist overlap,
   and criteria that cannot fail. Also ask for the degenerate
   cardinalities (0, 1 and 2 of every account, identity, member or
   row) and for one value that is two things at once (an address that
   is both an identity and an alias, in one account and across two):
   those were the critic's best catches in two consecutive runs.
   Also ask the critic to recompute
   every expected value and event sequence the task files prescribe,
   working from the rule as written rather than checking that the
   tests compile. In two consecutive runs, one of the overseer's
   hand-derived expectations was wrong. Fix the spec, then retire it. With
   a judge on the roster, lint each task file with it first
   (`resources/judge.md`). The critic then starts from cleaner specs.
4. **Gate 1: user approves the plan.** Do not spawn implementers
   before approval. Announce the gate (below).
5. **Set up your agent layout**, if your harness has one (below),
   launch implementers, assign one task file each using the dispatch
   ritual.
6. **Wait, verify, iterate.** Wait in bounded intervals with a health
   check between (see "Implementer health watch"). Completion is an
   artifact, not a status: the task file has a `Result` section and
   `git log` shows the task's commit. Then verify it yourself by
   execution: run the `Acceptance` command in a fresh session, paste
   the captured output under `Verification`. Never accept "tests pass"
   from a transcript. Output matches `Expect` (and the verifier
   passed, when gated in): set `Status: accepted`, update `STATE.md`,
   retire the implementer session. Otherwise the task goes back to
   the implementer with the captured output as the defect report.
7. **Verifier** (when gated in). Spawn from the reviewer entry in a
   fresh session; brief: the task file path and the diff, nothing
   else. It runs `Acceptance` and `Smoke`, writes pass/fail with
   output under `Verification`, and retires. A fail goes back to the
   implementer as a spec-referenced defect. Run the verifier after the
   reviewer's mutation pass, never alongside it, and keep implementers'
   suites off the box while it runs. Under shared load, timeouts and
   timing checks fail spuriously; three runs paid for re-runs.
8. **Review rounds** (if reviewer enabled), per the loop below.
9. **Gate 3: final acceptance.** Repeat the base check from On
   resume. Check the whole product against
   `PLAN.md`, run the full suite, append this run's `LESSONS` to
   `.overseer/LESSONS.md`, promote any repeated friction (under
   Lessons), delete your lease, and report to the user
   with evidence. The report lists each decision you made for the
   user: an adjudication, a review you skipped, a deviation you
   accepted, a merge choice. It also quotes each rule you added to
   the local rules file. Announce the gate (below).

## Verification evidence

Each report claim names the command or assertion that establishes it.
Nonverbose test output establishes package success, not zero skipped
tests. An HTTP 200 or port check establishes reachability, not the
served build; compare a build identifier or the served artifact bytes.
For negative-path suites, passing assertions establish expected rejection
and recovery, not an absence of failed HTTP requests.

## Dispatch ritual

Follow your driver's dispatch ritual: how to confirm the agent is
ready, how to deliver the task, and how to confirm the task took.
Never assume a dispatch took. Then, for every dispatch:

1. After editing a task file, read the task file back and confirm the
   edit landed before sending the nudge (twice in one run a
   scripted replace failed after the nudge went out and the
   implementer read the old spec).
2. After any wait returns, check the artifact before the status: task
   file `Status`/`Result`, then `git log -1`. A `done` status with an
   untouched task file is not completion (rate-limit backoff and API
   errors both produce it).
3. A wait that times out, or returns without artifact progress: ask
   your driver for whatever diagnostic it offers, then read the
   transcript. Find the cause before re-dispatching; a re-prompt on
   top of an unread error repeats it.

## Isolation and layout

Concurrent tasks always have disjoint `Allowed` lists; overlap is
fixed in the plan (repartition or serialize), never by worktrees.
Given disjoint tasks, two implementers may share the main checkout
only when `list()` shows no other live session working in that repo.
Another live session in the repo, or three or more concurrent
implementers, means one worktree per agent, and you own the merge.
Never switch branches in a shared checkout without that `list()`
check. Nothing of yours lands on a checkout an implementer is in, not
a one-line edit and not a docs-only commit: an edit fails the gate on
the half-built tree, and a commit moves `HEAD` under the implementer
and breaks its BASE-relative scope check (one run once, this
rule's second run twice). Queue it for the merge window, and verify a
task's scope against its commit's parent. Another run's lease in `.overseer/active/` is another live
session whatever `list()` shows, so it forces worktrees too. While
one exists, push only your own commits (`git push origin
<sha>:<branch>`, never the branch): a branch push publishes the other
run's unpushed work. If its commits sit below yours on the branch, a
sha push publishes them anyway; ask the user first. Parallelism
follows from independent task boundaries in the plan, never from
available session slots.

If your harness has a visual layout (tabs, panes, windows), arrange
agents so the reviewer never shares space with an implementer and you
can tell at a glance what is running; your driver gives a concrete
scheme. On a headless harness with no such concept, skip this and
name/label agents by task instead so `list()` output stays legible.

## Implementer health watch

Cheap models degrade. The signature: output flips — often abruptly,
mid-task, at modest context usage — into repetition loops or
multilingual token salad, while `status` still reads `working` and
the token counter keeps climbing. Status fields detect stalls, not
madness; only transcript content does.

- **Watch.** Never block one long blind wait. Wait in bounded
  intervals (10–15 minutes); on every expiry — and on every wait that
  fires — `read` the last ~30 lines of output and check progress
  (owned-path file mtimes, task-file status). Judge the content:
  `working` plus gibberish, or `working` plus zero file progress
  across two consecutive checks, is degradation. With a judge on the
  roster, a `working` verdict at 0.9 or higher replaces the 30-line
  read, never the progress check (`resources/judge.md`).
- **Interrupt immediately** on that judgment (`interrupt`, or kill the
  session). Every further second burns tokens on salad.
- **Never re-prompt a degraded session.** Not "please continue," not a
  re-nudge of the task — the garbage is in its context and every next
  response is conditioned on it. A degraded session never recovers.
  The session is dead; only the slot is reusable.
- **A stop is not degradation.** A session stopped by a transient
  harness tool error, with a coherent transcript, is not degraded.
  Re-prompt it once with the task nudge; treat a second stop like
  any failed dispatch. Judge degradation by transcript content, not
  by a stop.
- **Recover with a fresh session on the same task file.** The resume
  prompt states that the predecessor degraded, the state of play
  (files present, what fails), and orders an AUDIT of the inherited
  work against the spec — never blind trust. Before dispatching, scan
  `git status`/`diff` for out-of-scope or suspect edits and confirm
  read-only reference material is untouched. Partial work is usually
  sound up to the stall point; an auditing resume both salvages it and
  tends to catch real bugs the dying session was circling.
- **Prevent and record.** One task per implementer session: retire the
  session when its task is accepted, spawn fresh for the next
  assignment. Log every degradation in `STATE.md` (which agent, task,
  what the transcript looked like) so the pattern stays visible across
  resumes and to the user.

## Review loop

The reviewer brief: read the diff against the task spec and `PLAN.md`;
report gaps that affect correctness, the stated acceptance criteria, or
scope (changes outside `Allowed`); do not report style preferences.
Mark each finding `blocking` or `minor`. Write the round file in the
Review file layout, quoted in the brief. For each new test, the
reviewer applies the mutation the implementer named in Result (or
one it chooses, under the same conditions as the Task file rule) on
a scratch copy and runs the test; a test that still passes is a
`blocking` finding. The scratch copy is a disposable copy (for
example a `git worktree` of the fix commit in a temp directory); the
reviewer never edits the reviewed checkout.

From round 2 on, the review scope is two things. The first is the
items of earlier rounds that are neither `resolved` nor `rebutted`,
named by id. The second is the diff from the commit the previous round
reviewed to the fix commit. The rest of the brief is the round 1
brief, mutation runs and layout included. The reviewer checks each
named fix and reviews that diff. A fix that does not hold becomes a
new item that cites the old id. A second full read of code that
round 1 passed raises new items, and step 5 then reads them as a
deadlock. A debt-forced round keeps its whole-span scope.

1. Reviewer writes per-item findings to `review/round-N.md` and ends
   the file with the verdict block. A round file with no `verdict:`
   line is an unfinished review, never a pass: a reviewer that stopped
   after the title leaves the same file as one that found nothing.
   Treat it as a wait that returned without its artifact (Dispatch
   ritual, step 3).
2. Implementer addresses or rebuts each item in place, as a
   `- response:` line in the Review file layout. A rebuttal is
   typed `evidence` (a code citation, a test, a repro) or `concern`
   (an argument). Only an evidence rebuttal can move an item to
   `rebutted`; a concern leaves it `open` for the next round. With a
   judge on the roster, run it on the round file once the implementer
   is done (`resources/judge.md`). It types each response and flags
   items that got none.
3. An item may be rebutted at most twice: once in the round it first
   appeared, once in the round after. A third response is not a
   rebuttal; the item goes to adjudication.
4. A factual disagreement (about behavior, not style) that survives
   the item's first rebuttal must produce a runnable check — a test
   or repro script — before it gets another round. Evidence beats
   argument.
5. The count of `blocking` items still open must strictly decrease
   from one round to the next. If it does not, the round is
   deadlocked: stop the loop and adjudicate.
6. Still deadlocked: you adjudicate on the evidence. Escalate to the
   user only for preference or scope calls, or genuine uncertainty.

You may verify a small fix by replaying the reviewer's reproduction
instead of running a new round. All of these must hold: the finding
named a reproduction (a mutation, a probe test, a command); the fix
is a few lines and its diff stays inside the code the finding named;
the reproduction gives the right result for its kind. For a behavior
finding (a probe test, a command), it fails before the fix and
passes after it. For a vacuous-test finding (a mutation the test
missed), the reviewer's round-1 record shows the test passing under
the mutation; after the fix the unmutated test passes and the
mutated run fails on the test's own assertion. Reviewer probes and
mutation scripts usually hard-code the reviewer's scratch checkout and
port: repoint them to a disposable checkout of the fix commit before
replaying (seen in two runs). A probe that now fails only
because the fix legitimately added a second match (a hidden duplicate
element) is adapted to count visible matches, and the adaptation is
recorded. Print the diff of every replay mutation and check it is
non-empty before the run: a `sed` that matches nothing (a call that
spans two lines, a guessed variable name) leaves the code unmutated,
and the passing run proves nothing (three misses in one run).
Record the captured
output in the task's `Verification` as "verified by overseer,
round-N repro", and set the item's `- status:` to `resolved` in the
round file (add no other line to the round file). `last reviewed:`
in `STATE.md` does not advance past the fix, so the next review
round covers it. Anything larger, or a fix touching code the finding
did not name, goes back to the reviewer. This replays the reviewer's
own check; it is not the overseer reviewing its own work, so it does
not contradict the red flag about substituting for the reviewer.

If review stalls or an implementer flounders, you fix the *spec* or
reassign the *task* — you do not take over the implementation. Doing
the work yourself is the expensive failure mode this setup exists to
prevent. When a finding traces to a hole in your spec, say so in the
review file and fix the task file before the implementer touches code.

## Human-in-the-loop points

Exactly three: plan approval before implementation (Gate 1), a
deadlock you cannot settle (Gate 2, as often as one occurs), final
acceptance (Gate 3). Everything else is yours to decide.
Announce each through `notify`, if your harness offers it, so the
user is not the monitor; if it doesn't, announce it the way your
driver gives, or failing that directly in your own reply. Reserve whatever "urgent" signal `notify` offers for
these three gates and nothing else; a gate signal that also fires on
routine progress trains the user to ignore it.

## Lessons

At Gate 3, append a `LESSONS` section for this run to
`.overseer/LESSONS.md` (`>>`, never a rewrite): what cost the most
this run, which spec defects caused review rounds, any tooling quirk.
Then check the previous run's section, directly above yours (or your
own longer-term notes, if you keep them). A friction that appears in
two runs is promoted in the same session: append it as a rule to the
local rules file, not as another memory note.

The local rules file is the user's own, shared by every repo on the
machine:

```
${XDG_CONFIG_HOME:-$HOME/.config}/overseer/rules.md
%APPDATA%\overseer\rules.md                          # Windows
```

Create it if it is missing. One rule is one bullet: the instruction,
then the two runs that paid for it and today's date. Do not add a
rule that is there already. Read the file at every start and resume,
and follow its rules as you follow this skill. A local rule adds to
this skill. It never removes a gate or a check: if one tries to,
follow this skill and tell the user. A lesson never goes into this
skill's own files: they are an installed copy, and a local edit
blocks the next update.
Four memory notes recorded the swallowed-Enter bug before one rule
replaced them; that is the loop this section closes.

## Red flags — stop and correct course

- Pasting a diff, review, or task body into another agent's prompt
  ("just this once") — point at the file instead.
- Writing implementation code because "the fix is small" or "review
  isn't converging" — respec or reassign instead.
- Accepting "all tests pass" from a transcript instead of running the
  acceptance command yourself and pasting the output.
- Treating `status` (`done`, `idle`) as completion when the task file
  has no `Result` or `git log` shows no commit.
- Trusting a dispatch without confirming `status` flips to `working`
  afterward.
- Pressing Enter on input-box text you did not send. It may be the
  agent's greyed-out suggestion. Read with styling preserved first.
- Reviewer sharing space (tab, pane, session) with an implementer, on
  harnesses where that concept exists.
- Spawning implementers before the user approved `PLAN.md`.
- Spawning a verifier for a task with no smoke command and no
  subsystem scope.
- Polling `read` in a tight loop instead of a bounded wait for
  `status` — bounded-interval health sampling is required, tight
  polling is not.
- An unbounded (or hour-long) blind wait on a working agent with no
  interim transcript check.
- Prompting a session whose output has turned incoherent — kill and
  respawn instead; trusting `status: working` over what the transcript
  actually says.
- Reading full scrollback when a bounded `read` or the files answer it.
- A task spec an implementer must interpret ("improve error handling")
  rather than execute ("wrap X in Y, return Z on failure"), or one
  whose acceptance is not a command with expected output.
- Treating your own test runs and diff reads as a substitute for the
  reviewer — the mind that wrote the spec cannot see its own seams.
- Reading a round file with no `verdict:` line as a clean review.
- Resuming a session without checking the roster in `STATE.md`
  against `list()`.
- Switching branches in a shared checkout without a `list()` check.
- Writing any ledger file before your lease, or moving, archiving,
  or editing a ledger file another run created.
- Writing a lesson into this skill's own files. A promoted lesson
  goes in the local rules file.
- Restarting a server, pushing a branch, or resetting a database that
  another live lease claims, without the user's approval.
