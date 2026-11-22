# OpenCode v2 configuration

Global OpenCode v2 settings, agents, commands, skills, and the artifact
workflow used for software-engineering work.

## Agents

| Agent | Model | Role |
| --- | --- | --- |
| `Atlas` | `opencode-go/deepseek-v4.1-flash#max` | Default primary agent. Plans and implements work in the shared worktree. |
| `Traveller` | `opencode-go/glm-5.3-flash#high` | Optional read-only codebase investigator. |
| `Sentinel` | `opencode-go/gpt-6-luna#high` | Optional read-only implementation and regression reviewer. |

`Traveller` and `Sentinel` deny file edits and child-agent use. Their shell use
requires approval. `Atlas` owns mutations and task state.

## Configuration

- [`opencode.jsonc`](./opencode.jsonc) sets `Atlas` as the default agent,
  allows `opencode-go` and denies other providers, registers the `fff` MCP
  server, and adds `~/.agents/skills` as a skill source.
- [`cli.json`](./cli.json) uses the system theme, wraps diffs by word, shows
  thinking, uses the automatic session sidebar, hides the scrollbar, and
  enables animations. No CLI plugins are configured.
- [`agents/`](./agents/) defines the custom agents.
- [`commands/`](./commands/) defines `/task`, `/handoff`, and
  `/artifact-status`.

The provider policy currently uses the deprecated `experimental.policies`
location. Check the
[OpenCode config docs](https://opencode.ai/docs/config/) before you change it.

Authenticate OpenCode Go with `opencode auth login opencode-go` or `/connect`.
OpenCode stores provider credentials in its SQLite database. They do not go in
`service.json`. That file is for shared-server settings. `opencode --standalone`
can bypass the shared server for a run; it does not remove an existing
`service.json`.

### Model cost and selection

The current model choices balance role fit and usage limits:

- `DeepSeek V4.1 Flash` is the primary model. OpenCode Go lists the largest
  request allowance of these three models.
- `GLM-5.3-Flash` is a low-cost model for read-only investigation.
- `GPT-6 Luna` has low listed token prices, but a lower Go request allowance
  than the other two. It remains a reasonable choice for independent review,
  where review quality matters more than maximum request volume.

There is no universal best model without tests on this workload. Go limits and
model prices can change. Check the live
[OpenCode Go model limits](https://opencode.ai/console/go) and
[model pricing](https://models.dev/providers/opencode-go/) before changing
these selections.

## Install

Clone this repository into OpenCode's global config directory:

```bash
git clone https://github.com/joaortcoelho/opencode-config.git ~/.config/opencode
```

Restart OpenCode after you change its config or agents.

## Skills

The config reads global skills from `~/.agents/skills`. Install Matt Pocock's
skills with the
[official skills repository](https://github.com/mattpocock/skills):

```bash
npx skills@latest add mattpocock/skills -a opencode -g
```

In the installer, select `setup-matt-pocock-skills` and any other skills you
want. Run the setup skill once in each project. It asks where the project's
issues, triage labels, and domain documents live. See the repository's
[installation guide](https://github.com/mattpocock/skills#installation-30-second-setup)
for other agents. Update the installed skills with `npx skills@latest update -g`,
then re-run the add command to install new skills from the repository.

## `fff` MCP server

This config starts `fff-mcp` from
`/home/coelho/.local/bin/fff-mcp`. Install it from the
[official `fff` GitHub repository](https://github.com/dmtrKovalenko/fff):

```bash
curl -fsSL https://raw.githubusercontent.com/dmtrKovalenko/fff/main/install-mcp.sh | bash
```

The installer uses `~/.local/bin/fff-mcp` by default. If it installs elsewhere,
change the command in `opencode.jsonc` to the binary's path. Review the
[installer script](https://github.com/dmtrKovalenko/fff/blob/main/install-mcp.sh)
before you run it if you want to inspect what it does.

## Artifact workflow

The artifact workflow stores task state in one JSON plan under
`.agent/plans/`. Its Markdown view is generated; do not edit that view by hand.
The workflow supports validation records, step dependencies, retry limits, and
handoffs across fresh sessions.

Read the
[artifact workflow guide](./docs/artifact-driven-workflow.md) for plan commands,
the task lifecycle, and recovery steps. Run its test suite from this directory:

```bash
artifact-workflow/tests/test.sh
```

## License

See [`LICENSE`](./LICENSE).
