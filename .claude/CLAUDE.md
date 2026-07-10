# CLAUDE.md — LeRobot Dataset Inspector

Guidance for Claude Code when working in this project. This `.claude/` folder is a
**self-contained, portable bundle** — drop it into the repo where the tool will be
built and its skills, agents, and hooks activate automatically.

> **Status:** Scaffolding only. The actual `lerobot-inspect` Bash tool is **not
> written yet** — it will be built once a real dataset is provided, since the
> dataset's true schema (v2.0 / v2.1 / older) governs the final code. These
> settings may evolve when the dataset arrives. For now the setup focuses on
> **bash scripting**, **dataset handling & anomaly detection**, and
> **documentation**.

## The project

Build **`lerobot-inspect`**: a read-only Bash tool that takes a single LeRobot
dataset **or a batch** (a folder of many datasets) and, for each one, reports its
statistics, verifies its integrity against the actual files on disk, and flags
anything wrong. Datasets will contain **deliberate problems** (missing files,
missing metadata fields, incorrect parameters); the tool must **detect and report
each precisely**. A tool that crashes, or that reports `PASS` on a broken dataset,
fails the assignment.

Full requirements live in [`skills/lerobot-inspector/SKILL.md`](skills/lerobot-inspector/SKILL.md).
The source brief is `../LeRobot_Dataset_Inspector_Mini_Project-1.pdf`.

### What the tool must do (summary)

- **Report per dataset:** total recorded duration in hours (derived), episode
  count, fps, cameras (names + resolution), robot type + tasks, on-disk size.
- **Verify integrity:** per-episode cross-modal consistency (parquet rows ==
  episode length == mp4 frame count), file accounting (missing + orphan, correct
  chunk math), metadata consistency, temporal integrity (monotonic timestamps,
  empirical vs declared fps), and statistical validation (recomputed vs stored
  mean/std/min/max within a configurable tolerance).
- **Handle scale & versions:** schema differences across `codebase_version`;
  batch mode with a configurable concurrency limit and cross-dataset anomaly
  flagging.
- **Verdict:** PASS/FAIL + issue list per dataset, plus a roll-up summary.

### Engineering rules (non-negotiable)

- `set -euo pipefail`, all variables quoted, **shellcheck-clean at zero warnings**
  (a hook enforces this on every shell edit — see below).
- **Read-only:** never modify, move, or write into a dataset.
- Proper shebang; `-h`/`--help`; one dataset and a batch use the **same** code path.
- Two outputs: human-readable report **and** valid JSON (`--json`). Logs to
  **stderr**, data to **stdout**.
- **Documented exit codes** + a `--strict` flag that turns warnings into failures.
- Precise error handling: malformed JSON, truncated parquet, missing `meta/`,
  zero-byte video, missing dependency → exact message + correct exit code, never a
  raw dump or a false PASS.
- No hardcoded paths, dataset names, or magic numbers; tolerances configurable.
- Bash has no floating-point math — use `awk`/`bc`.

### Deliverables

1. The tool / script.
2. A test that generates broken datasets and shows the tool catches each
   ([`skills/lerobot-inspector/references/broken-dataset-test.md`](skills/lerobot-inspector/references/broken-dataset-test.md)).
3. A README: usage, every flag, dependencies, the JSON schema, the exit-code table.
4. A DESIGN note (≤1 page): assumptions, tradeoffs, improvements.

## How to work in this project

1. **Plan before coding.** Run [`/wizard`](skills/wizard/SKILL.md) — treat the
   tool as a medium/complex task: understand the real dataset schema, list the
   files to write, and design the check pipeline before writing code. **Do not
   write the tool until a dataset is provided** and its schema confirmed.
2. **Structure all shell code** per the [`/bash`](skills/bash/SKILL.md) skill:
   usage → main → business functions → utilities, explicit error handling (no
   `set -e`; the project mandates `set -euo pipefail` — reconcile per the brief),
   dependency checks, guard clause.
3. **Reason about the dataset** with [`/dataset-handling`](skills/dataset-handling/SKILL.md)
   (profile → validate → clean → transform → report) and
   [`/detecting-data-anomalies`](skills/detecting-data-anomalies/SKILL.md) for the
   cross-dataset outlier flagging in batch mode.
4. **Document** with [`/documentation-writer`](skills/documentation-writer/SKILL.md)
   (README, DESIGN, exit-code + JSON-schema tables) and
   [`/mermaid-architecture-diagrams`](skills/mermaid-architecture-diagrams/SKILL.md)
   for architecture diagrams embedded in Markdown.
5. **Never assume.** Verify every field, path, and count against the real files —
   the brief's whole point is catching things that don't match.

## Skills (invoke as `/name`)

| Skill | Use it for |
|-------|------------|
| [`wizard`](skills/wizard/SKILL.md) | Architect-mode planning, TDD, adversarial self-review before/while building |
| [`bash`](skills/bash/SKILL.md) | Bash script structure, argument parsing, error handling, shellcheck-clean code |
| [`lerobot-inspector`](skills/lerobot-inspector/SKILL.md) | LeRobot dataset layout + the 14 required checks (domain knowledge) |
| [`dataset-handling`](skills/dataset-handling/SKILL.md) | Profiling, validating, cleaning, transforming ML datasets |
| [`detecting-data-anomalies`](skills/detecting-data-anomalies/SKILL.md) | Outlier/anomaly detection (batch cross-dataset flagging) |
| [`documentation-writer`](skills/documentation-writer/SKILL.md) | Structured Markdown docs: README, DESIGN, references |
| [`mermaid-architecture-diagrams`](skills/mermaid-architecture-diagrams/SKILL.md) | Architecture diagrams for the docs |

## Agents (in `agents/`)

Focused set for this project — delegate specialized work:

| Agent | Delegate when |
|-------|---------------|
| `cli-developer` | Designing the CLI: flags, help text, UX, exit codes |
| `data-engineer` | Pipeline/format reasoning (parquet, jsonl, batch processing) |
| `data-scientist` | Statistical validation, recomputing/diffing stats |
| `ml-engineer` | ML-dataset conventions and lifecycle context |
| `documentation-engineer` | Larger multi-doc documentation systems |
| `readme-generator` | A maintainer-ready README from real repo state |
| `code-reviewer` | Reviewing the tool for correctness/security before "done" |
| `qa-expert` | Test strategy for the broken-dataset harness (mutation mindset) |

## Hooks

`settings.json` registers two **PostToolUse** hooks:

1. [`hooks/shellcheck-hook.sh`](hooks/shellcheck-hook.sh) runs `shellcheck` after
   any `Write`/`Edit`/`MultiEdit`. Findings are fed back (exit 2) so they get
   fixed — enforcing the brief's "shellcheck-clean at zero warnings" rule. If
   `shellcheck` isn't installed, it warns and skips (`apt install shellcheck`).
2. [`hooks/naming-convention-hook.sh`](hooks/naming-convention-hook.sh) runs on
   `Write` and enforces the verb-first `lib/` naming rule above: a new
   `lib/*.sh` that doesn't lead with an action verb (and isn't `core.sh`) is
   rejected (exit 2) with instructions to rename it. Add a new verb to the hook's
   allowlist if one is genuinely needed.

Both require `$CLAUDE_PROJECT_DIR` (set by Claude Code); if unavailable, adjust
the paths in `settings.json`.

## Conventions

- **File naming — verb-first, one job per file (enforced by a hook).** Every
  `lib/` module must be named for the ACTION it performs so a developer
  understands its job from the filename alone: lead with an action verb
  (`read_metadata.sh`, `probe_video.sh`, `read_parquet.sh`, `build_statistics.sh`,
  `emit_result.sh`, `inspect_dataset.sh`, `discover_datasets.sh`, `run_batch.sh`,
  `flag_cross_dataset_anomalies.sh`, `report_build.sh`, `render_*`), or use the
  `check_<aspect>.sh` / `report_<format>.sh` families. **Never** a bare domain
  noun (`video.sh`, `parquet.sh`, `batch.sh`, `statistics.sh`, `result.sh`) — a
  reader can't tell what it does. `core.sh` (shared primitives) is the only
  exception. If a file does more than one job, split it. The
  `naming-convention-hook.sh` PostToolUse hook rejects a vaguely-named new
  `lib/*.sh` and tells you to rename it.
- Read-only toward any dataset — copy before you perturb (tests included).
- Logs → stderr, data → stdout; everything composes in a pipe.
- Tolerances and limits are configurable flags, never magic numbers.
- Keep this `.claude/` folder portable: paths inside it are relative.
