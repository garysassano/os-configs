---
name: sol-oracle
description: Consult gpt-5.6-sol through the local codex-kiro CLI as an independent second reviewer on code changes, design forks, and factual claims. Use when reviewing a diff before opening or merging a PR, when a plan or issue prescribes a fix whose premise is unverified, when weighing a design decision with real trade-offs, or when the user asks for a second opinion, asks to check something with sol/codex/kiro, or asks to work back and forth with another model.
---

# Consult sol as a second reviewer

`sol` is gpt-5.6-sol, reached through the local `codex-kiro` CLI. It reads the
real working tree, so it reviews actual code rather than a description of it.

Treat it as a competent colleague whose findings must be verified, **not** as an
authority. It has been both decisively right and confidently wrong in the same
session.

## Invocation

### Keep one thread — do not start a fresh session per question

`codex-kiro exec` starts a **new session every time**. Used naively that means
sol re-derives everything from scratch on each question, forgets what it already
told you, and cannot notice that its own earlier advice was superseded. Restating
context in the next prompt is not a substitute: it is your summary of sol's
reasoning, not sol's reasoning.

Open one thread per review conversation and resume it.

**First call** — capture the session id, which the CLI prints in its header:

```bash
codex-kiro exec \
  -m gpt-5.6-sol \
  -c model_reasoning_effort="xhigh" \
  --dangerously-bypass-approvals-and-sandbox \
  -C /path/to/repo \
  -o out1.md \
  "$(cat prompt1.md)" > out1.log 2>&1

# --pcre2 is required for \K
SOL_SESSION=$(rg --pcre2 -o -m1 'session id: \K[0-9a-f-]+' out1.log)
```

**Follow-ups** — resume that exact session:

```bash
codex-kiro exec resume "$SOL_SESSION" \
  -m gpt-5.6-sol \
  -c model_reasoning_effort="xhigh" \
  --dangerously-bypass-approvals-and-sandbox \
  -o out2.md \
  "$(cat prompt2.md)" > out2.log 2>&1
```

Verified: a resumed session recalls its own prior review verbatim without
re-reading any files.

`--last` resumes the most recent session, but it filters by cwd and is ambiguous
as soon as more than one thread exists. Prefer the explicit id; reach for
`--last` only for a quick one-off follow-up.

### One session per work item

When working through a list of items — review findings, issues, a task
breakdown — the rule is:

> **All back-and-forth about one item stays in one session. A new item gets a
> new session.**

So a single item's thread covers its whole life: the initial analysis, the review
of the resulting diff, the re-review after applying fixes, and any follow-up
argument. By the final exchange sol knows what it already recommended, what you
changed in response, and what it has already ruled out — which is exactly the
context that makes the last pass worth anything.

Keep a session id per item so threads never get crossed:

```bash
declare -A SOL             # item -> session id
SOL[RUST-4]=$(rg --pcre2 -o -m1 'session id: \K[0-9a-f-]+' rust4-analysis.log)
# ...later, same item, same thread:
codex-kiro exec resume "${SOL[RUST-4]}" -m gpt-5.6-sol ... "$(cat rust4-diff-review.md)"
```

Start a new session when the item changes. A fresh thread keeps an unrelated
item's history from dragging in, and stops sol from anchoring on decisions that
do not apply.

Two items that turn out to be genuinely coupled can share a thread — say so
explicitly in the prompt rather than letting it happen by accident.

### Mechanics

- **Always run in the background.** Runs take minutes and routinely exceed ten.
  Start it, do your own analysis meanwhile, then read the output file.
- Write the prompt to a file and pass it via `"$(cat ...)"`. Long prompts get
  mangled inline.
- `-o` captures the final answer; the `.log` holds the full trace, including the
  `session id:` line you need for resuming.
- The log header echoes `model:` and `provider:`, which is how you verify the
  right model ran. Effort level is **not** echoed, so the flag is the only
  evidence for `xhigh`.
- Smoke-test once with a trivial prompt at `model_reasoning_effort="low"` before
  depending on it.

## When to consult

Consult **before shipping**, not only when planning. Reviewing a plan catches
bad premises; reviewing the diff catches bad implementations. Both matter.

Highest value:

- A diff about to become a PR — ask for an explicit ship / don't-ship verdict.
- A prescribed fix whose premise you have not verified. Plans and issues are
  frequently wrong about external limits, API behavior, and version history.
- A design fork where you can state options and want the case against your lean.
- Anything touching subtle machinery — concurrency, budgets, schemas, retries.

Low value: mechanical refactors, formatting, anything a compiler or test already
proves.

## Writing the prompt

What reliably produces useful output:

- **Say "DO NOT EDIT ANY FILES."** It respects this and reviews read-only.
- **Number questions as lettered sections** (A, B, C…). Answers come back
  section by section and stay addressable.
- **State settled decisions as given.** Write "the maintainer has decided X;
  do not relitigate it." Without this it will spend the review arguing against
  a preference the user already made, which wastes the pass.
- **Ask it to confirm or refute your own reading**, explicitly. Include your
  measurements and your tentative recommendation and invite disagreement:
  "I lean toward (a); argue against me if you disagree."
- **Ask for a verdict**: "Ship or don't ship? If don't ship, list exactly what
  must change."
- **Tell it what is committed vs uncommitted.** It reads the working tree and
  will otherwise report your in-progress edits as if they were already merged.
- Ask "what did I miss?" as its own question. This is where it earns its keep.

## Verify before acting

Never adopt a factual claim without checking it. Verified failures from real use:

- It claimed a repository had **zero configured environments**. The API returned
  two. The underlying concern was still valid but the sharper, correct finding
  (one environment existed and was entirely unprotected) came from checking.
- It correctly identified that a plan's cited AWS quotas were obsolete — but the
  thing that settled it was fetching the AWS docs directly, not its assertion.

Rules of thumb:

- **External facts** (API limits, version support, quotas): fetch the primary
  source. It is often right, and being right does not make it evidence.
- **Claims about this codebase**: check with `rg`, the API, or a probe script.
- **Claims about behavior**: prove it by experiment. Write the throwaway script.
  An empirical result outranks both of your opinions.
- **Claims a test is adequate**: mutate the code and confirm the test fails.

When it is wrong, say so plainly in your report and record the correction so it
does not propagate.

## Iterate

Send the revised diff back **on the same session** after acting on findings, so
it can judge its own earlier advice rather than re-deriving the problem. A second
pass regularly catches real bugs introduced while fixing the first pass — for
example, a `try` block widened far enough to swallow a *consumer's* error and
misreport it as a library-compatibility failure.

Within a thread the follow-up prompt can be short: "I applied your A and B; here
is the revised diff; did that close them, and did I break anything?" You no
longer need to restate the problem.

Stop when it returns ship with only optional follow-ups. If those follow-ups are
cheap and fix something you know is weak, do them anyway rather than shipping
known-weak work and filing a ticket.

## Record disagreements

When you and sol do not converge, do not silently pick one. Write both positions
down where the decision-maker will see them, each attributed, including which
argument is stronger on the merits and which is a matter of appetite or scope.

Note explicitly when a finding is one sol **has not seen** — for instance
something you discovered after its review returned. Otherwise a reader assumes
it was reviewed.

## Pitfalls

- **Do not defer by default.** The user is asking for a second opinion, not a
  second decision-maker. Push back when the evidence supports you.
- **Do not let it relitigate settled preferences.** Fence them in the prompt.
- **Do not paste its output as your answer.** Relay what matters, in your own
  words, with your own verification attached.
- **Watch for stale context.** It sees the tree at invocation time; a long run
  may return advice about code you have since changed.
