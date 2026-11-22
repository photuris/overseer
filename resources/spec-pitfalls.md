# Spec pitfalls

Read this file before you write the first task file of a run. Read it
again before you write or change a task file after a resume. Most
rules here cost a run a review round, a blocked implementer, or a
false accept. `SKILL.md` holds the general rules for a task file. This
file holds the specific traps, grouped by the kind of task.

For each task, find the groups that apply and check the task file
against every rule in them:

| Group | Applies when |
|-------|--------------|
| [Acceptance commands](#acceptance-commands) | Always |
| [Scope](#scope) | Always |
| [What the spec must state](#what-the-spec-must-state) | The task adds a function, a queue or cache, stateful UI, a deferred action, user JSON, or platform-gated code or tests |
| [Tests the spec asks for](#tests-the-spec-asks-for) | The task adds or changes a test |
| [Scripts you write](#scripts-you-write) | You supply an acceptance script, a smoke script, a probe test, or shell for a remote or privileged step |

Most rules end with what happened when a run did not follow them.

Some rules act after the spec is written: at acceptance, or before
Gate 3. When one applies, write it into the task file or `PLAN.md`, so
that it is still in front of you then.

## Acceptance commands

- **Compare every number in the spec with what the dry run at `BASE`
  prints.** The dry run exposes a miscounted number: a count that
  includes a trailing comma, a test file that holds fewer tests than
  the spec says. *Seen:* in two runs the dry run caught one before an
  implementer took the blame.
- **Put `set -o pipefail` in front of every pipeline.** Without it,
  `go test ./... | tail -5` exits 0 on a failed test.
- **Do not write a count check as `test "$(cmd | grep -c X)" = N`.**
  It discards the exit status of `cmd`, even under `pipefail`. Capture
  the output, test the status, then test the count. *Seen:* two runs.
- **Assert an exit code against a built binary.** Never assert it
  through a runner that rewrites it: `go run` turns every non-zero
  exit into 1. *Seen:* three runs.
- **Let a grep over `go test -v` output allow Go's duration suffix.**
  The line is `--- PASS: TestName (0.00s)`, so end the pattern in
  ` \(`, never `$`. That form is for `grep -E`. Plain `grep` takes
  ` (`. *Seen:* every task in one run had this defect.
- **Do not use `python -m compileall` alone as the change check for a
  new module.** It exits 0 on a path that does not exist. Put
  `python -c "import <module>"` in front of it. *Seen:* two runs.
- **Name files in a Vitest count, not directories.** Use a directory
  count only after you checked it with `ls`.
- **Make a full web suite that runs as a guard name its failing
  files.** For Vitest: `--reporter=json --outputFile.json=<log>`. A
  `tail` of the default output names none. Under another run's load,
  give it a longer `--testTimeout`. A failure is real only after a
  quiet rerun of that file. *Seen:* three unexplained failing runs
  across two runs, one caused by a neighbor's merge in the middle of
  the suite.

## Scope

- **Put every test that pins what the spec changes in `Allowed`.**
  Before dispatch, grep the tests for whatever the spec changes. List
  each test with the one edit it needs. Look for these:
  - a whole-value comparison of a struct that gains a field
  - a class name the spec removes
  - a label an end-to-end spec selects by
  - a golden list of every member of the set the spec adds to (routes,
    operation ids, tables)

  *Seen:* four runs.
- **Treat a grep from a work list as a lower bound, not the
  inventory.** A work list gives a grep for a forbidden pattern.
  Before planning, widen it to the other spellings of the same rule:
  an equality, a list `includes`, a `switch`, a set lookup. Put every
  hit in scope or in the report. *Seen:* two runs missed role lists
  written as `includes`.
- **Before a task edits a script, check whether a live timer or unit
  runs that file from the checkout.** If one does, the first commit is
  a deploy. *Seen:* an hourly publish failed for hours on a new
  default path.

## What the spec must state

- **For every new function the spec names, state three inputs and
  what each yields.** The inputs are the empty input, the
  whitespace-only input, and the duplicated input. Do this before the
  critic sees the spec. *Seen:* in two consecutive runs, every
  blocking critic finding was one of these left unsaid.
- **For an in-run queue or cache keyed by a shared identifier, list
  every exit path of the per-record function.** A shared identifier
  is, for example, a company GUID or an alert id. Include the early
  skips. Say what each path does to an entry that an earlier record
  left under the same key. *Seen:* the reviewer's blocking finding in
  two runs.
- **For stateful UI, list the transitions as a table: state, event,
  next state.** Stateful UI is a form, a guard, a stale-read notice,
  or a gate. Include these rows:
  - a second failure while already in the failure state
  - recovery
  - a remount
  - a second form that opens over a dirty one
  - an edit made while a save is in flight

  *Seen:* two runs paid review rounds for missing rows.
- **For a task that acts later on something it observed earlier, make
  it read its target again when it acts.** Examples are a queued
  notification, a deferred click, a pending confirmation, and a timer.
  The task reads the target from the source of truth. The spec names
  the identity checks for that moment: which device or account owns
  the target, and a stable key rather than a reusable slot. Keep that
  decision in code that takes the clock as an argument. *Seen:* two
  runs paid review and critic rounds for this.
- **For a task that carries arbitrary user JSON, state its numeric
  precision contract.** Check a large integer and a precise decimal
  through the actual transport and the stored record, plus an
  unrelated UI edit. Fields the person did not change stay out of the
  patch. Typed decoding can otherwise rewrite them.
- **Do not accept platform-gated code or tests on local results
  alone.** Platform gates are `#[cfg(unix)]`, build tags, and a
  Windows-only branch. Run the other platform's CI, or a cross-target
  lint, first. A Linux machine cannot see an import used only under
  another `cfg`, or a CRLF checkout that changes fixture bytes. Commit
  a `.gitattributes` that pins line endings before fixtures land.
  *Seen:* two projects, each in its second run.

## Tests the spec asks for

- **Copy a test idiom from an existing test in the repo before the
  spec prescribes it.** This applies to an assertion and to a query
  option. jest-dom matchers (`toHaveAttribute`, `toBeDisabled`) and
  options like `exact` on `getByRole` are often absent or fail
  typecheck. *Seen:* two runs.
- **Give a test for one branch of an OR a fixture that satisfies only
  that branch.** An OR is a filter, a posture rule, or a permission. A
  row that also satisfies another branch masks the removal of the
  branch under test.
- **Make a toggle test turn the control on from off, not only off
  from on.** *Seen:* four vacuous tests across two runs.
- **Assert the value the rule requires, not that a value changed.**
  - Bracket a written timestamp between clock reads taken around the
    request.
  - Check a null field after the status and the presence of the key.
    An index into a missing key reads as null on an error body.
  - Compare a link or token sent elsewhere with the string actually
    sent, never with one the test rebuilds.

  *Seen:* five such tests survived mutation across two runs.
- **Name in the task spec the response helper that every test reads
  through.** The helper asserts the status and the presence of the key
  before it returns the value. The reviewer flags any field read
  outside it. The rule in a brief is not enough. *Seen:* seven
  more such tests in three tasks whose briefs carried the rule.
- **Make a test of code that sends a request assert the request it
  sent.** This applies to a mock and to a fake server. Assert the
  exact body, patch, or parameters. It is not enough that a call
  matched by method or id and that the parsed result looks right.
  *Seen:* in two runs an id-only matcher let a wrong payload pass.
- **Test a query that filters by owner with a second owner's competing
  rows.** An owner is a user, tenant, or account id. Put the competing
  rows in every table the query reads, and assert the exact rows
  returned. Otherwise the tests pass with the owner predicate deleted.
  *Seen:* two tasks in one run. The authorization matrix did not catch
  it, because it checks who may call a route, not which rows come
  back.
- **Make a wait in a test a time deadline, never a count of polls.** A
  loaded machine uses up a poll count early.
- **Disable the lower layer when a test covers a filter that the lower
  layer also enforces.** The lower layer is row-level security, a
  middleware, or a foreign key. Disable it in a rolled-back
  transaction. Otherwise the removal of the filter passes unnoticed.
  *Seen:* two runs.
- **Make a UI test wait for something the refresh visibly changes
  before it asserts after an asynchronous refresh.** Otherwise it
  asserts on the DOM from before the refresh, and passes whatever the
  refresh does. *Seen:* three of the five tests that could not fail
  in one run.
- **Apply the same rule to a first load.** An absence check, a count
  of zero, or a layout measurement first waits for a positive marker
  of loaded data, such as a row known to exist. Otherwise it passes on
  a loading or error state. *Seen:* in two runs, an empty-state check
  and zoom measurements ran before the list arrived.
- **Make a test that creates a privileged resource register its
  cleanup before it creates anything.** A privileged resource is a
  database role, an admin connection, or a credential. *Seen:* one
  run left 14 roles with a known password on a local Postgres.

## Scripts you write

- **Run your own acceptance script twice before dispatch.** Such a
  script is a corpus checker, a diff limiter, or a count. Run it once
  on a known-good input and once on an injected fault. It must pass
  the first and catch the second. *Seen:* three such scripts in two
  runs, each wrong on first run, two of them failing open.
- **Dry-run the navigation of your own smoke script against the dev
  stack before dispatch.** Navigation is the login and the path to the
  target screen. *Seen:* selectors guessed from code failed on first
  run in two runs.
- **Dry-run a whole device smoke script on an emulator, then once on
  the target phone, before Gate 3.** This applies to an Android
  WebView. Budget for it in the schedule. Names, gestures, and the
  visible-only snapshot differ from the browser. *Seen:* drafts failed
  for a dozen or more attempts in two runs.
- **Start swipes inside the screen, away from its edges.** A phone
  with gesture navigation reads an edge swipe as Back. An emulator
  with three buttons does not. *Seen:* one run.
- **Make a smoke script stop its server by listening port or process
  group.** Never use `pkill -f` or `pgrep -f`: the pattern also
  matches the command line of the calling shell and kills it (exit
  144). *Seen:* two consecutive runs.
- **When the spec prescribes shell for a remote or privileged step,
  treat your own text as the likeliest defect.** Examples are an
  install over `ssh` and `sudo`, and a guard that decides whether to
  replace a file. The spec does these:
  - lists every external tool the script calls
  - has a test with each tool missing
  - has a test with each tool failing after it printed output

  The script does these:
  - opens no file with truncation
  - refuses a symbolic link where it creates one

  *Seen:* in two consecutive runs, every blocking review finding on
  such a script was in text the overseer supplied "verbatim".
- **Have the plan critic check the expected values of every probe
  test against the behavioral source before Gate 1.** A probe test is
  a black-box test that you write. The task's Acceptance copies it
  into the package, and the implementer can never edit it. It raises
  the judge's acceptance score and gives the verifier a contract
  independent of the implementer's tests. Its failure mode is your own
  reading of the behavioral contract, so a check that it compiles is
  not enough. When the implementer reports a probe failure with a
  reproduction from the original, treat it as a probe defect first.
  *Seen:* in two consecutive runs a probe asserted a value the
  contract did not support (a row count the original emitted twice,
  and path assertions that ignored URL normalization). The implementer
  was blocked until the probe was corrected.
