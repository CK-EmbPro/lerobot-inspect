# shellcheck shell=bash
#
# stats_report.sh — the six "questions to answer" (checks 1-6). These are
# descriptive statistics, not pass/fail checks, so build_stats() emits a single
# JSON object that becomes the dataset's "stats" field. Values are derived from
# the authoritative sources: duration and episode count from episodes.jsonl,
# fps/robot/cameras from info.json, size from du. Any disagreement with the
# declared total_* fields is the job of check_metadata, not this reporter.

# build_stats DATASET_ROOT -> echoes the stats JSON object.
build_stats() {
    local root="$1"
    local idx total_len=0

    # Check 1: total duration derived as sum(length)/fps/3600 (not stored).
    # EP_LEN is associative, so the subscript must be $idx (dereferenced) — a
    # bare EP_LEN[idx] in arithmetic uses the literal key "idx".
    local len
    for idx in "${EP_INDICES[@]}"; do
        len="${EP_LEN[$idx]:-}"
        [[ "$len" =~ ^[0-9]+$ ]] && total_len=$(( total_len + len ))
    done

    local fps="${META[fps]}" hours="null"
    if [[ "$fps" =~ ^[0-9]+([.][0-9]+)?$ ]] && awk -v f="$fps" 'BEGIN{exit !(f>0)}'; then
        hours=$(awk -v l="$total_len" -v f="$fps" 'BEGIN{printf "%.4f", l/f/3600}')
    fi

    # Check 6: on-disk size in bytes (human-formatted later, in the report).
    local bytes
    bytes=$(du -sb "$root" 2>/dev/null | cut -f1)
    [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0

    # Check 4: cameras — names + declared resolution, as a JSON array.
    local cameras_json="[]" k
    if (( ${#CAM_KEYS[@]} > 0 )); then
        cameras_json=$(
            for k in "${CAM_KEYS[@]}"; do
                printf '%s\t%s\n' "$k" "${CAM_SHAPE[$k]}"
            done | jq -R -s 'split("\n") | map(select(length > 0) | split("\t"))
                             | map({name: .[0], resolution: .[1]})'
        )
    fi

    # Check 5: task list as a JSON array of strings.
    local tasks_json="[]"
    if (( ${#TASK_LIST[@]} > 0 )); then
        tasks_json=$(printf '%s\n' "${TASK_LIST[@]}" | jq -R . | jq -s .)
    fi

    # fps as a JSON number when valid, else null (check_metadata flags the null).
    local fps_json="null"
    [[ "$fps" =~ ^[0-9]+([.][0-9]+)?$ ]] && fps_json="$fps"

    jq -n \
        --argjson episodes "${#EP_INDICES[@]}" \
        --argjson total_frames "$total_len" \
        --argjson fps "$fps_json" \
        --argjson duration_hours "$hours" \
        --argjson on_disk_bytes "$bytes" \
        --arg robot_type "${META[robot_type]}" \
        --arg version "${META[version]}" \
        --argjson cameras "$cameras_json" \
        --argjson tasks "$tasks_json" \
        '{
            codebase_version: (if $version == "" then "unknown" else $version end),
            episodes: $episodes,
            fps: $fps,
            duration_hours: $duration_hours,
            robot_type: (if $robot_type == "" then null else $robot_type end),
            tasks: $tasks,
            cameras: $cameras,
            total_frames_from_episodes: $total_frames,
            on_disk_bytes: $on_disk_bytes
        }'
}
