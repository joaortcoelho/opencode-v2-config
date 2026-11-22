---
description: Load a task artifact into this session
---

Work on task `$ARGUMENTS`.

Run the global artifact-workflow `task` command to print the generated handoff,
then read the canonical JSON plan. Do not use old conversation text as state.
Continue only from the current step.

Note: this command does not resume a session. It loads task state into the
session you are already in. Use `/new` first if the context is stale.

Update the JSON plan after each state change. Stop on ambiguity, a blocker,
retry-cap exhaustion, or the read-only-turn cap.
