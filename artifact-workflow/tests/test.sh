#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/../.." && pwd)
CLI="$ROOT/artifact-workflow/bin/artifact-workflow"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

expect_failure() {
  if "$@" >/dev/null 2>&1; then
    fail "command unexpectedly passed: $*"
  fi
}

WORKSPACE="$TMP/fixture-workspace"
mkdir -p "$WORKSPACE"
git -C "$WORKSPACE" init -q
printf 'untracked fixture\n' > "$WORKSPACE/fixture.txt"

"$CLI" init \
  --workspace "$WORKSPACE" \
  --slug workflow-fixture \
  --title "Workflow fixture" \
  --objective "Exercise durable plan state" \
  --criterion "Fixture plan validates" \
  --criterion "Retry cap blocks a step" \
  --step '1|Prepare fixture' \
  --step '2|Validate fixture' \
  --step '3|Finish fixture' \
  --step-meta '1|risk=high' \
  --step-meta '1|invariants=Plan stays parseable' \
  --step-meta '2|satisfies=AC-1' \
  --depends-on '2|1' \
  --depends-on '3|2' >/dev/null

PLAN=$(find "$WORKSPACE/.agent/plans" -name '*.json' -type f -print)
"$CLI" validate "$PLAN" >/dev/null
jq -e . "$PLAN" >/dev/null

# Acceptance criteria are minted in order and referenced, never re-minted.
jq -e '.schema_version == 2 and [.criteria[].id] == ["AC-1", "AC-2"]' "$PLAN" >/dev/null
jq -e '.execution.steps[1].satisfies == ["AC-1"]' "$PLAN" >/dev/null
jq -e '.execution.steps[0].risk == "high" and .execution.steps[0].invariants == ["Plan stays parseable"]' "$PLAN" >/dev/null

# Schema and invariant failures are rejected.
expect_failure "$CLI" add-step "$PLAN" --id 9 --title "Bad reference" --satisfies AC-99
if "$CLI" add-step "$PLAN" --id 9 --title "High risk without invariant" --risk high 2>&1 | grep -F 'high risk and must declare at least one invariant' >/dev/null; then
  :
else
  fail 'high-risk gate did not report its reason'
fi
cp "$PLAN" "$TMP/duplicate.json"
jq '.execution.steps[1].id = 1' "$PLAN" > "$TMP/duplicate.json.tmp"
mv "$TMP/duplicate.json.tmp" "$TMP/duplicate.json"
expect_failure "$CLI" validate "$TMP/duplicate.json"
cp "$PLAN" "$TMP/missing-validation.json"
jq '.execution.steps[0].status = "completed" | .execution.steps[0].status_history[-1].status = "completed"' "$PLAN" > "$TMP/missing-validation.json.tmp"
mv "$TMP/missing-validation.json.tmp" "$TMP/missing-validation.json"
expect_failure "$CLI" validate "$TMP/missing-validation.json"
cp "$PLAN" "$TMP/retry-cap.json"
jq '.execution.steps[0].retry.failed_runs = 4' "$PLAN" > "$TMP/retry-cap.json.tmp"
mv "$TMP/retry-cap.json.tmp" "$TMP/retry-cap.json"
expect_failure "$CLI" validate "$TMP/retry-cap.json"
cp "$PLAN" "$TMP/gap-criteria.json"
jq '.criteria[1].id = "AC-3"' "$PLAN" > "$TMP/gap-criteria.json.tmp"
mv "$TMP/gap-criteria.json.tmp" "$TMP/gap-criteria.json"
expect_failure "$CLI" validate "$TMP/gap-criteria.json"
cp "$PLAN" "$TMP/high-no-invariant.json"
jq '.execution.steps[0].invariants = []' "$PLAN" > "$TMP/high-no-invariant.json.tmp"
mv "$TMP/high-no-invariant.json.tmp" "$TMP/high-no-invariant.json"
expect_failure "$CLI" validate "$TMP/high-no-invariant.json"
cp "$PLAN" "$TMP/unknown-criterion.json"
jq '.execution.steps[1].satisfies = ["AC-7"]' "$PLAN" > "$TMP/unknown-criterion.json.tmp"
mv "$TMP/unknown-criterion.json.tmp" "$TMP/unknown-criterion.json"
expect_failure "$CLI" validate "$TMP/unknown-criterion.json"

# A version 1 plan is rejected with a migrate hint, then upgraded in place.
cp "$PLAN" "$TMP/legacy.json"
jq '.schema_version = 1 | del(.criteria) | .execution.steps |= map(del(.risk, .satisfies, .invariants, .non_goals, .edge_cases, .regression_risks))' "$PLAN" > "$TMP/legacy.json.tmp"
mv "$TMP/legacy.json.tmp" "$TMP/legacy.json"
"$CLI" validate "$TMP/legacy.json" 2>&1 | grep -F 'migrate' >/dev/null || fail 'legacy plan error omits the migrate hint'
"$CLI" migrate "$TMP/legacy.json" >/dev/null
"$CLI" validate "$TMP/legacy.json" >/dev/null
jq -e '.schema_version == 2 and (.criteria | type == "array") and (.execution.steps[0].risk == "low")' "$TMP/legacy.json" >/dev/null

# Invalid transitions are rejected before the JSON file changes.
expect_failure "$CLI" mark "$PLAN" 1 completed --command true --result passed --summary invalid
"$CLI" mark "$PLAN" 1 in_progress >/dev/null
"$CLI" mark "$PLAN" 1 completed --command true --result passed --summary passed >/dev/null
"$CLI" mark "$PLAN" 2 in_progress >/dev/null
"$CLI" mark "$PLAN" 2 completed --command true --result passed --summary passed >/dev/null
"$CLI" mark "$PLAN" 3 in_progress >/dev/null
"$CLI" mark "$PLAN" 3 completed --command true --result passed --summary passed --unverified 'Interrupted writes covered only by the test hook.' >/dev/null
"$CLI" validate "$PLAN" >/dev/null
jq -e '.execution.phase == "completed" and .execution.current_step == null' "$PLAN" >/dev/null
jq -e '.execution.steps[2].validation_records[0].unverified == ["Interrupted writes covered only by the test hook."]' "$PLAN" >/dev/null
jq -e '.execution.steps[0].validation_records[0].unverified == []' "$PLAN" >/dev/null

# Retry exhaustion creates a blocked terminal state.
RETRY_WORKSPACE="$TMP/retry-workspace"
mkdir -p "$RETRY_WORKSPACE"
"$CLI" init --workspace "$RETRY_WORKSPACE" --slug retry-fixture --title Retry --step '1|Retry step' >/dev/null
RETRY_PLAN=$(find "$RETRY_WORKSPACE/.agent/plans" -name '*.json' -type f -print)
"$CLI" mark "$RETRY_PLAN" 1 in_progress >/dev/null
"$CLI" mark "$RETRY_PLAN" 1 failed --command false --result failed --summary one >/dev/null
"$CLI" mark "$RETRY_PLAN" 1 in_progress >/dev/null
"$CLI" mark "$RETRY_PLAN" 1 failed --command false --result failed --summary two >/dev/null
"$CLI" mark "$RETRY_PLAN" 1 in_progress >/dev/null
"$CLI" mark "$RETRY_PLAN" 1 failed --command false --result failed --summary three >/dev/null
"$CLI" validate "$RETRY_PLAN" >/dev/null
jq -e '.execution.phase == "blocked" and .execution.steps[0].status == "blocked" and .execution.steps[0].retry.failed_runs == 3' "$RETRY_PLAN" >/dev/null
jq -e '.session_handoff.last_failure.summary == "three"' "$RETRY_PLAN" >/dev/null

# Two writers retain both notes. The second writer waits for the file lock.
ARTIFACT_WORKFLOW_LOCK_HOLD_SECONDS=0.2 "$CLI" note "$RETRY_PLAN" first-note >/dev/null &
FIRST_PID=$!
sleep 0.02
"$CLI" note "$RETRY_PLAN" second-note >/dev/null &
SECOND_PID=$!
wait "$FIRST_PID"
wait "$SECOND_PID"
jq -e '[.notes[].text] | (index("first-note") != null and index("second-note") != null)' "$RETRY_PLAN" >/dev/null

# A failure between validation and replace leaves the plan byte-for-byte intact.
BEFORE=$(shasum -a 256 "$RETRY_PLAN" | awk '{print $1}')
expect_failure env ARTIFACT_WORKFLOW_FAIL_BEFORE_REPLACE=1 "$CLI" note "$RETRY_PLAN" interrupted-note
AFTER=$(shasum -a 256 "$RETRY_PLAN" | awk '{print $1}')
[ "$BEFORE" = "$AFTER" ] || fail 'interrupted update changed the plan'

# Handoff output is bounded and loads from the artifact, not conversation text.
"$CLI" handoff "$PLAN" >/dev/null
TASK_OUT=$($CLI task "$PLAN")
printf '%s\n' "$TASK_OUT" | grep -F 'This is generated handoff context.' >/dev/null
printf '%s\n' "$TASK_OUT" | grep -F 'prior conversation' >/dev/null
printf '%s\n' "$TASK_OUT" | grep -F 'second-note' >/dev/null && fail 'unbounded note leaked into handoff'
printf '%s\n' "$TASK_OUT" | grep -F '?? fixture.txt' >/dev/null
printf '%s\n' "$TASK_OUT" | grep -F '## Acceptance criteria' >/dev/null
printf '%s\n' "$TASK_OUT" | grep -F 'AC-1: Fixture plan validates' >/dev/null
printf '%s\n' "$TASK_OUT" | grep -F '## Unverified areas' >/dev/null
printf '%s\n' "$TASK_OUT" | grep -F 'Return findings first' >/dev/null
printf '%s\n' "$TASK_OUT" | grep -F '/task' >/dev/null || fail 'handoff does not name the /task command'
if git -C "$WORKSPACE" rev-parse --verify HEAD >/dev/null 2>&1; then
  fail 'fixture test created a commit'
fi

# The lock file is a permanent mutex handle. No command removes it.
[ -f "$RETRY_PLAN.lock" ] || fail 'lock file missing after writes'
"$CLI" unlock "$RETRY_PLAN" >/dev/null
[ -f "$RETRY_PLAN.lock" ] || fail 'unlock removed the lock file'

# unlock reports a held lock, exits non-zero, and deletes nothing.
ARTIFACT_WORKFLOW_LOCK_HOLD_SECONDS=0.6 "$CLI" note "$RETRY_PLAN" held-note >/dev/null &
HOLDER_PID=$!
sleep 0.15
expect_failure "$CLI" unlock "$RETRY_PLAN"
[ -f "$RETRY_PLAN.lock" ] || fail 'held unlock removed the lock file'
wait "$HOLDER_PID"

# An in-progress step outranks an earlier pending step in the derived state.
OUT_OF_ORDER_WORKSPACE="$TMP/out-of-order-workspace"
mkdir -p "$OUT_OF_ORDER_WORKSPACE"
"$CLI" init --workspace "$OUT_OF_ORDER_WORKSPACE" --slug out-of-order-fixture --title 'Out of order' \
  --step '1|First pending' --step '2|Second in progress' >/dev/null
OUT_PLAN=$(find "$OUT_OF_ORDER_WORKSPACE/.agent/plans" -name '*.json' -type f -print)
"$CLI" mark "$OUT_PLAN" 2 in_progress >/dev/null
"$CLI" state "$OUT_PLAN" --json | jq -e '.current_step == 2' >/dev/null

# Concurrent init with one task ID leaves exactly one plan and exactly one winner.
RACE_WORKSPACE="$TMP/init-race-workspace"
mkdir -p "$RACE_WORKSPACE"
RACE_ID=20200101T000000-init-race
"$CLI" init --workspace "$RACE_WORKSPACE" --task-id "$RACE_ID" --slug init-race --title 'Init race' --step '1|Race step' >/dev/null 2>&1 &
RACE_A=$!
"$CLI" init --workspace "$RACE_WORKSPACE" --task-id "$RACE_ID" --slug init-race --title 'Init race' --step '1|Race step' >/dev/null 2>&1 &
RACE_B=$!
set +e
wait "$RACE_A"
RACE_STATUS_A=$?
wait "$RACE_B"
RACE_STATUS_B=$?
set -e
[ $((RACE_STATUS_A + RACE_STATUS_B)) -eq 1 ] || fail "concurrent init winners: $RACE_STATUS_A and $RACE_STATUS_B"
RACE_PLAN="$RACE_WORKSPACE/.agent/plans/$RACE_ID.json"
[ -f "$RACE_PLAN" ] || fail 'concurrent init produced no plan'
RACE_COUNT=$(find "$RACE_WORKSPACE/.agent/plans" -name '*.json' -type f | wc -l | tr -d ' ')
[ "$RACE_COUNT" = "1" ] || fail "concurrent init produced $RACE_COUNT plans"
"$CLI" validate "$RACE_PLAN" >/dev/null

# Every generated plan and fixture passes jq parsing.
find "$TMP" -name '*.json' -type f -exec jq -e . '{}' ';' >/dev/null

printf 'PASS: artifact workflow tests\n'
