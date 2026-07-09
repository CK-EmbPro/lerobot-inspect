# lerobot-inspect

A read-only Bash tool that inspects **LeRobot datasets** — a single dataset or a
whole batch — reports their statistics, verifies their integrity against the
actual files on disk, and flags anything wrong. It is built to **detect
deliberate corruption**: missing files, malformed metadata, truncated parquet,
dropped video frames, perturbed statistics. It never modifies a dataset and
never reports `PASS` on a broken one.

---

## Quick start

```bash
# one dataset
./lerobot-inspect ./datasets/dataset-1

# a batch (any folder containing datasets at any depth)
./lerobot-inspect ./datasets

# machine-readable report
./lerobot-inspect --json ./datasets > report.json

# treat warnings as failures, 8 datasets at a time
./lerobot-inspect --strict --jobs 8 ./datasets
```

## Dependencies

| Tool | Purpose | Install |
|------|---------|---------|
| `jq` | parse JSON / JSONL metadata | `apt install jq` |
| `ffprobe` | video frame counts + resolution | `apt install ffmpeg` |
| `duckdb` | parquet row counts + column stats | [duckdb.org](https://duckdb.org) (single static binary) |
| `awk` | floating-point math (bash is integer-only) | coreutils / gawk |
| `du`, `find` | on-disk size, file enumeration | coreutils / findutils |
| `ffmpeg` | *(tests only)* re-encode a frame-dropped video | `apt install ffmpeg` |

Every dependency is checked at startup; a missing one exits `4` with an exact
message naming the tool and why it is needed.

## Usage

```
lerobot-inspect [options] <dataset|batch-folder> [more paths...]
```

A path containing `meta/info.json` is a **single dataset**; a folder containing
such datasets (found at any depth) is a **batch**. Both take the same code path.

### Options

| Flag | Description | Default |
|------|-------------|---------|
| `--json` | Emit the machine-readable JSON report on stdout | human report |
| `--strict` | Promote warnings to failures (verdict **and** exit code) | off |
| `--tolerance <float>` | Absolute tolerance for statistical validation | `0.01` |
| `--jobs <n>` | Max datasets inspected in parallel | CPU count |
| `--frame-mode <fast\|exact>` | `fast` reads container headers; `exact` decodes every packet | `fast` |
| `-v`, `--verbose` | Verbose diagnostics on stderr | off |
| `-h`, `--help` | Show help | — |
| `--version` | Show version | — |

Defaults live in [`etc/lerobot-inspect.conf`](etc/lerobot-inspect.conf) and can be
overridden by an environment variable of the same name (`LEROBOT_INSPECT_*`) or a
flag. **No magic numbers are baked into the code.**

Logs go to **stderr**; the report (human or JSON) goes to **stdout**, so the tool
composes in a pipe: `lerobot-inspect --json ./datasets | jq '.roll_up'`.

## What it checks

**Statistics reported per dataset** — total recorded duration in hours (derived
as Σ episode length ÷ fps ÷ 3600), episode count, fps, cameras (names +
resolution), robot type + task list, on-disk size.

**Integrity checks:**

| Check | What it verifies |
|-------|------------------|
| `metadata_consistency` | `total_episodes/frames/tasks/videos/chunks` and `splits` agree with `episodes.jsonl`, `tasks.jsonl`, the camera list, and the chunk directories; required fields present and valid |
| `file_accounting` | Expands the `data_path`/`video_path` templates with chunk math (`episode_index / chunks_size`); reports **missing** (referenced, absent) and **orphan** (present, unreferenced) files |
| `cross_modal_consistency` | Per episode: parquet row count == `episodes.jsonl` length == each camera `.mp4` frame count (via `ffprobe`, never the filename) |
| `temporal_integrity` | Timestamps increase monotonically (**fail** if not); empirical vs declared fps within tolerance and large inter-frame gaps (**warn** — dropped frames) |
| `statistical_validation` | Recomputes min/max/mean/std for `observation.state` and `action` from the parquet and diffs against stored stats within `--tolerance` |

**Version awareness:** v2.0 (`stats.json`, global) and v2.1 (`episodes_stats.jsonl`,
per-episode) are both handled. Camera-info nesting (`video_info` vs `info`) and
non-integer fps are handled.

**Batch mode:** datasets are inspected concurrently (`--jobs`), then
**cross-dataset anomalies** are flagged (e.g. one dataset's fps deviating from
the batch median).

## Exit codes

| Code | Meaning |
|------|---------|
| `0` | OK — all datasets passed |
| `1` | Warnings (or any warning under `--strict`) |
| `2` | Integrity failure — corruption detected |
| `3` | Usage / argument error |
| `4` | Missing dependency / environment error |

The process exit code reflects the **worst** outcome across all datasets.

## JSON report schema

`--json` emits a single valid JSON document on stdout:

```json
{
  "tool": "lerobot-inspect",
  "version": "1.0.0",
  "generated_at": "2026-07-09T12:00:00Z",
  "roll_up": {
    "total_datasets": 5,
    "passed": 2,
    "failed": 3,
    "total_episodes": 556,
    "total_hours": 2.8965,
    "cross_dataset_anomalies": ["./datasets/dataset-5: fps=29.68 deviates from batch median 40"]
  },
  "datasets": [
    {
      "path": "./datasets/dataset-1",
      "codebase_version": "v2.1",
      "verdict": "FAIL",
      "worst_status": "fail",
      "stats": {
        "codebase_version": "v2.1",
        "episodes": 10,
        "fps": 50,
        "duration_hours": 0.2528,
        "robot_type": "i2rt_yam_pro",
        "tasks": ["Folding towels"],
        "cameras": [{"name": "observation.images.env1", "resolution": "1280x720"}],
        "total_frames_from_episodes": 45499,
        "on_disk_bytes": 1717986918
      },
      "checks": [
        {
          "check": "statistical_validation",
          "status": "fail",
          "detail": "1 deviation(s) > 0.01: action episode_000003 dim0 max: stored=999.0 recomputed=0.3418751",
          "location": ""
        }
      ],
      "issues": ["statistical_validation: 1 deviation(s) > 0.01: ..."]
    }
  ]
}
```

Field contract:
- `checks[].status` is one of `ok` / `warn` / `fail`.
- `verdict` is `PASS` unless a check is `fail`, or a check is `warn` under `--strict`.
- A dataset whose metadata cannot be parsed at all still gets a record with an
  `error` field and `verdict: "FAIL"` — the document is never truncated.

## Testing

The broken-dataset harness proves each corruption class is caught. It copies a
clean dataset (read-only toward the source), injects one defect per case, and
asserts the right check fails:

```bash
./tests/run-tests.sh            # uses datasets/dataset-4 as the clean source
./tests/run-tests.sh <clean-dataset>
```

Covered defects: corrupt `info.json`, truncated parquet, deleted parquet,
zero-byte video, perturbed stat, metadata lie, and a dropped video frame
(if `ffmpeg` is installed).

## Project layout

```
lerobot-inspect              # entrypoint: arg parsing, orchestration, exit codes
etc/lerobot-inspect.conf     # configurable defaults (tolerances, jobs, thresholds)
lib/
  core.sh                    # exit codes, status algebra, logging, float helpers
  deps.sh                    # dependency verification
  meta.sh                    # version-aware metadata readers
  video.sh   parquet.sh      # ffprobe / duckdb wrappers
  result.sh                  # the single structured-result primitive
  stats_report.sh            # statistics (checks 1-6)
  check_*.sh                 # one file per integrity check (7-11)
  inspect.sh                 # per-dataset orchestration + verdict
  batch.sh                   # discovery, concurrency, cross-dataset anomalies
  report_json.sh report_human.sh  # two renderers from one JSON structure
tests/run-tests.sh           # broken-dataset test harness
```

Adding a new check is one file plus one line — see [`DESIGN.md`](DESIGN.md).

## Design notes

See [`DESIGN.md`](DESIGN.md) for architecture, assumptions, tradeoffs, and
planned improvements.
