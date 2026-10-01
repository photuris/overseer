# Judge (optional)

`overseer-judge` is a small CLI that turns three of your recurring
judgments into typed JSON verdicts from a fast classification model
(TypeSafe's Jev). It costs a fraction of a cent and about half a
second per call. It exists to save your attention on the common case,
not to make decisions for you.

Source: [`github.com/photuris/overseer-judge`][overseer-judge]. Install
a prebuilt binary from its [releases page][overseer-judge-releases]
(this repository's README has the one-line install commands), or
build from source with `cargo install --git
https://github.com/photuris/overseer-judge --locked`. It
reads its API key from `TYPESAFE_API_KEY`, else from `~/.config/jev`.
Run `overseer-judge <verb> --help` for flags. Every verb accepts
`--dry-run`, which prints the request and makes no network call.

[overseer-judge]: https://github.com/photuris/overseer-judge
[overseer-judge-releases]: https://github.com/photuris/overseer-judge/releases/latest

## Rules that hold for every use

- **It is on the roster or it is not.** `OVERSEER_JUDGE` unset means
  this file does not apply. Do every step the way the skill says.
- **It sends content off the machine.** Pane text, task files, and
  review files go to a third-party API. Never put it on the roster for
  work whose content must not leave the machine.
- **It fails open.** A non-zero exit, or output that is not JSON,
  means do that step yourself, the way the skill says. Note the
  failure once in `STATE.md`. Do not retry in a loop. Never pause a
  run because the judge is down.
- **The gate is 0.9.** A verdict with confidence below 0.9 is no
  verdict. Do the step yourself.
- **It is advisory.** It never replaces an artifact check, an executed
  verification, a review round, or your adjudication.

## 1. Session state (the health watch and the dispatch ritual)

Feed it a bounded pane read with styling preserved. Styling matters:
it is how the tool drops an agent's greyed-out prompt suggestion.

```bash
multiplexer-driver --harness <harness> pane read <handle> --lines 60 --ansi \
  | jq -r .output \
  | $OVERSEER_JUDGE session --input - --agent <kind>
```

`<kind>` is `claude`, `codex`, `pi`, `opencode`, or `unknown`. The
output has `state`, `confidence`, `input_line` (what sits in the
agent's input box), and `activity_hint` (the agent's own busy
indicator, or empty). Act on `state` like this:

| `state` at 0.9 or higher | What you do |
|---|---|
| `working` | Skip the 30-line read. Still check file progress. |
| `idle` | Check the artifact: `Result` section, then `git log`. Idle is not completion. |
| `dialog` | `read` the pane and answer it as your driver documents. |
| `unsubmitted` | `input_line` shows the text. Your nudge: resubmit it. Anything else: `read` and decide. |
| `error` | `read` the transcript and fix the cause before any re-dispatch. |
| `degraded` | `read` the tail yourself. Interrupt only if you agree. |

Three limits:

- Never interrupt on a `degraded` verdict alone. The tool has been
  tested on synthetic degraded output only, never a real one.
- The judge cannot see files. `working` with zero file progress across
  two checks is still degradation, as the skill says.
- Use `state`. The separate `coherent` score reads low on screens that
  are mostly logo or chrome and is not an alarm on its own.

## 2. Task files (before the plan critic and Gate 1)

```bash
$OVERSEER_JUDGE task .overseer/tasks/003-rate-limit.md
```

It parses only the task-file template in the skill. Act like this:

- Any entry in `static` with `"ok": false`: fix the task file. These
  checks are deterministic (sections, order, `Allowed:`, every
  `Command:` has an `Expect:`, a numeric budget).
- `judgments.needs_interpretation` above 0.5: the objective or spec
  leaves a design decision to the implementer. Name the concrete
  things that will exist.
- `judgments.scope_generic` above 0.5: `Out of scope` is boilerplate.
  Name the tempting adjacent work.
- `acceptance.score` below 2.2, on a scale of 0 to 3: an `Expect:`
  line would pass on a wrong implementation. Make it assert a specific
  result. A vague objective drags this score down too, so read the
  two together.

This supplements the plan critic. It does not replace it: it reads
one file at a time and cannot see contradictions between files.

## 3. Review rounds (after the implementer responds)

```bash
$OVERSEER_JUDGE review .overseer/review/round-2.md
```

It parses only the Review file layout in the skill, and prints one
JSON line per `### R<n>-<nn>:` item. This section needs
`overseer-judge` 0.3.0 or later. Check the parse before you act on a
verdict:

- Exit 2 with `no review items`: no header in the file matched the
  layout. Read the round yourself, as for any judge failure, and
  quote the layout in the next brief.
- A `warnings` field on an item: part of that item did not parse, so
  the judge's verdict on it does not count. This is not a missing
  response. Do not send the item back. Read the item yourself. The
  field is absent when the item parsed in full.

| Warning | What did not parse |
|---|---|
| `missing_severity`, `missing_status` | That metadata line is absent, or not a lower-case list line. |
| `unparsed_response` | A reply sits in the finding in another spelling. The judge saw no reply, and scored `style_only` on finding plus reply. |
| `text_after_response` | A continuation line was not indented two spaces. The judge dropped the rest of that reply. |

Then act like this:

- `"responses": []` on an open item with no `warnings`: the
  implementer did not respond under that item. Send it back. A fix
  described only in the task file's `Result` leaves the round file
  without a record.
- `style_only` above 0.5: the finding is outside the reviewer brief.
  Set it aside unless you disagree.
- A response of kind `concern`: the item stays `open` (review loop
  rule 2). Kind `evidence`: check the citation yourself before you
  mark it `rebutted`. Kind `fixed`: verify by execution, as always.
- A response kind with confidence below 0.9: read that response
  yourself.

The judge types a response. It never says who is right.

## Keep the evidence

The tool's fixtures are mostly synthetic, so real disagreements are
worth more than any test. When the judge errors, or its verdict
differs from your own read, save both and note it in `STATE.md`:

```bash
mkdir -p .overseer/judge
multiplexer-driver --harness <harness> pane read <handle> --lines 60 --ansi \
  | jq -r .output > .overseer/judge/003-impl-idle-vs-working.ansi
$OVERSEER_JUDGE session --input .overseer/judge/003-impl-idle-vs-working.ansi \
  --agent <kind> > .overseer/judge/003-impl-idle-vs-working.json
```

Name the file for what you saw against what it said. Also save the
capture whenever you judge a pane degraded yourself, judge or no
judge: no real degraded transcript exists yet.
