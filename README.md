# lerobot-inspect

A read-only Bash tool that inspects **LeRobot datasets** — a single dataset or a
whole batch — reports their statistics, verifies their integrity against the
actual files on disk, and flags anything wrong. It is built to **detect
deliberate corruption**: missing files, malformed metadata, truncated parquet,
dropped video frames, perturbed statistics. It never modifies a dataset and
never reports `PASS` on a broken one.

---

## Getting started

From a fresh clone, this is the full order of commands to go from nothing to
seeing the anomalies in the datasets:

```bash
# 1. Enter the project
cd lerobot_inspect

# 2. Install every dependency + make the scripts executable.
#    Run via `bash` the first time in case the +x bit was lost on download.
bash bootstrap.sh

# 3. Put duckdb (installed into ~/.local/bin) on PATH for this shell.
#    Without this, the tool can't find duckdb and exits 4.
export PATH="$HOME/.local/bin:$PATH"

# 4. Confirm everything is ready (optional — installs nothing).
./bootstrap.sh --check

# 5. Inspect ALL datasets — this is where the anomalies are reported.
./lerobot-inspect ./datasets
```

Step 5 prints a per-dataset report and a roll-up, and exits `2` when any dataset
fails its integrity checks.

### Getting the data

The datasets to inspect live under **`./datasets/`**, each as its own folder that
contains `meta/info.json` — e.g. `datasets/dataset-1`, `datasets/dataset-2`, …
(a LeRobot dataset is that folder with its `meta/`, `data/`, and `videos/`
together; `./datasets/` just holds one or more of them side by side).

`bootstrap.sh` **checks for this**: in step 2 it verifies at least one dataset
exists under `./datasets/`, and if none are found it does **not** report ready —
it fails with guidance, so you always know to place the data there before
running. Override the location with `LEROBOT_INSPECT_DATASETS_DIR=/path ./bootstrap.sh`.
The `datasets/` folder is gitignored (it's large binary data — distribute it via
the Hugging Face Hub / DVC / cloud storage, not GitHub).

### More ways to run it

```bash
# one dataset in detail
./lerobot-inspect ./datasets/dataset-1

# machine-readable report -> just the verdict + issues per dataset
./lerobot-inspect --json ./datasets | jq '.datasets[] | {path, verdict, issues}'

# treat warnings as failures, 8 datasets at a time
./lerobot-inspect --strict --jobs 8 ./datasets

# prove it catches deliberately injected corruption (fast; uses the clean dataset-4)
./tests/run-tests.sh
```

## Dependencies

Run **`./bootstrap.sh`** to install all of these automatically — it detects your
package manager (apt/dnf/pacman/brew), installs the system tools with `sudo`, and
fetches the duckdb CLI into `~/.local/bin`. `./bootstrap.sh --check` reports
what's missing without installing. Or install manually:

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
| `--results-dir <dir>` | Where to save run reports | `results` |
| `--no-save` | Don't save a report file (terminal output only) | off |
| `--no-explanation` | Save the report but skip the `_explanation.md` companion | off |
| `-v`, `--verbose` | Verbose diagnostics on stderr | off |
| `-h`, `--help` | Show help | — |
| `--version` | Show version | — |

Defaults live in [`conf/lerobot-inspect.conf`](conf/lerobot-inspect.conf) and can be
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
| `1` | Warnings present (without `--strict`) |
| `2` | Integrity failure — corruption detected, **or any warning under `--strict`** |
| `3` | Usage / argument error |
| `4` | Missing dependency / environment error |

The process exit code reflects the **worst** outcome across all datasets and
always agrees with the JSON verdicts: `--strict` promotes warnings to `FAIL`
(exit `2`); without it, warnings are exit `1`.

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

## Saved results

Every run also persists its report to timestamped files under `results/` (in
addition to the terminal output), so you keep a history of inspections:

```
results/
  run_10-07-2026_13-20-39.md              # the report as Markdown
  run_10-07-2026_13-20-39.json            # the same report as JSON (always saved too)
  run_10-07-2026_13-20-39_explanation.md  # an annotated companion (first_run.md style)
```

- Filenames are `run_DD-MM-YYYY_HH-MM-SS` (24-hour). **Both** the Markdown and
  JSON reports are saved on every run — two views of the same data. The `--json`
  flag only changes what is printed to the terminal, not what is saved.
- The `_explanation.md` companion explains the report line by line — what each
  check verifies and what each result means. Its content (the intro and the
  per-check descriptions) lives in [`conf/lerobot-inspect.conf`](conf/lerobot-inspect.conf)
  under `LEROBOT_INSPECT_EXPLAIN_INTRO` and `LEROBOT_INSPECT_CHECK_DOC`, so you
  can tune how runs are explained without touching code.
- Control it with `--no-save`, `--no-explanation`, `--results-dir <dir>`, or the
  `LEROBOT_INSPECT_SAVE_RESULTS` / `LEROBOT_INSPECT_WRITE_EXPLANATION` /
  `LEROBOT_INSPECT_TIMESTAMP_FMT` config keys. `results/` is gitignored.

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
bootstrap.sh                 # one-command dependency installer (--check to dry-run)
lerobot-inspect              # entrypoint: arg parsing, orchestration, exit codes
conf/lerobot-inspect.conf     # configurable defaults (tolerances, jobs, thresholds)
lib/
  core.sh                    # exit codes, status algebra, logging, float helpers
  verify_dependencies.sh     # verify external tools are installed
  read_metadata.sh           # read/parse LeRobot metadata (info/episodes/tasks)
  probe_video.sh             # ffprobe wrapper — read mp4 frame count + resolution
  read_parquet.sh            # duckdb wrapper — read parquet counts, stats, timestamps
  emit_result.sh             # the {check,status,detail,location} record each check emits
  build_statistics.sh        # build descriptive statistics (checks 1-6)
  check_*.sh                 # one file per integrity check (7-11)
  inspect_dataset.sh         # per-dataset orchestration + verdict
  discover_datasets.sh       # find dataset roots under the given paths
  run_batch.sh               # inspect datasets concurrently (bounded)
  flag_cross_dataset_anomalies.sh  # cross-dataset fps outlier flagging
  report_build.sh            # assembles the canonical report document (+ roll-up)
  report_human.sh report_markdown.sh report_explanation.sh  # renderers derived from that document
tests/run-tests.sh           # broken-dataset test harness
results/                     # generated: run_<timestamp>.md|json + explanations (gitignored)
```

Adding a new check is one file plus one line — see [`DESIGN.md`](DESIGN.md).

## Design notes

See [`DESIGN.md`](DESIGN.md) for architecture, assumptions, tradeoffs, and
planned improvements.
