# shellcheck shell=bash
#
# report_explanation.sh — render the annotated companion,
# results/run_<timestamp>_explanation.md, in the style of first_run.md: an intro
# on how to read the report, then every check of every dataset explained.
#
# The explanatory CONTENT (the intro and the one-line description of what each
# check verifies) lives in conf/lerobot-inspect.conf so it is configurable; this
# module only assembles that content around the actual run data. The array is
# re-declared here (idempotently, preserving the conf values) so the reference
# is visible to static analysis.
declare -gA LEROBOT_INSPECT_CHECK_DOC

render_explanation() {
    local doc="$1"
    printf '# Run Explanation — %s\n\n' "$(jq -r '.generated_at' <<< "$doc")"
    printf '%s\n\n' "${LEROBOT_INSPECT_EXPLAIN_INTRO:-}"

    local ds
    while IFS= read -r ds; do
        _explain_dataset "$ds"
    done < <(jq -c '.datasets[]' <<< "$doc")

    _explain_rollup "$doc"
}

_explain_dataset() {
    local ds="$1" path verdict err
    path=$(jq -r '.path' <<< "$ds")
    verdict=$(jq -r '.verdict' <<< "$ds")
    printf '## %s — %s\n\n' "$path" "$verdict"

    err=$(jq -r '.error // empty' <<< "$ds")
    if [[ -n "$err" ]]; then
        printf '> **Could not inspect:** %s\n>\n' "$err"
        printf '> The metadata could not be parsed, so no per-check results were produced.\n'
        printf '> The tool fails the dataset outright rather than reporting a partial pass.\n\n'
        return
    fi

    jq -r '"- version `\(.stats.codebase_version)` · episodes \(.stats.episodes) · fps \(.stats.fps // "?") · duration \(.stats.duration_hours // "?") h · robot `\(.stats.robot_type // "?")`\n"' <<< "$ds"

    local status check detail doc_text note
    while IFS=$'\t' read -r status check detail; do
        doc_text="${LEROBOT_INSPECT_CHECK_DOC[$check]:-This check verifies dataset integrity.}"
        case "$status" in
            ok)   note="Passed." ;;
            warn) note="Flagged as a **warning** — surfaced for attention, not a hard failure (promotes to a failure under \`--strict\`)." ;;
            *)    note="**Failed** — a real defect the tool detected." ;;
        esac
        # shellcheck disable=SC2016  # backticks are literal markdown, not command substitution
        printf '### %s — `%s`\n\n%s\n\n**Result:** %s\n\n%s\n\n' \
            "$(_explain_status_word "$status")" "$check" "$doc_text" "$detail" "$note"
    done < <(jq -r '.checks[] | [.status, .check, .detail] | @tsv' <<< "$ds")
}

_explain_status_word() {
    case "$1" in
        ok)   echo "PASS" ;;
        warn) echo "WARN" ;;
        *)    echo "FAIL" ;;
    esac
}

_explain_rollup() {
    local doc="$1" total passed failed eps hours a anomalies
    IFS=$'\t' read -r total passed failed eps hours < <(
        jq -r '[.roll_up.total_datasets, .roll_up.passed, .roll_up.failed,
                .roll_up.total_episodes, .roll_up.total_hours] | @tsv' <<< "$doc")

    printf '## Roll-up\n\n'
    printf -- '- **%s** dataset(s): **%s passed**, **%s failed**.\n' "$total" "$passed" "$failed"
    printf -- '- **%s** episodes across the batch, **%s** recorded hours total.\n' "$eps" "$hours"

    anomalies=$(jq -r '.roll_up.cross_dataset_anomalies[]?' <<< "$doc")
    if [[ -n "$anomalies" ]]; then
        printf -- '- **Cross-dataset anomalies** (informational — a batch-level heuristic, not necessarily a defect):\n'
        while IFS= read -r a; do
            printf -- '  - %s\n' "$a"
        done <<< "$anomalies"
    fi
    printf '\n'
}
