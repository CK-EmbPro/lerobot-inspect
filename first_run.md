# First Run — Walkthrough & Output Explained

A guided tour of running `lerobot-inspect` for the first time and reading every
line it prints. It uses the five datasets under `datasets_repo/datasets/`
(`dataset-1` … `dataset-5`) — four carry deliberate defects, `dataset-4` is the
clean control.

---

## 1. The commands, line by line

```bash
cd lerobot_inspect
bash bootstrap.sh
export PATH="$HOME/.local/bin:$PATH"
./bootstrap.sh --check
./lerobot-inspect ./datasets_repo/datasets
```

| Line | What it does | Why |
|------|--------------|-----|
| `cd lerobot_inspect` | Enter the project root | Later commands use relative paths (`./lerobot-inspect`, `./datasets_repo/...`) |
| `bash bootstrap.sh` | Install every dependency + set `+x` on the scripts | Run via `bash` in case the executable bit was lost on download; installs `jq`, `ffmpeg`, `duckdb`, `shellcheck`, `unzip` |
| `export PATH="$HOME/.local/bin:$PATH"` | Put `~/.local/bin` on `PATH` for this shell | `duckdb` was installed there; **without this the tool exits `4`** (missing dependency) |
| `./bootstrap.sh --check` | Report readiness, install nothing | Optional confirmation; exits `0` when all present |
| `./lerobot-inspect ./datasets_repo/datasets` | Inspect the batch of 5 datasets | This is where anomalies are reported |

> Point the tool at **`datasets_repo/datasets`** (the clean datasets), *not*
> `datasets_repo` — the latter also holds the raw multi-part downloads, which are
> intentionally incomplete and would report as broken.

---

## 2. How to read the report

Each dataset gets a block:

```
=== <path> ===  verdict: PASS|FAIL
  version: … | episodes: … | fps: … | duration: …h | robot: … | size: …   ← statistics
  cameras: …
  tasks: …
  [ ok ] <check_name>   <detail>     ← one line per integrity check
  [warn] <check_name>   <detail>
  [FAIL] <check_name>   <detail>
```

Status markers:

- **`[ ok ]`** — the check passed.
- **`[warn]`** — a data-quality issue that does not, by itself, mean corruption
  (e.g. dropped-frame gaps). The dataset still `PASS`es unless you pass `--strict`.
- **`[FAIL]`** — a real integrity failure. Any `FAIL` makes the dataset `FAIL`.

A dataset's `verdict` is `PASS` unless a check `FAIL`s (or a `warn` under
`--strict`). The process exit code is the worst outcome across all datasets:
`0` ok · `1` warnings · `2` integrity failure · `3` usage error · `4` missing dependency.

---

## 3. The actual output, dataset by dataset

### dataset-1 — verdict: FAIL

```
  version: v2.1 | episodes: 10 | fps: 50 | duration: 0.2528h | robot: i2rt_yam_pro | size: 1.6 GiB
  [FAIL] metadata_consistency     total_frames=44000 but sum of episode lengths=45499
  [FAIL] file_accounting          1 missing, 1 orphan; missing: videos/chunk-000/observation.images.env1/episode_000007.mp4; orphan: data/chunk-000/episode_000050.parquet
  [FAIL] cross_modal_consistency  1 mismatch(es): episode_000007 observation.images.env1: video missing or zero-byte
  [ ok ] temporal_integrity       all 10 episodes: timestamps monotonic, empirical fps within tolerance of declared
  [FAIL] statistical_validation   1 deviation(s) > 0.01: action episode_000003 dim0 max: stored=999.0 recomputed=0.3418751
```

- **stats line** — descriptive facts derived from the files: schema `v2.1`, 10
  episodes at 50 fps, ~0.25 recorded hours, robot `i2rt_yam_pro`, 1.6 GiB on disk.
- **metadata_consistency FAIL** — `info.json` declares `total_frames=44000`, but
  summing the per-episode `length` values in `episodes.jsonl` gives `45499`. The
  declared total is wrong.
- **file_accounting FAIL** — one **missing** file (episode 7's `env1` video is
  referenced but absent) and one **orphan** (`episode_000050.parquet` exists on
  disk but there is no episode 50 in `episodes.jsonl` — only 0–9).
- **cross_modal_consistency FAIL** — the same episode-7 `env1` video is missing /
  zero-byte, so its frame count can't match the episode length. (Cross-modal
  independently catches what file accounting flagged.)
- **temporal_integrity ok** — every episode's timestamps rise monotonically and
  the empirical frame rate matches the declared 50 fps.
- **statistical_validation FAIL** — a **tampered statistic**: `episodes_stats.jsonl`
  stores `999.0` as the max of `action` dimension 0 for episode 3, but recomputing
  from the parquet gives `0.34`. The sentinel `999.0` is the injected defect.

### dataset-2 — verdict: FAIL

```
  [FAIL] could not inspect: meta/episodes.jsonl contains malformed JSON
```

- There are no per-check lines because parsing failed **before** the checks could
  run: `episodes.jsonl` contains a syntactically broken line (a truncated object
  with a missing `}`). The tool refuses to proceed on unparseable metadata and
  fails the dataset outright — it never silently reports a partial PASS.

### dataset-3 — verdict: FAIL

```
  version: v2.1 | episodes: 40 | fps: 30 | duration: 0.8684h | robot: i2rt_yam_pro | size: 1.7 GiB
  [FAIL] metadata_consistency     total_frames=93752 but sum of episode lengths=93787; total_tasks=12 but tasks.jsonl lines=16
  [FAIL] file_accounting          2 missing, 1 orphan; missing: data/chunk-000/episode_000005.parquet, data/chunk-000/episode_000039.parquet; orphan: data/chunk-001/episode_000005.parquet
  [FAIL] cross_modal_consistency  8 mismatch(es): episode_000000 observation.images.wrist_right: mp4 frames=3281 != length=3282, episode_000005: parquet unreadable or missing, episode_000010: parquet rows=2565 != length=2600, …
  [FAIL] temporal_integrity       1 issue(s): episode_000020: parquet unreadable (corrupt or missing timestamp)
  [ ok ] statistical_validation   recomputed stats for observation.state action match stored values within 0.01
```

- **metadata_consistency FAIL** — two lies: `total_frames` is off by 35
  (`93752` vs actual `93787`), and `total_tasks=12` while `tasks.jsonl` actually
  lists 16 tasks.
- **file_accounting FAIL** — episodes 5 and 39 are **missing** from `chunk-000`
  where the chunk math says they belong; episode 5's parquet instead sits in
  `chunk-001` (the wrong directory), so it's reported as an **orphan** there.
- **cross_modal_consistency FAIL** — several per-episode mismatches: episode 0's
  `wrist_right` video is one frame short (`3281` vs `3282`); episode 5's parquet
  can't be read; episode 10 is truncated to `2565` rows/frames against a declared
  length of `2600` across the parquet *and* both wrist videos (a whole episode cut
  short consistently). "(+3 more)" means the list was truncated for readability.
- **temporal_integrity FAIL** — episode 20's parquet is **corrupt/truncated** (no
  valid parquet footer), so its timestamp column can't be read. Note the tool
  still validated the other episodes rather than aborting on the one bad file.
- **statistical_validation ok** — the readable episodes' recomputed stats match
  what's stored, so no perturbation here.

### dataset-4 — verdict: PASS (the clean control)

```
  version: v2.1 | episodes: 5 | fps: 50 | duration: 0.1536h | robot: agilex_piper | size: 1.1 GiB
  [ ok ] metadata_consistency     all declared metadata reconciles with on-disk sources
  [ ok ] file_accounting          all 20 referenced files present, no orphans
  [ ok ] cross_modal_consistency  all 5 episodes: parquet rows == length == mp4 frames
  [ ok ] temporal_integrity       all 5 episodes: timestamps monotonic, empirical fps within tolerance of declared
  [ ok ] statistical_validation   recomputed stats for observation.state action match stored values within 0.01
```

- Every check passes. This dataset is intact, and its role is to prove the tool
  does **not** raise false alarms on clean data — a validator that flagged
  everything would be as useless as one that flagged nothing.

### dataset-5 — verdict: PASS (with warnings)

```
  version: v2.1 | episodes: 501 | fps: 29.68 | duration: 1.6217h | robot: UnitZero_UMI | size: 1.8 GiB
  [ ok ] metadata_consistency     all declared metadata reconciles with on-disk sources
  [ ok ] file_accounting          all 1002 referenced files present, no orphans
  [ ok ] cross_modal_consistency  all 501 episodes: parquet rows == length == mp4 frames
  [warn] temporal_integrity       58 issue(s): episode_000021: empirical fps=23.466 != declared 29.68, episode_000021: max gap 3.7126846s > one frame period (dropped frames?), …
  [ ok ] statistical_validation   recomputed stats for observation.state action match stored values within 0.01
```

- The largest dataset: 501 episodes, one `webcam` camera, non-integer fps
  (`29.68`). Metadata, file accounting, cross-modal and statistics all pass.
- **temporal_integrity warn** — 58 timing issues: some episodes have an empirical
  frame rate well below the declared 29.68 (e.g. `23.466`) and large inter-frame
  gaps (`3.7s`, `1.7s`) that look like **dropped frames**. These are real
  characteristics of handheld UMI capture, so they are **warnings**, not hard
  failures — surfaced for your attention, and promotable to `FAIL` with `--strict`.

---

## 4. The roll-up

```
========== SUMMARY ==========
  datasets: 5   passed: 2   failed: 3
  total episodes: 556   total recorded hours: 2.8965
  cross-dataset anomalies:
    - ./datasets_repo/datasets/dataset-5: fps=29.68 deviates from batch median 40
```

- **passed 2 / failed 3** — `dataset-4` and `dataset-5` pass (dataset-5 with
  warnings); `dataset-1/2/3` fail on real corruption.
- **total episodes / hours** — summed across all inspected datasets.
- **cross-dataset anomalies** — a *batch-level heuristic*: dataset-5's fps (29.68)
  differs from the batch median (40) by more than 25%. This is **informational**
  — different robots legitimately run at different rates (the UMI rig here is
  slower than the others), so it's a "worth a look," not a defect.

The process exits **`2`** (an integrity failure occurred). In CI, `exit != 0`
means "something needs attention"; `2` specifically means real corruption.

---

## 5. Next steps

```bash
# machine-readable — just verdict + issues per dataset
./lerobot-inspect --json ./datasets_repo/datasets | jq '.datasets[] | {path, verdict, issues}'

# zoom into one dataset
./lerobot-inspect ./datasets_repo/datasets/dataset-3

# treat warnings as failures (dataset-5 then FAILs, exit 2)
./lerobot-inspect --strict ./datasets_repo/datasets

# prove detection on a controlled defect set (uses the clean dataset-4)
./tests/run-tests.sh
```

For the full flag list, JSON schema, and exit-code table see
[`README.md`](README.md); for architecture and design rationale see
[`DESIGN.md`](DESIGN.md).
