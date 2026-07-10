# USAGE — Using the skills, agents, commands & hooks

A practical guide to everything in this `.claude/` bundle: what each piece is,
how to invoke it, and how they work together to build `lerobot-inspect`.

> **TL;DR of the mental model**
> - **Skills** = knowledge/procedures Claude follows. You trigger them by typing
>   `/name`, or they auto-activate when your request matches their description.
> - **Agents** = separate specialist workers Claude *delegates* a sub-task to;
>   they run in their own context and report back.
> - **Commands** = in this project, the slash form of the skills (e.g. `/wizard`).
>   There is no separate `commands/` folder — a skill *is* its command.
> - **Hooks** = automation the harness runs for you (here: shellcheck on every
>   shell edit). You don't invoke them; they fire on their own.

---

## 1. Skills — how to use them

Skills live in `skills/<name>/SKILL.md`. Two ways they engage:

1. **Explicit (recommended for control):** type `/` + the skill name in Claude
   Code, e.g. `/wizard`, `/bash`, `/lerobot-inspector`.
2. **Automatic:** just describe your task. Claude reads each skill's
   `description` and loads the matching one (e.g. asking to "write a shell
   script" pulls in `bash`; "find outliers across datasets" pulls in
   `detecting-data-anomalies`).

### The skills in this project

| Command | What it does | Invoke it when… |
|---------|--------------|-----------------|
| `/wizard` | Architect-mode: plan → TDD → adversarial self-review → quality gate | Starting any non-trivial build; you want a disciplined plan before code |
| `/bash` | Bash structure, arg parsing, error handling, shellcheck-clean output; cheat-sheet in `references/linux-patterns.md` | Writing or editing any `.sh` file |
| `/lerobot-inspector` | LeRobot dataset layout + the 14 required checks; references for checks, JSON schema, broken-dataset tests | Working on `lerobot-inspect` itself |
| `/dataset-handling` | Profile → validate → clean → transform → report pipeline for ML datasets | Loading/validating/reconciling any dataset |
| `/detecting-data-anomalies` | Statistical + ML outlier detection | Cross-dataset anomaly flagging in batch mode |
| `/documentation-writer` | Structured Markdown docs: README, DESIGN, reference tables | Writing the README / DESIGN note / any `.md` |
| `/mermaid-architecture-diagrams` | Architecture diagrams as `mermaid` fences | Adding diagrams to the docs |

### Example prompts

```
/wizard  Plan the lerobot-inspect tool. Don't write code yet —
         I'll give you the dataset first.

/bash    Scaffold the lerobot-inspect entrypoint: usage(), main(),
         arg parsing for --json/--strict/--tolerance/--jobs, dep checks.

/lerobot-inspector  Implement check #7 (cross-modal consistency) as a
                    function that compares parquet rows, episode length,
                    and mp4 frame count.

/documentation-writer  Draft the README with the flag table and the
                       exit-code table from the skill.
```

> **Note:** skills describe *how* to do the work — Claude still does it in the
> main conversation. A skill doesn't run code by itself.

---

## 2. Agents — how to use them

Agents live in `agents/<name>.md`. Unlike skills, an agent is a **separate
worker** with its own context window and its own tool set. Claude launches one
via its Task/Agent tool, the agent does the sub-task, and returns a result. Use
them to parallelize or to get a focused expert pass without cluttering the main
thread.

Invoke by asking for delegation explicitly:

```
Use the code-reviewer agent to review lerobot-inspect for correctness
and read-only safety.

Have the qa-expert agent design the broken-dataset test matrix.

Ask the data-scientist agent how to recompute std to match the stored
stats (sample vs population).
```

Claude may also delegate automatically when a task fits an agent's description.

### The agents in this project

| Agent | Delegate when you need… |
|-------|-------------------------|
| `cli-developer` | CLI/UX design: flags, `--help` text, exit-code ergonomics |
| `data-engineer` | Pipeline/format reasoning: parquet, jsonl, batch throughput |
| `data-scientist` | Statistical validation — recomputing/diffing mean/std/min/max |
| `ml-engineer` | ML-dataset conventions and lifecycle context |
| `documentation-engineer` | A larger multi-document docs system |
| `readme-generator` | A maintainer-ready README built from real repo state |
| `code-reviewer` | A correctness/security review before calling the tool "done" |
| `qa-expert` | Test strategy with a mutation-testing mindset |

### Skills vs agents — which do I reach for?

- **Skill** = guidance applied *inline* by Claude in your current conversation.
  Cheap, immediate, keeps full context. Default choice.
- **Agent** = a *delegated* deep pass in a fresh context. Use for heavy,
  self-contained sub-tasks (a full review, a test-plan design) or to run several
  specialists in parallel.

They compose: run `/wizard` to plan, `/bash` + `/lerobot-inspector` to build,
then hand the diff to the `code-reviewer` agent and the tests to `qa-expert`.

---

## 3. Commands

Per this project's setup, **commands = skills**. Every skill is invocable as a
slash command (`/wizard`, `/bash`, `/lerobot-inspector`, `/dataset-handling`,
`/detecting-data-anomalies`, `/documentation-writer`,
`/mermaid-architecture-diagrams`). There is intentionally **no separate
`commands/` folder** — this keeps one source of truth per capability.

To see them in Claude Code, type `/` and the skill names appear in the menu.

---

## 4. Hooks — how they work

Hooks are automation the Claude Code harness runs at defined moments. They are
configured in `settings.json` and you never invoke them manually.

### What's configured here

```json
"PostToolUse": [{ "matcher": "Edit|Write|MultiEdit",
                  "hooks": [{ "type": "command",
                              "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/shellcheck-hook.sh" }]}]
```

**Behavior:** after Claude writes or edits any file, `hooks/shellcheck-hook.sh`
checks whether it was a shell script (`.sh`/`.bash` or a bash/sh shebang). If so,
it runs `shellcheck`. If there are findings, they're fed back to Claude to fix —
enforcing the brief's **"shellcheck-clean at zero warnings"** rule. If
`shellcheck` isn't installed, it warns and skips.

### To make the hook work

1. Install shellcheck: `sudo apt install shellcheck` (Debian/Ubuntu) or
   `brew install shellcheck` (macOS).
2. Ensure Claude Code sets `$CLAUDE_PROJECT_DIR` (it does when the project root
   is this folder). If your layout differs, edit the path in `settings.json`.
3. Trust the settings when Claude Code prompts on first load.

### Adding more hooks later

Common additions once the tool exists (edit `settings.json`):
- `bash -n` syntax check alongside shellcheck.
- A `Stop` hook that runs the broken-dataset test suite when a work session ends.
- A `PreToolUse` guard that blocks writes into a dataset directory (reinforces
  the read-only rule). Use the `update-config` skill or ask Claude to wire it.

---

## 5. Putting it together — a typical session

```
1. /wizard
   → "Plan lerobot-inspect. Here is the dataset at ./data/pick_place.
      Confirm the codebase_version and list the files you'll write
      before coding."

2. /bash + /lerobot-inspector
   → Build the entrypoint and the 14 checks as small functions.
      (The shellcheck hook keeps every save clean automatically.)

3. /dataset-handling + /detecting-data-anomalies
   → Reason about profiling/validation and the batch cross-dataset
      outlier flagging.

4. qa-expert agent
   → Design the broken-dataset fixtures (drop frame, truncate parquet,
      corrupt info.json, delete chunk, perturb stat).

5. code-reviewer agent
   → Review the diff for correctness and read-only safety.

6. /documentation-writer (+ /mermaid-architecture-diagrams)
   → Write the README (flags, deps, JSON schema, exit codes) and the
      1-page DESIGN note.
```

## 6. Where to read more

- Project overview & rules: [`CLAUDE.md`](CLAUDE.md)
- What's in the bundle & where it came from: [`README.md`](README.md),
  [`PROVENANCE.md`](PROVENANCE.md)
- The tool's full spec & the 14 checks:
  [`skills/lerobot-inspector/SKILL.md`](skills/lerobot-inspector/SKILL.md)
