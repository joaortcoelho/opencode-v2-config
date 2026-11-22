# Artifact-driven OpenCode workflow

The global toolkit is `artifact-workflow/bin/artifact-workflow`. It stores
durable task state in one JSON file:

```text
.agent/plans/<YYYYMMDD>T<HHMMSS>-<slug>.json
```

The adjacent Markdown file is generated. Do not edit it as a second source.
Validation reports and clean-session handoffs are stored below `.agent/` and
are not task state.

## Create a plan

```sh
~/.config/opencode/artifact-workflow/bin/artifact-workflow init \
  --slug add-cache \
  --title "Add cache" \
  --objective "Reduce repeated reads" \
  --step '1|Inspect access patterns' \
  --step '2|Implement cache' \
  --depends-on '2|1'
```

The default plan has these guardrails:

- one writer for the shared plan and worktree;
- three failed validation runs per step;
- six consecutive read-only turns;
- validation commands need approval or an allowlist;
- no unrequested commit or push;
- a clean session uses `/new`, then `/task <task-id>`.

Work is bounded by the context reset threshold, the failed-validation retry
cap, and the consecutive read-only-turn cap.

Mint acceptance criteria at creation time when the work is medium or high risk:

```sh
~/.config/opencode/artifact-workflow/bin/artifact-workflow init \
  --slug rotate-signing-key \
  --title "Rotate signing key" \
  --objective "Rotate the JWT signing key with zero downtime" \
  --criterion "Old tokens verify until they expire" \
  --criterion "New tokens sign with the new key" \
  --step '1|Stage the new key' \
  --step '2|Cut over signing' \
  --step-meta '1|risk=high' \
  --step-meta '1|invariants=Old tokens keep verifying' \
  --step-meta '2|satisfies=AC-1,AC-2' \
  --depends-on '2|1'
```

Step metadata keys are `risk`, `satisfies`, `invariants`, `non_goals`,
`edge_cases`, and `regression_risks`. Repeat a key to add more than one entry.

Use `migrate` once for a plan created before schema version 1:

```sh
~/.config/opencode/artifact-workflow/bin/artifact-workflow migrate \
  .agent/plans/<task>.json
```

## Plan contract

The contract is versioned at:

```text
artifact-workflow/schema/v2/plan.schema.json
artifact-workflow/schema/v2/status-transition.schema.json
```

The stage-by-stage field mapping, enums, and risk tiers live in
`docs/stage-artifact-contract.md`. That file is the source of truth. This
section is a summary only.

Important fields:

- `task`: timestamp-plus-slug ID, title, workspace, branch, and base revision.
- `objective`, `criteria`, `constraints`, and `decisions`: bounded task context.
- `criteria`: acceptance criteria as `AC-1`, `AC-2`, ... Minted once, referenced
  by ID, never renumbered. A retired criterion stays with `superseded` status.
- `execution.steps`: ordered steps with dependencies, `risk`, `satisfies`, and
  status history.
- `invariants`, `non_goals`, `edge_cases`, `regression_risks`: the frozen spec
  for a step. Required before a medium or high-risk change.
- `validation_records`: command, passed/failed/blocked result, bounded summary,
  `unverified` areas, and an optional output path. Full logs stay outside JSON.
- `retry`: attempts, failed runs, cap, and last failure.
- `session_handoff`: next action, last failure, `/new` task ID, and latest
  generated handoff path.

`execution.phase` and `execution.current_step` are derived from step status.
The validator rejects drift, duplicate IDs, unknown or later dependencies,
illegal history transitions, missing validation data, retry-cap breaches,
non-contiguous criterion IDs, `satisfies` references to unknown criteria, and a
`high`-risk step with no invariant.

### Schema versions

Schema version 2 adds `criteria`, `risk`, `satisfies`, the four spec fields,
and `unverified`. Version 1 plans are rejected with a message that names the
`migrate` command. Run it once per old plan:

```sh
~/.config/opencode/artifact-workflow/bin/artifact-workflow migrate \
  .agent/plans/<task>.json
```

`migrate` is idempotent. It backfills new fields with explicit empty values.

## Read and update state

```sh
TOOL=~/.config/opencode/artifact-workflow/bin/artifact-workflow
PLAN=.agent/plans/<task>.json

"$TOOL" validate "$PLAN"
"$TOOL" state "$PLAN"
"$TOOL" state "$PLAN" --json
"$TOOL" render "$PLAN"
```

Use the toolkit for updates. It takes an exclusive lock, writes a temporary
file in the plan directory, runs `jq -e` checks and semantic validation, then
uses an atomic replace. A failed write leaves the old JSON intact.

Start and finish a step only after validation:

```sh
"$TOOL" mark "$PLAN" 1 in_progress
"$TOOL" mark "$PLAN" 1 completed \
  --command 'npm test -- --runInBand' \
  --result passed \
  --summary 'Unit tests pass.' \
  --unverified 'Concurrent writes not exercised.' \
  --output .agent/validation/<task>/unit-tests.log
```

`--unverified` records what remains assumed rather than demonstrated. Omit the
flag for an explicit none. Each entry is bounded to 280 characters.

Record a failed validation, retry the step, or let the cap block it:

```sh
"$TOOL" mark "$PLAN" 1 failed \
  --command 'npm test' \
  --result failed \
  --summary 'Three assertions fail.'
```

Add a step with its spec and risk tier:

```sh
"$TOOL" add-step "$PLAN" --id 3 --title "Add retry budget" \
  --risk med \
  --satisfies AC-1 \
  --edge-case "Clock skew between nodes" \
  --regression-risk "Retry storm under outage" \
  --depends-on 2
```

Add bounded reasoning with `note`. Direct edits are allowed only for recovery
or schema migration, then run `validate`.

For read-only jq inspection:

```sh
jq -e '.execution.steps[] | select(.status == "in_progress")' "$PLAN"
jq -r '.session_handoff.next_action' "$PLAN"
```

## Clean session

`/new` and `/task` are different kinds of thing. Do not confuse them.

| Command | Kind | Job |
| --- | --- | --- |
| `/new` | TUI built-in | Clear context. Start a fresh session. |
| `/task <task-id>` | Custom command | Load the task artifact into the session you are in. |
| `/handoff <task-id>` | Custom command | Regenerate the bounded handoff for a task. |
| `/artifact-status <task-id>` | Custom command | Show phase, current step, retries, and next action. |

`/task` does **not** resume a session. OpenCode session resume is a different
feature (`opencode --continue`, `opencode --session <id>`, `/sessions`). The
`/task` command only reads the JSON plan and the generated handoff, and prints
them for the current session.

### The commands are agent-neutral

None of the three commands sets `agent` in its frontmatter. They run in
whatever agent the session already uses. This is deliberate: two disciplined
The primary agent is `Atlas`, and a pinned agent would drag the session back to
`Atlas`.

Verified against the running server by creating a session per agent, invoking
each command, and reading the session agent back:

```text
Atlas    via /artifact-status  before=Atlas    after=Atlas    PRESERVED
Atlas    via /task             before=Atlas    after=Atlas    PRESERVED
Atlas    via /handoff          before=Atlas    after=Atlas    PRESERVED
```

Before the `agent` field was removed, the same probe showed
`Atlas via /artifact-status  before=Atlas  after=Atlas  PRESERVED`.

**Trade-off.** Because the commands do not switch agents, invoking one in a
`build` session stays in `build`. `build` has no artifact discipline. Start the
session in `Atlas` before you use these commands.

Generate the handoff before a reset:

```sh
"$TOOL" handoff "$PLAN" --diff-path src/cache.ts
```

Then, at a safe boundary:

```text
/new
/task <task-id>
```

The new session reads the JSON plan and the handoff. It does not read the old
conversation. Do not switch sessions during a tool call. Native compaction is
an emergency fallback, not the workflow source of truth.

## Leaf agents

The primary `Atlas` agent can implement work without a child session. Optional
`Traveller` and `Sentinel` agents are read-only investigation or review roles.
They must not edit the shared worktree. A mutation leaf needs an isolated
OpenCode worktree or an explicit single-writer handoff from the primary agent.

## Locks and recovery

The writer lock is `<plan>.lock`. Normal process exit releases the advisory
lock. If a lock file remains after a crash, confirm that no writer is active,
then remove it through the toolkit:

```sh
"$TOOL" unlock "$PLAN" --force
```

Do not remove an active lock. Validation reports are safe to inspect under
`.agent/validation/`; they are not copied into plan JSON.

## Migration and approval rules

The workflow does not commit or push. OpenCode asks for approval for commit,
push, reset, clean, restore, and checkout commands. Validation commands must be
approved unless they are on a local allowlist. Preserve unrelated providers,
MCP servers, skills, and Herdr integration settings when changing config.

## Tests

Run the shell fixture suite from this global config directory:

```sh
artifact-workflow/tests/test.sh
```

It covers valid state, invalid transitions, retry exhaustion, concurrent notes,
interrupted writes, handoff, task, and `jq` parsing.
