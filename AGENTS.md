- In all interaction and commit messages, be extremely concise and sacrifice grammar for the sake of concision.

## LANGUAGE

**ALWAYS** use ASD-STE100 Simplified Technical English in all your messages. This is a **MANDATORY** rule.

Use the fff MCP tools for all file search operations instead of default tools.

## Code Quality Standards

- Make minimal, surgical changes
- **Follow Unix Philosophy** (see below)
- **Never compromise type safety**: No `any`, no non-null assertion operator (`!`), no type assertions (`as Type`)
- **Make illegal states unrepresentable**: Model domain with ADTs/discriminated unions; parse inputs at boundaries into typed structures; if state can't exist, code can't mishandle it
- **Abstractions**: Consciously constrained, pragmatically parameterised, doggedly documented

### Unix Philosophy

1. **Modularity:** Simple parts, clean interfaces
2. **Clarity:** Clarity > cleverness
3. **Composition:** Design programs to connect to other programs
4. **Separation:** Policy from mechanism; interfaces from engines
5. **Simplicity:** Add complexity only where you must
6. **Parsimony:** Big program only when nothing else will do
7. **Transparency:** Design for visibility; make inspection/debugging easy
8. **Robustness:** Child of transparency + simplicity
9. **Representation:** Fold knowledge into data; keep logic stupid
10. **Least Surprise:** In interfaces, do the expected thing
11. **Silence:** Nothing surprising to say → say nothing
12. **Repair:** Fail loud, fail fast
13. **Economy:** Programmer time > machine time
14. **Generation:** Write programs to write programs
15. **Optimization:** Get it working before optimizing
16. **Diversity:** Distrust "one true way"
17. **Extensibility:** Design for the future

## Testing

- Write tests that verify semantically correct behavior
- **Failing tests are acceptable** when they expose genuine bugs and test correct behavior

## SCM, Git, Pull Requests, Commits

- **Never** add Claude to attribution or as a contributor PRs, commits, messages, or PR descriptions

## Node.js package management

- For a new Node.js project, use pnpm.
- Use `pnpm create`, `pnpm dlx`, `pnpm install`, `pnpm add`, and `pnpm exec`.
- Generate `pnpm-lock.yaml`.
- Do not create `package-lock.json`, `yarn.lock`, or `bun.lock`.
- For an existing project, follow its established package manager and lockfile.
- Do not migrate an existing project to pnpm unless explicitly requested.

## Plans

- At the end of each plan, give me a list of unresolved questions to answer, if any. Make the questions extremely concise. Sacrifice grammar for the sake of concision.

## Agent skills

### Issue tracker

Issues and specs live as markdown files under `.scratch/<feature>/`. See `docs/agents/issue-tracker.md`.

### Triage labels

Default label strings: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
