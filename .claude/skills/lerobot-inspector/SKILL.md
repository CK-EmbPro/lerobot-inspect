---
name: lerobot-inspector
description: >
  Domain knowledge and build guidance for `lerobot-inspect` — a read-only Bash
  tool that inspects LeRobot datasets (single or batch), reports statistics,
  verifies on-disk integrity, and flags corruption precisely. Invoke when
  working on the LeRobot Dataset Inspector project, parsing LeRobot metadata
  (meta/info.json, episodes.jsonl, stats.json, tasks.jsonl), reasoning about
  parquet / mp4 / chunk layout, or implementing the required integrity checks.
  Trigger with "lerobot", "dataset inspector", "lerobot-inspect", or any of the
  14 required checks.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
metadata:
  version: 1.0.0
---

# LeRobot Dataset Inspector

This skill encodes everything needed to build **`lerobot-inspect`**, the tool
specified in the mini-project brief. Pair it with the [`bash`](../bash/SKILL.md)
skill (script structure, error handling, shellcheck-clean output) and the
[`detecting-data-anomalies`](../detecting-data-anomalies/SKILL.md) skill
(cross-dataset outlier flagging in batch mode).

> **Scope note:** Do NOT write the tool until a real dataset is supplied. Use
> this skill to plan, structure, and reason about the checks. Once a dataset is
> in hand, its actual schema (v2.0 / v2.1 / older) governs the final code.

## Objective (from the brief)

A Bash tool that takes **one LeRobot dataset OR a batch (a folder of datasets)**
and, for each one: reports statistics, verifies integrity against the actual
files on disk, and flags anything wrong. It must **detect deliberate corruption**
and must **never crash or report PASS on a broken dataset** — either failure
fails the assignment.

## LeRobot dataset layout (reference model — verify against the real dataset)

A typical `LeRobotDataset` (v2.x) on disk looks like:

```
<dataset_root>/
├── meta/
│   ├── info.json            # fps, robot_type, features, chunks_size,
│   │                        # data_path / video_path templates, codebase_version,
│   │                        # total_episodes / total_frames / total_videos / total_tasks
│   ├── episodes.jsonl       # one line per episode: {episode_index, tasks, length}
│   ├── tasks.jsonl          # one line per task: {task_index, task}
│   ├── stats.json           # global mean/std/min/max per feature   (v2.0)
│   └── episodes_stats.jsonl # per-episode stats                      (v2.1)
├── data/
│   └── chunk-000/
│       └── episode_000000.parquet   # one parquet per episode (row = frame)
└── videos/
    └── chunk-000/
        └── observation.images.<cam>/
            └── episode_000000.mp4   # one mp4 per camera per episode
```

Templates in `info.json` (e.g. `data_path`, `video_path`) drive exact file
locations. `chunks_size` caps episodes per chunk — do the chunk math:
`chunk_index = episode_index // chunks_size`.

**Never trust filenames.** Read frame counts with `ffprobe`, row counts from the
parquet, and reconcile them against the declared metadata.

## The 14 things the tool must answer / check

### Statistics (per dataset)
1. **Total recorded duration in hours** — derive it (not stored): sum of episode
   `length` (frames) ÷ `fps` ÷ 3600. Bash has no float math → use `awk` or `bc`.
2. **Number of episodes.**
3. **FPS.**
4. **Number of cameras, their names, and resolution** (from features / video streams).
5. **Robot type and list of tasks.**
6. **On-disk size.**

### Integrity checks
7. **Per-episode cross-modal consistency:** parquet row count == episode `length`
   in `episodes.jsonl` == each camera `.mp4` frame count (via `ffprobe`). Report
   every mismatch localized to the exact episode and file.
8. **File accounting:** expand `data_path` / `video_path` templates with
   `chunks_size` from `info.json`; compute exactly which files should exist;
   report **missing** (referenced, absent) and **orphan** (present, unreferenced).
   Get the chunk math right.
9. **Metadata consistency:** `total_episodes`, `total_frames`, `total_videos`,
   `total_tasks` must match what is on disk and in the `.jsonl` files. Detect
   missing/empty fields and zero/invalid values.
10. **Temporal integrity:** read the `timestamp` column; confirm it increases
    monotonically; compute empirical fps and compare to declared fps; report
    dropped frames / time gaps.
11. **Statistical validation:** recompute mean/std/min/max for `action` and
    `observation.state` from the parquet and diff against stored stats in
    `stats.json` / `episodes_stats.jsonl` within a **configurable tolerance**.
12. **Version awareness:** detect `codebase_version` and handle schema
    differences (v2.0 vs v2.1 vs older) — e.g. `stats.json` vs `episodes_stats.jsonl`.
13. **Batch mode:** process hundreds of datasets in parallel with a configurable
    concurrency limit; flag **cross-dataset anomalies** (e.g. one dataset's fps
    or episode length disagreeing with the rest — see `detecting-data-anomalies`).
14. **Verdict:** a clear PASS/FAIL + issue list per dataset, plus a roll-up
    summary (total datasets, episodes, hours, how many passed).

## Engineering demands (non-negotiable)

- Runs as `./lerobot-inspect` after `chmod +x`; proper shebang; `-h`/`--help`.
- Accepts paths as arguments; one dataset and a batch use the **same** code path.
- `set -euo pipefail`, all variables quoted, **shellcheck-clean at zero warnings**.
- **Read-only:** never modifies, moves, or writes into a dataset.
- Two outputs: a human-readable report and a valid JSON report (`--json`).
- **Documented exit codes** (ok / warnings / integrity failure / usage error) and
  a `--strict` flag that turns warnings into failures.
- Precise error handling: malformed JSON, truncated parquet, missing `meta/`,
  zero-byte video, missing dependency → exact message + correct exit code, never
  a raw dump or a false PASS.
- No hardcoded paths, dataset names, or magic numbers; tolerances configurable.
- Logs to **stderr**, data to **stdout**, so it composes in a pipe.
- Bash has no floating-point math — handle it correctly (`awk`/`bc`).

## Suggested exit-code table (make it explicit in the README)

| Code | Meaning                                  |
|------|------------------------------------------|
| 0    | OK — all checks passed                   |
| 1    | Warnings (or any failure under `--strict`) |
| 2    | Integrity failure (a real corruption)    |
| 3    | Usage / argument error                   |
| 4    | Missing dependency / environment error   |

## Dependencies to declare and check

`jq` (JSON), `ffprobe` (video frame counts / resolution), a parquet reader
(`duckdb` CLI or `python3 -c` with pyarrow/pandas), `awk`/`bc` (float math),
`du` (on-disk size). Fail with exit code 4 and an exact message if any is absent.

## Deliverables (plan toward these)

1. The tool / script.
2. A test that **generates broken datasets** (drop a frame, truncate a parquet,
   corrupt `info.json`, delete a chunk, perturb a stat) and shows the tool
   catches each. See [`references/broken-dataset-test.md`](references/broken-dataset-test.md).
3. A README: usage, every flag, dependencies, the JSON schema, the exit-code table.
4. A short DESIGN note (≤1 page): assumptions, tradeoffs, what you'd improve.
   Use the [`documentation-writer`](../documentation-writer/SKILL.md) skill.

## Build approach

1. **Plan first with [`wizard`](../wizard/SKILL.md)** — treat this as a
   medium/complex task: understand the schema, list files to write, design the
   check pipeline before coding.
2. Structure the script per the [`bash`](../bash/SKILL.md) skill (usage/main/
   functions/guard clause, explicit error handling).
3. Implement checks 1–14 as small single-responsibility functions; each emits a
   structured result feeding both the human and `--json` reports.
4. Build the broken-dataset generator alongside, TDD-style: every check gets a
   fixture that must trip it.
5. Keep it shellcheck-clean throughout (the PostToolUse hook enforces this).

See [`references/checks.md`](references/checks.md) for per-check implementation
notes and [`references/json-schema.md`](references/json-schema.md) for the report
contract.
