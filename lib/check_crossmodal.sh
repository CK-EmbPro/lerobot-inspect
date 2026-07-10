# shellcheck shell=bash
#
# check_crossmodal.sh — check 7 (per-episode cross-modal consistency). For every
# declared episode, the parquet row count, the episodes.jsonl length, and each
# camera .mp4 frame count must all agree. Frame counts come from ffprobe, never
# the filename. Mismatches are localized to the exact episode and file.
#
# Files are keyed by their full dataset-relative path (from the templates + chunk
# math), NOT by episode number alone — so a parquet sitting in the wrong chunk
# directory is treated as missing (and reported), not silently matched by index.
#
# Row counts are read in one glob query for speed; if that fails (a truncated
# parquet aborts the whole scan), it falls back to per-episode reads so a single
# bad file is pinpointed instead of blinding the check.

check_crossmodal() {
    local root="$1"
    local -A rows=()
    local glob="${root}/data/**/*.parquet"

    if ! _cm_load_rows_glob "$root" "$glob" rows; then
        log_debug "row-count glob failed; per-episode fallback (a parquet is likely corrupt)"
        _cm_load_rows_perfile "$root" rows
    fi

    local status="ok"
    local -a bad=()
    local chunks_size="${META[chunks_size]}"
    local idx len r cam chunk pqrel mp4 frames
    for idx in "${EP_INDICES[@]}"; do
        len="${EP_LEN[$idx]:-}"
        chunk=$(( idx / chunks_size ))
        pqrel=$(_expand_path "${META[data_path]}" "$chunk" "$idx")
        r="${rows[$pqrel]:-}"

        if [[ -z "$r" ]]; then
            bad+=("episode_$(printf '%06d' "$idx"): parquet unreadable or missing")
            status="fail"
        elif [[ "$r" != "$len" ]]; then
            bad+=("episode_$(printf '%06d' "$idx"): parquet rows=${r} != length=${len}")
            status="fail"
        fi

        for cam in "${CAM_KEYS[@]}"; do
            mp4="${root}/$(_expand_path "${META[video_path]}" "$chunk" "$idx" "$cam")"
            if [[ ! -s "$mp4" ]]; then
                bad+=("episode_$(printf '%06d' "$idx") ${cam}: video missing or zero-byte")
                status="fail"
                continue
            fi
            if ! frames=$(video_frame_count "$mp4"); then
                bad+=("episode_$(printf '%06d' "$idx") ${cam}: video unreadable")
                status="fail"
                continue
            fi
            if [[ "$frames" != "$len" ]]; then
                bad+=("episode_$(printf '%06d' "$idx") ${cam}: mp4 frames=${frames} != length=${len}")
                status="fail"
            fi
        done
    done

    local detail="all ${#EP_INDICES[@]} episodes: parquet rows == length == mp4 frames"
    (( ${#bad[@]} > 0 )) && detail="${#bad[@]} mismatch(es): $(_files_sample "${bad[@]}")"
    emit_result "cross_modal_consistency" "$status" "$detail" ""
}

# _cm_load_rows_glob ROOT GLOB ASSOC -> fill ASSOC keyed by dataset-relative path
# -> row count, via one query. Returns non-zero if the query errors.
_cm_load_rows_glob() {
    local root="$1" glob="$2"
    local -n _rows="$3"
    local out
    out=$(pq_row_counts_glob "$glob") || return 1
    local path count rel
    while IFS='|' read -r path count; do
        [[ -z "$path" ]] && continue
        rel="${path#"${root}/"}"
        _rows["$rel"]="$count"
    done <<< "$out"
    return 0
}

# _cm_load_rows_perfile ROOT ASSOC -> per-episode fallback keyed by the exact
# expected path; an unreadable parquet leaves that path unset (reported as such).
_cm_load_rows_perfile() {
    local root="$1"
    local -n _rows2="$2"
    local chunks_size="${META[chunks_size]}"
    local idx chunk pqrel pq count
    for idx in "${EP_INDICES[@]}"; do
        chunk=$(( idx / chunks_size ))
        pqrel=$(_expand_path "${META[data_path]}" "$chunk" "$idx")
        pq="${root}/${pqrel}"
        [[ -f "$pq" ]] || continue
        count=$(pq_row_count "$pq") && _rows2["$pqrel"]="$count"
    done
}
