# Stage artifact contract

Single source of truth for what each stage must produce. Change a field or an
enum here, once. Do not copy these lists into each agent prompt.

The plan JSON is the only mutable state. This document maps each stage onto the
fields of that JSON. It does not define a second store.

Canonical state:

```text
.agent/plans/<YYYYMMDD>T<HHMMSS>-<slug>.json
```

Schema:

```text
artifact-workflow/schema/v2/plan.schema.json
```

## Conventions

1. **Explicit none.** A section with nothing to report is an empty array, never
   an omitted key. Absence is ambiguous; an empty array is not.
2. **Bounded strings.** Every string is at most 280 characters. The validator
   rejects longer values.
3. **Enum values are literal.** Do not paraphrase them.
4. **One producer per field.** A field is written by one stage only. Other
   stages read it or reference it.

## Enums

| Field | Values |
| --- | --- |
| Step status | `pending` `ready` `in_progress` `failed` `completed` `blocked` `skipped` |
| Validation status | `passed` `failed` `blocked` |
| Risk level | `low` `med` `high` |
| Criterion status | `active` `superseded` |

## Risk tiers

Classify every step before you start it. Record the tier in `risk`.

| Tier | Meaning | Examples |
| --- | --- | --- |
| `low` | Internal, reversible, no shared contract. | comment, log line, local helper, test-only change |
| `med` | User-visible behaviour, shared types, async flows. | response shape, error handling, caching, refactor |
| `high` | Hard to reverse, security-relevant, or shared with others. | auth, secrets, persistence, migrations, destructive ops, billing, public APIs, concurrency, idempotency |

A `high` step must declare at least one `invariant`. The validator enforces
this.

### Escalation

If a step reveals higher risk than declared, stop. Update `risk`, add the
missing `invariants`, `edge_cases`, and `regression_risks`, then continue. Do
not silently widen the blast radius.

## Acceptance criteria and ID minting

This is the registry-of-record rule.

- The primary executor mints criteria with the `init` and `add-step` commands.
  IDs are sequential: `AC-1`, `AC-2`, ...
- A retired criterion stays in the list with `"status": "superseded"`. IDs are
  never reused and never renumbered.
- Because retired criteria remain, IDs are always contiguous from `AC-1`. The
  validator enforces this.
- Steps **reference** criteria through `satisfies`. Steps never mint IDs.
- If a step discovers a missing criterion, report it as prose through the plan
  `notes`. The primary executor decides whether to mint it.

Low-risk work may use prose criteria in `objective` and leave `criteria` empty.
Medium and high-risk work must mint IDs.

## Stage 1 — Investigation

Producer: the primary executor, or `Traveller` for a read-only pass.

| Artifact | Field |
| --- | --- |
| Summary | `notes` with `step_id` |
| Relevant files | `notes` |
| Current behaviour | `notes` |
| Call flow | `notes` |
| Contracts and boundaries | `notes` |
| Dependencies | `notes` |
| Existing tests | `notes` |
| Impact analysis | `regression_risks` on the affected step |
| Unknowns | `notes` |
| Risks | `regression_risks` |

Stop exploring once every row above is supported by evidence or an explicit
unknown. Do not treat the turn allowance as a target.

## Stage 2 — Specification

Producer: the primary executor.

| Artifact | Field |
| --- | --- |
| Problem | `objective`, and `changes` on the step |
| Acceptance criteria | `criteria` |
| Invariants | `invariants` |
| Non-goals | `non_goals` |
| Edge cases | `edge_cases` |
| Regression risks | `regression_risks` |
| Tests to add or update | `validation` |
| Verification plan | `validation` |
| Open questions | `notes` |

## Stage 3 — Implementation

Producer: the primary executor.

| Artifact | Field |
| --- | --- |
| Files changed | `changes` |
| What changed | `changes` |
| Reasoning | `notes` |
| Spec items satisfied | `satisfies` |
| Edge cases considered | `edge_cases` |
| Remaining risks | `regression_risks` |
| Verification run | `validation_records[].command` |
| Anything not verified | `validation_records[].unverified` |

If the spec is ambiguous, incomplete, or contradicts the code, stop and report
the smallest blocking issue. Do not force the implementation to fit the spec.
Do not silently redefine a criterion.

## Stage 4 — Verification

Producer: the primary executor, or `Sentinel` for a read-only pass.

| Artifact | Field |
| --- | --- |
| Verification status | `validation_records[].status` |
| Spec coverage | `validation_records[].summary`, keyed by `satisfies` |
| Checks run | `validation_records[].command` |
| Failures | `validation_records[].summary` |
| Unverified areas | `validation_records[].unverified` |
| Residual risks | `regression_risks` |

Rules:

- Distinguish what was demonstrated from what was assumed.
- If evidence is missing, write `unverified`. Do not imply proof.
- If a check did not run, say so.

## Stage 5 — Review handoff

Producer: the `handoff` command.

The generated handoff carries the criteria, the current-step spec, the
unverified areas, bounded working-tree status including untracked files, and
selected diffs. It carries no prior conversation.

Use `/new`, then `/task <task-id>`. `/new` is a TUI built-in that clears
context. `/task` loads this artifact into the new session. `/task` does not
resume a session.

## Guardrails

Limits come from the plan guardrails, not from a step count.

| Guardrail | Value |
| --- | --- |
| Context reset threshold | 0.5 |
| Failed validation runs per step | 3 |
| Consecutive read-only turns | 6 |
| Terminal task states | `completed`, `blocked` |
