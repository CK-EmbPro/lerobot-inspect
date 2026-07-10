# shellcheck shell=bash
#
# report_markdown.sh — render the report as a clean Markdown document (headings,
# tables, status badges) from the same JSON structure the human and JSON
# renderers use. This is what gets saved to results/run_<timestamp>.md.

render_markdown() {
    local doc="$1"
    jq -r '
        def badge: if . == "ok" then "✅ ok" elif . == "warn" then "⚠️ warn" else "❌ fail" end;
        def cell: (. // "") | gsub("\\|"; "\\|") | gsub("\n"; " ");
        def humansize:
            (. // 0) as $b
            | if   $b >= 1073741824 then "\(($b / 1073741824 * 10 | round) / 10) GiB"
              elif $b >= 1048576    then "\(($b / 1048576 * 10 | round) / 10) MiB"
              elif $b >= 1024       then "\(($b / 1024 * 10 | round) / 10) KiB"
              else "\($b) B" end;

        "# lerobot-inspect report",
        "",
        "`\(.tool) v\(.version)` · generated `\(.generated_at)`",
        "",
        "## Summary",
        "",
        "- **Datasets:** \(.roll_up.total_datasets) (**\(.roll_up.passed) passed**, **\(.roll_up.failed) failed**)",
        "- **Total episodes:** \(.roll_up.total_episodes) · **Total recorded hours:** \(.roll_up.total_hours)",
        ( if (.roll_up.cross_dataset_anomalies | length) > 0
          then "- **Cross-dataset anomalies:**", (.roll_up.cross_dataset_anomalies[] | "  - \(.)")
          else "- **Cross-dataset anomalies:** none" end ),
        "",
        ( .datasets[] |
          "## \(.path) — \(.verdict)",
          "",
          ( if .error then
              "> **Could not inspect:** \(.error)", ""
            else
              "- version `\(.stats.codebase_version)` · episodes \(.stats.episodes) · fps \(.stats.fps // "?") · duration \(.stats.duration_hours // "?") h · robot `\(.stats.robot_type // "?")` · size \(.stats.on_disk_bytes | humansize)",
              "- cameras: \([.stats.cameras[]? | "`\(.name)` (\(.resolution))"] | join(", "))",
              "- tasks: \((.stats.tasks // []) | join(", "))",
              "",
              "| status | check | detail |",
              "| --- | --- | --- |",
              ( .checks[] | "| \(.status | badge) | `\(.check)` | \(.detail | cell) |" ),
              ""
            end )
        )
    ' <<< "$doc"
}
