# Lessons from run fix-1 (bespoke-grc, 2026-10-01)

Written by the overseer of that run for whoever folds these into the
skill. The run: 18 tasks fixing 29 of 31 findings from an external
code review, Sonnet 5.5 implementers (Opus for two frontend tasks),
GPT-6.1-Sol reviewer and critic, `overseer-judge 0.2.0`, Herdr. The
ledger is at `~/Projects/personal/bespoke-grc/.overseer/` (`STATE.md`,
"LESSONS (run fix-1)", and `tasks/113-*` to `tasks/130-*`).

Each item below says what happened, what it cost, what I checked in
the skill at `1dd7379` (2026-10-03), and what I propose. Check the
skill again before editing; it moved 16 commits between the run and
this file.

## Already covered since the run

- **The judge's review layout.** `SKILL.md` "Review file" now
  quotes the exact layout and says to put it in every reviewer and
  implementer brief. `resources/judge.md` documents the `warnings`
  field and exit 2 on a file with no items. `overseer-judge 0.3.1`
  flags the run's old layout: on
  `.overseer/review/round-1-122.md` it prints `missing_severity`,
  `missing_status`, `unparsed_response` for every item. Nothing left
  to do here except one line, below (item 5).
- **The ledger symlink prompt.** `resources/herdr.md` now says to
  answer it with `herdr agent send-keys <name> 2`. That is the manual
  answer; item 2 is about not doing it by hand.

## 1. Acceptance commands that cannot do their job

**What happened.** Five Acceptance defects in the task files, all
mine, all found late: literal `BASE FIX` in a `git diff` that passed
on a failed git (the plan critic caught it); a devDependencies count
that counted a trailing comma; a test count of 17 for a file holding
13 tests; a lint check missing from the docs task; a stale
`--disable lll` left in task 120 after task 118 turned `lll` on.
Run judge-1 had two of the same kind. Each one cost either a critic
round or a false fail on an implementer's correct work.

**What the skill says.** The "Task file" section lists specific past
defects (duration suffix, `pipefail`, `go run` exit codes, Vitest
counts). It has no general rule that the overseer runs the commands.

**Proposal.** Add to "Task file", after "Write `Acceptance` before
spawning the implementer":

> Run every Acceptance command yourself at `BASE` before dispatch,
> in the checkout the implementer will use. A command that errors
> for a reason other than the missing change, or that already prints
> its Expect, is a spec defect: fix the spec. After a task that
> changes a shared gate merges (a lint rule, a test count, a schema
> file), re-read the Acceptance of every task still open against it.

The dry run also catches the "count the comma" class: the number is
visible before the implementer starts.

## 2. The ledger-symlink watcher

**What happened.** Under Herdr with one worktree per implementer, the
first write through `.overseer` -> symlink raised Claude Code's
permission prompt in every implementer session, usually while it was
writing `Result`. Six times I answered by hand (`send-keys <pane> 2`)
after noticing a `blocked` status minutes late. Then I ran a watcher
script that polled `pane read`, matched the prompt text, and answered
it. Run judge-1 had the same script. Each manual answer cost the idle
minutes before I looked plus one of my turns.

**What the skill says.** `resources/herdr.md` documents the prompt
and the manual answer. No watcher.

**Proposal.** Add to `resources/herdr.md`, after the paragraph on the
symlink prompt, and keep the script beside the driver (for example
`resources/herdr-watch.sh`):

> From the first dispatch, run a watcher that reads every
> implementer pane each minute and answers `2` to a prompt whose
> text names only `.overseer/` paths and says `resolves through a
> symlink` or `make this edit to NNN-*.md`. It reports every other
> prompt to you and answers none of them.

The run's script is at
`~/Projects/personal/bespoke-grc/.overseer/fix1-watch.sh`. Two
defects to fix before adopting it: it matched prompts with a regex
written in a heredoc where `\b` became a backspace byte (use
`grep -w`), and its danger list (`rm|push|curl|wget|sudo`) is a
heuristic, not a policy. The watcher must never answer anything
outside the ledger paths; that is the whole safety argument.

## 3. Tests that cannot fail

**What happened.** Five new tests across tasks 126, 127, 120, 119 and
128 passed with the fix reverted; the reviewer found each by
mutation (`vitest` on a scratch copy with one line changed). Run
calc-2 had two. Each one cost a review round, or, where I applied the
reviewer's mutation myself, a round of my own time.

**What the skill says.** The plan critic is told to look for
"criteria that cannot fail" in task files. Nothing asks the
implementer or the reviewer to do the same for tests.

**Proposal.** Two lines.

In the "Task file" `Rules` template:

> For every new test, name in Result the one-line change to the code
> under test that makes it fail, and say that you ran it.

In the reviewer brief:

> For each new test, apply the mutation the implementer named (or
> one you choose) on a scratch copy and run the test. A test that
> still passes is a blocking finding.

One pattern to call out by name, since it produced three of the
five: a UI test that asserts after an asynchronous refresh must first
wait for something the refresh visibly changed; otherwise it asserts
on the pre-refresh DOM and passes whatever the refresh does.

## 4. Verifying a small review fix by mutation instead of a round

**What happened.** Five times a review fix was a few lines plus a
test. Instead of a second reviewer round I applied the reviewer's
own mutation from round 1, confirmed the new test failed, reverted,
confirmed it passed, and accepted. Cost: a few of my turns each.
A reviewer round would have been many times that.

**What the skill says.** The review loop sends every fix back to the
reviewer for a count.

**Proposal.** Add to "Review loop":

> A fix of a few lines whose round-1 finding named a reproduction
> (a mutation, a probe test, a command) may be verified by the
> overseer repeating that reproduction, without a second round.
> Record "verified by overseer, round-1 repro" under the item.
> Anything larger, or any fix that changes code the finding did not
> name, goes back to the reviewer.

## 5. Small additions

- `resources/judge.md`: say that `warnings` also print on stderr as
  `WARN ... review item did not fully parse id=R1-01
  warning="missing_severity"`, so an overseer piping `--dry-run` to
  `jq` with `2>&1` gets a parse error: use `2>/dev/null` for the
  pipe and read stderr separately.
- "Task file": a stateful UI rule (a guard, a stale-read notice, a
  gate) gets its transitions as a table (state, event, next state)
  including "then the next failure" and "then a remount". Three
  review rounds this run (122, 124, 128) traced to a transition the
  spec never named.
- "Task file": a budget in a spec (a shutdown grace, a timeout) says
  in one sentence which waits share it. Task 119 promised one cleanup
  budget and the implementation applied it twice.
- "Dispatch ritual": edit the task file, confirm the edit landed
  (read it back), then nudge. Twice a scripted replace failed after
  the nudge had gone out and the implementer read the old spec.
- "Task file": a test that creates a privileged resource (a database
  role, an admin connection) registers its cleanup before it creates
  anything. The run left 14 roles with a known password on the local
  Postgres until review caught it.
- Roster note: Sonnet 5.5 did every backend task and most frontend
  tasks at first attempt; the two Opus tasks stopped correctly on a
  spec gap instead of working around it. A transient Claude Code
  "Bash classifier errored on three attempts" stopped two Sonnet
  sessions before their commit; a re-prompt fixed it. Worth a line
  in the health watch so it is not read as degradation.

## Not proposed

- The plan critic: paid for the fifth consecutive run (9 blocking
  before any code). Keep it; the experiment in the skill can be
  called settled.
- Loosening the judge's parser to accept improvised layouts. The
  warnings make the mismatch loud, which is enough; a forgiving
  parser trades a loud miss for a silent misread.
