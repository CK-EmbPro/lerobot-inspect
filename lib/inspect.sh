# shellcheck shell=bash
#
# inspect.sh — orchestrates a single dataset (checks 12 & 14). meta_load parses
# the metadata, build_stats answers checks 1-6, then every registered check
# runs and emits one result. The results are aggregated into one dataset JSON
# object with a PASS/FAIL verdict. This same function is the unit of work for
# both single-dataset and batch runs (one code path).
#
# Extensibility: to add a check, write lib/check_<name>.sh with a function that
# calls emit_result once, source it in the entrypoint, and add its function name
# to INSPECT_CHECKS below. Nothing else changes — that is the whole contract.

readonly INSPECT_CHECKS=(
    check_metadata
    check_files
    check_crossmodal
    check_temporal
    check_stats
)

# inspect_one DATASET_ROOT STRICT(true|false) -> one dataset JSON object on stdout.
inspect_one() {
    local root="$1" strict="$2"

    if ! meta_load "$root"; then
        # Metadata could not be parsed at all: a hard integrity failure. Still
        # emit a well-formed record so the batch document never truncates.
        jq -cn --arg path "$root" --arg err "$META_ERROR" '{
            path: $path, verdict: "FAIL", worst_status: "fail",
            error: $err, stats: null, checks: [], issues: [("metadata: " + $err)]
        }'
        return 0
    fi

    local stats_json results checks_json
    stats_json=$(build_stats "$root")
    results=$(run_checks "$root")
    checks_json=$(printf '%s\n' "$results" | jq -s '.')

    jq -n \
        --arg path "$root" \
        --argjson strict "$strict" \
        --argjson stats "$stats_json" \
        --argjson checks "$checks_json" \
        '
        ($checks | map(.status)) as $st
        | (if   ($st | length) == 0        then "fail"
           elif ($st | any(. == "fail")) then "fail"
           elif ($st | any(. == "warn")) then "warn"
           else "ok" end) as $worst
        | {
            path: $path,
            codebase_version: $stats.codebase_version,
            verdict: (if $worst == "fail" then "FAIL"
                      elif ($worst == "warn" and $strict) then "FAIL"
                      else "PASS" end),
            worst_status: $worst,
            stats: $stats,
            checks: $checks,
            issues: [ $checks[] | select(.status != "ok") | "\(.check): \(.detail)" ]
        }'
}

# run_checks DATASET_ROOT -> JSONL of every registered check's single result.
run_checks() {
    local root="$1" fn
    for fn in "${INSPECT_CHECKS[@]}"; do
        "$fn" "$root"
    done
}
