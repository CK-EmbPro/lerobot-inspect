# shellcheck shell=bash
#
# check_metadata.sh — check 9 (metadata consistency) with version awareness
# (check 12). Reconciles the declared total_* fields in info.json against the
# authoritative sources: episodes.jsonl, tasks.jsonl, the camera list, the
# splits range, and the on-disk chunk directories. Missing/empty/zero/negative
# fields are flagged too. Emits one metadata_consistency result whose status is
# the worst of everything found.

check_metadata() {
    local root="$1"
    local info="${root}/meta/info.json"
    local status="ok"
    local -a issues=()

    _md_flag() {  # SEVERITY MESSAGE
        issues+=("$2")
        status=$(status_worst "$status" "$1")
    }

    # --- required fields present and valid ---------------------------------
    [[ -n "${META[version]}" ]] || _md_flag warn "codebase_version missing"

    if [[ ! "${META[fps]}" =~ ^[0-9]+([.][0-9]+)?$ ]] || ! awk -v f="${META[fps]}" 'BEGIN{exit !(f>0)}'; then
        _md_flag fail "fps missing or not a positive number (got '${META[fps]}')"
    fi
    if [[ ! "${META[chunks_size]}" =~ ^[0-9]+$ ]] || (( ${META[chunks_size]:-0} <= 0 )); then
        _md_flag fail "chunks_size missing or not a positive integer (got '${META[chunks_size]}')"
    fi
    [[ -n "${META[robot_type]}" ]] || _md_flag warn "robot_type missing"

    # --- count reconciliation ---------------------------------------------
    local actual_eps="${#EP_INDICES[@]}"
    local actual_tasks="${#TASK_LIST[@]}"
    local ncams="${#CAM_KEYS[@]}"

    _md_expect_int "total_episodes" "${META[total_episodes]}" "$actual_eps" \
        "episodes.jsonl lines" fail

    local sum_frames=0 idx len
    for idx in "${EP_INDICES[@]}"; do
        len="${EP_LEN[$idx]:-}"
        [[ "$len" =~ ^[0-9]+$ ]] && sum_frames=$(( sum_frames + len ))
    done
    _md_expect_int "total_frames" "${META[total_frames]}" "$sum_frames" \
        "sum of episode lengths" fail

    _md_expect_int "total_tasks" "${META[total_tasks]}" "$actual_tasks" \
        "tasks.jsonl lines" fail

    if [[ "${META[total_videos]}" =~ ^[0-9]+$ ]]; then
        local expect_videos=$(( actual_eps * ncams ))
        _md_expect_int "total_videos" "${META[total_videos]}" "$expect_videos" \
            "episodes x cameras" fail
    fi

    # splits: "train": "start:end" — end must equal the episode count.
    local split_range split_end
    split_range=$(jq -r '.splits.train // empty' "$info" 2>/dev/null)
    if [[ "$split_range" =~ ^[0-9]+:[0-9]+$ ]]; then
        split_end="${split_range#*:}"
        (( split_end == actual_eps )) || \
            _md_flag fail "splits.train ends at ${split_end} but there are ${actual_eps} episodes"
    fi

    # total_chunks vs the chunk directories implied by the episodes on disk.
    if [[ "${META[chunks_size]}" =~ ^[0-9]+$ ]] && (( META[chunks_size] > 0 )); then
        local max_idx=0
        for idx in "${EP_INDICES[@]}"; do (( idx > max_idx )) && max_idx="$idx"; done
        local expect_chunks=$(( max_idx / META[chunks_size] + 1 ))
        _md_expect_int "total_chunks" "${META[total_chunks]}" "$expect_chunks" \
            "highest episode_index / chunks_size" fail
    fi

    local detail="all declared metadata reconciles with on-disk sources"
    (( ${#issues[@]} > 0 )) && detail=$(_md_join "; " "${issues[@]}")
    emit_result "metadata_consistency" "$status" "$detail" "meta/info.json"
}

# _md_expect_int FIELD DECLARED ACTUAL SOURCE_DESC SEVERITY
# Flags when a declared integer field is absent or disagrees with the derived
# actual value. Absent required integers are themselves an issue.
_md_expect_int() {
    local field="$1" declared="$2" actual="$3" source="$4" severity="$5"
    if [[ ! "$declared" =~ ^-?[0-9]+$ ]]; then
        _md_flag warn "${field} missing or non-integer (got '${declared}')"
        return
    fi
    (( declared == actual )) || \
        _md_flag "$severity" "${field}=${declared} but ${source}=${actual}"
}

_md_join() {
    local sep="$1"; shift
    local out="" item
    for item in "$@"; do
        [[ -n "$out" ]] && out+="$sep"
        out+="$item"
    done
    printf '%s' "$out"
}
