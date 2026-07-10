# shellcheck shell=bash
#
# report_build.sh — assemble the canonical report document (check 14 roll-up)
# from the array of per-dataset objects produced by inspect_one. This builder is
# the single source of truth: the --json output is this document verbatim, and
# every renderer (human / markdown / explanation) is derived from it, so they can
# never disagree.

# build_report DATASETS_ARRAY ANOMALIES_ARRAY TOOL VERSION GENERATED_AT
build_report() {
    local datasets="$1" anomalies="$2" tool="$3" version="$4" generated_at="$5"
    jq -n \
        --argjson datasets "$datasets" \
        --argjson anomalies "$anomalies" \
        --arg tool "$tool" \
        --arg version "$version" \
        --arg generated_at "$generated_at" \
        '{
            tool: $tool,
            version: $version,
            generated_at: $generated_at,
            roll_up: {
                total_datasets: ($datasets | length),
                passed: ([ $datasets[] | select(.verdict == "PASS") ] | length),
                failed: ([ $datasets[] | select(.verdict == "FAIL") ] | length),
                total_episodes: ([ $datasets[] | (.stats.episodes // 0) ] | add // 0),
                total_hours: (([ $datasets[] | (.stats.duration_hours // 0) ] | add // 0) * 10000 | round / 10000),
                cross_dataset_anomalies: $anomalies
            },
            datasets: $datasets
        }'
}
