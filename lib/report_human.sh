# shellcheck shell=bash
#
# report_human.sh — render the human-readable report to stdout from the final
# JSON document. Reading from the same structure the --json output uses keeps
# the two reports in lockstep. All status coloring flows through one icon helper.

render_human() {
    local doc="$1" ds

    while IFS= read -r ds; do
        _render_dataset "$ds"
    done < <(jq -c '.datasets[]' <<< "$doc")

    _render_summary "$doc"
}

_status_icon() {
    case "$1" in
        ok)   printf '%s[ ok ]%s'  "$C_GREEN"  "$C_NC" ;;
        warn) printf '%s[warn]%s'  "$C_YELLOW" "$C_NC" ;;
        *)    printf '%s[FAIL]%s'  "$C_RED"    "$C_NC" ;;
    esac
}

_verdict_label() {
    case "$1" in
        PASS) printf '%sPASS%s' "$C_GREEN" "$C_NC" ;;
        *)    printf '%sFAIL%s' "$C_RED"   "$C_NC" ;;
    esac
}

_render_dataset() {
    local ds="$1"
    local path verdict ver eps fps hours robot bytes err

    IFS=$'\t' read -r path verdict ver eps fps hours robot bytes < <(
        jq -r '[.path, .verdict, (.codebase_version // "?"),
                (.stats.episodes // 0), (.stats.fps // "?"),
                (.stats.duration_hours // 0), (.stats.robot_type // "?"),
                (.stats.on_disk_bytes // 0)] | @tsv' <<< "$ds")

    printf '\n%s=== %s ===%s  verdict: %s\n' "$C_BLUE" "$path" "$C_NC" "$(_verdict_label "$verdict")"

    err=$(jq -r '.error // empty' <<< "$ds")
    if [[ -n "$err" ]]; then
        printf '  %s[FAIL]%s could not inspect: %s\n' "$C_RED" "$C_NC" "$err"
        return
    fi

    printf '  version: %s | episodes: %s | fps: %s | duration: %sh | robot: %s | size: %s\n' \
        "$ver" "$eps" "$fps" "$hours" "$robot" "$(human_bytes "$bytes")"

    local camline
    camline=$(jq -r '[.stats.cameras[]? | "\(.name) (\(.resolution))"] | join(", ")' <<< "$ds")
    [[ -n "$camline" ]] && printf '  cameras: %s\n' "$camline"
    local tasks
    tasks=$(jq -r '(.stats.tasks // []) | join(", ")' <<< "$ds")
    [[ -n "$tasks" ]] && printf '  tasks: %s\n' "$tasks"

    local status check detail
    while IFS=$'\t' read -r status check detail; do
        printf '  %s %-24s %s\n' "$(_status_icon "$status")" "$check" "$detail"
    done < <(jq -r '.checks[] | [.status, .check, .detail] | @tsv' <<< "$ds")
}

_render_summary() {
    local doc="$1"
    local total passed failed eps hours

    IFS=$'\t' read -r total passed failed eps hours < <(
        jq -r '[.roll_up.total_datasets, .roll_up.passed, .roll_up.failed,
                .roll_up.total_episodes, .roll_up.total_hours] | @tsv' <<< "$doc")

    printf '\n%s========== SUMMARY ==========%s\n' "$C_BLUE" "$C_NC"
    printf '  datasets: %s   %spassed: %s%s   %sfailed: %s%s\n' \
        "$total" "$C_GREEN" "$passed" "$C_NC" "$C_RED" "$failed" "$C_NC"
    printf '  total episodes: %s   total recorded hours: %s\n' "$eps" "$hours"

    local anomalies
    anomalies=$(jq -r '.roll_up.cross_dataset_anomalies[]?' <<< "$doc")
    if [[ -n "$anomalies" ]]; then
        printf '  %scross-dataset anomalies:%s\n' "$C_YELLOW" "$C_NC"
        printf '    - %s\n' "$anomalies"
    fi
}
