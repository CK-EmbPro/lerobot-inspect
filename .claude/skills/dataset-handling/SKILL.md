---
name: dataset-handling
description: >
  Standards for analysing, preparing, processing, and handling ML datasets —
  schema profiling, integrity/consistency validation, cleaning and normalization,
  format conversion (CSV/JSON/JSONL/Parquet/video), and computing/verifying
  summary statistics. Invoke when loading, profiling, validating, transforming,
  or reconciling a dataset, especially before training or before an integrity
  audit. For outlier/anomaly work delegate to `detecting-data-anomalies`; for
  robotics/LeRobot specifics use `lerobot-inspector`.
allowed-tools: Read, Write, Edit, Bash, Glob, Grep
metadata:
  version: 1.0.0
---

# Dataset Handling

A disciplined pipeline for working with ML datasets so downstream analysis,
training, and integrity checks rest on trustworthy data. Complements
[`detecting-data-anomalies`](../detecting-data-anomalies/SKILL.md) (outliers) and
[`lerobot-inspector`](../lerobot-inspector/SKILL.md) (robotics datasets).

## When this applies

- Loading a new dataset and needing to know what it contains.
- Preparing data for training, validation, or an audit.
- Converting between CSV / JSON / JSONL / Parquet / media formats.
- Reconciling declared metadata (row counts, totals, stats) against on-disk reality.
- Any "is this data actually correct and complete?" question.

## The pipeline

### 1. Profile before you touch anything
- Establish schema: columns, dtypes, row count, file inventory, encoding.
- Descriptive stats per feature: count, mean/std, min/max, null rate, cardinality.
- Record the baseline so later transforms can be verified against it.
- **Read-only first.** Never mutate source data during profiling.

### 2. Validate integrity & consistency
- **Completeness:** declared counts/totals match on-disk reality and index files.
- **Cross-modal / cross-file:** related artifacts agree (e.g. row count == frame
  count == declared length). Localize every mismatch to the exact record/file.
- **Types & ranges:** values fall within valid domains; no zero/negative where
  invalid; timestamps monotonic where expected.
- **Statistical:** recomputed mean/std/min/max match stored stats within a
  **configurable tolerance** (never hardcode magic numbers).
- Surface a missing/empty/invalid field as a finding — never let it pass silently.

### 3. Clean & prepare
- Handle missing values explicitly: median (numeric) / mode (categorical)
  imputation, or documented row exclusion — state which and why.
- Normalize/scale numeric features (StandardScaler/MinMax/Robust) when magnitudes
  differ; encode categoricals separately.
- Deduplicate; document every dropped/altered record.

### 4. Process & transform
- Convert formats without loss; verify counts and a checksum/stat before & after.
- Prefer streaming/chunked processing for large files; show progress; support
  resume where feasible.
- Keep transforms reproducible: script them, parameterize thresholds, log inputs.

### 5. Report
- Emit a structured summary: schema, counts, stats, findings, actions taken.
- Provide both human-readable and machine-readable (JSON) output where useful, so
  it composes in a pipeline (data to stdout, logs to stderr).

## Tooling cheatsheet

| Task                     | Preferred tool                                  |
|--------------------------|-------------------------------------------------|
| JSON / JSONL             | `jq`                                            |
| Parquet query/stats      | `duckdb` CLI, or `python3` + pyarrow / pandas   |
| Tabular stats / cleaning | pandas, NumPy                                    |
| Video streams            | `ffprobe` (counts/resolution), `ffmpeg`         |
| Float math in Bash       | `awk` / `bc` (Bash has no floats)               |
| Sizes / inventory        | `du`, `find`, `wc`                              |

## Principles

- **Profile → validate → clean → transform → report**, in that order.
- **Read-only until intentional.** Copy before you perturb.
- **Tolerances configurable**, never magic numbers.
- **Localize findings** to the exact record and file.
- **Verify every transform** against the pre-transform baseline.
- Scripts follow the [`bash`](../bash/SKILL.md) standards; audits use the
  [`data-engineer`](../../agents/data-engineer.md) /
  [`data-scientist`](../../agents/data-scientist.md) agents.
