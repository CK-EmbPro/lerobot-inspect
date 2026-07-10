# `--json` report contract

The `--json` output must be a single valid JSON document on **stdout** (logs go
to stderr). Keep it stable — the README must document this schema and the
exit-code table.

## Proposed shape

```json
{
  "tool": "lerobot-inspect",
  "version": "1.0.0",
  "generated_at": "<ISO-8601>",
  "roll_up": {
    "total_datasets": 3,
    "passed": 2,
    "failed": 1,
    "total_episodes": 240,
    "total_hours": 6.4213
  },
  "datasets": [
    {
      "path": "/data/pick_place",
      "verdict": "FAIL",
      "codebase_version": "v2.1",
      "stats": {
        "episodes": 80,
        "fps": 30,
        "duration_hours": 2.1338,
        "robot_type": "so100",
        "tasks": ["pick the cube", "place in bin"],
        "cameras": [
          {"name": "observation.images.top", "resolution": "640x480"},
          {"name": "observation.images.wrist", "resolution": "320x240"}
        ],
        "on_disk_bytes": 1288490188
      },
      "checks": [
        {
          "check": "cross_modal_consistency",
          "status": "fail",
          "detail": "episode_000004: parquet rows=298, episodes.jsonl length=300, top.mp4 frames=300",
          "location": "data/chunk-000/episode_000004.parquet"
        }
      ],
      "issues": [ "cross_modal_consistency: episode_000004 frame mismatch" ]
    }
  ]
}
```

## Rules

- `status` is one of `ok` / `warn` / `fail`.
- `verdict` is `PASS` only when every check is `ok` (or `warn` without `--strict`).
- Under `--strict`, any `warn` promotes the dataset verdict to `FAIL` and the
  process exit code to 1.
- The exit code reflects the **worst** outcome across all datasets:
  `0` ok · `1` warnings/strict · `2` integrity failure · `3` usage · `4` env.
- Emit valid JSON even on partial failure — a dataset that errors out still gets
  a record with its error, never a truncated document.
