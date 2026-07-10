# Per-check implementation notes

Reference for the 14 checks in `../SKILL.md`. Each check should be one function
returning a structured result: `{check, status: ok|warn|fail, detail, location}`.
Aggregate results drive both the human report and the `--json` report.

## Float math in Bash

Bash integers only. Use `awk` for portable float math and comparisons:

```bash
hours=$(awk -v f="$total_frames" -v fps="$fps" 'BEGIN{printf "%.4f", f/fps/3600}')
# tolerance compare: returns 0 (true) if |a-b| <= tol
within_tol() { awk -v a="$1" -v b="$2" -v t="$3" 'BEGIN{d=a-b; if(d<0)d=-d; exit !(d<=t)}'; }
```

## Reading metadata (jq)

```bash
fps=$(jq -er '.fps' "$meta/info.json")          # -e: fail if null/absent
robot=$(jq -er '.robot_type // empty' "$meta/info.json")
chunks_size=$(jq -er '.chunks_size' "$meta/info.json")
ver=$(jq -er '.codebase_version // "unknown"' "$meta/info.json")
```
Guard every read: a `null`, empty, or missing field is check #9 territory
(missing/empty/invalid) — surface it, do not let `jq` output an empty string
that silently passes.

## Frame counts (never trust filenames)

```bash
# mp4 frame count
frames=$(ffprobe -v error -select_streams v:0 -count_frames \
  -show_entries stream=nb_read_frames -of csv=p=0 "$mp4")
# resolution
res=$(ffprobe -v error -select_streams v:0 \
  -show_entries stream=width,height -of csv=s=x:p=0 "$mp4")
```

## Parquet row count / columns

Prefer `duckdb` if present, else `python3` + pyarrow:

```bash
rows=$(duckdb -noheader -list -c "SELECT count(*) FROM read_parquet('$pq')")
# stats for a column:
duckdb -c "SELECT avg(action), stddev_samp(action), min(action), max(action)
           FROM read_parquet('$pq')"
```
A truncated/corrupt parquet must produce exit code 2 + exact message, not a crash.

## Check-by-check

1. **Duration (h):** `sum(episode.length)/fps/3600`. Cross-check `total_frames`.
2. **Episodes:** `wc -l meta/episodes.jsonl` vs `total_episodes` vs data files.
3. **FPS:** from `info.json`; validate against empirical (check 10).
4. **Cameras:** feature keys `observation.images.*` → names; resolution via ffprobe.
5. **Robot type / tasks:** `info.json.robot_type`; tasks from `tasks.jsonl`.
6. **On-disk size:** `du -sb "$root"` (bytes; human-format for the report).
7. **Cross-modal:** for each episode, assert `parquet_rows == episodes.length ==
   each mp4 frame count`. Report the exact episode + file on mismatch.
8. **File accounting:** expand `data_path`/`video_path` templates for every
   episode/camera using `chunks_size`; diff the expected set against `find` output
   → missing (expected, absent) and orphan (present, unexpected).
9. **Metadata consistency:** `total_*` fields vs on-disk reality and jsonl counts;
   flag zero/negative/missing/empty.
10. **Temporal:** read `timestamp` column; assert strictly increasing; empirical
    fps = `(n-1)/(t_last - t_first)`; compare to declared fps within tolerance;
    report gaps > 1/fps as dropped frames.
11. **Statistical:** recompute mean/std/min/max for `action` and
    `observation.state`; diff vs `stats.json` (v2.0) or `episodes_stats.jsonl`
    (v2.1) within `--tolerance`.
12. **Version:** branch on `codebase_version`; v2.0 uses `stats.json`, v2.1 uses
    `episodes_stats.jsonl`; older schemas may differ — detect and adapt.
13. **Batch:** iterate datasets with a bounded worker pool (e.g. `xargs -P` or a
    job-count loop); collect per-dataset JSON; run cross-dataset outlier detection
    on fps / episode length / duration.
14. **Verdict:** worst per-check status → dataset PASS/FAIL; roll up totals.

## Batch concurrency (bounded)

```bash
# process datasets N at a time, N from --jobs (default: nproc)
printf '%s\0' "${datasets[@]}" | xargs -0 -P "$jobs" -I{} \
  bash -c 'inspect_one "$@"' _ {}
```
Guard shared output; write each dataset's JSON to a temp file, merge at the end.
