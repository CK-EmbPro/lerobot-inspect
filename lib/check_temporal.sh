# shellcheck shell=bash
#
# check_temporal.sh — check 10 (temporal integrity). For every episode the
# timestamp column must increase monotonically (FAIL if not); the empirical
# frame rate must match the declared fps within tolerance, and large inter-frame
# gaps are flagged (WARN — these occur naturally in real captures and promote to
# FAIL under --strict). Rate is bounded two ways: a per-frame absolute tolerance
# (recommended_tolerance_s, else config) and a relative fps tolerance for gross
# errors the absolute one is too lenient to catch.
#
# Episodes are keyed by their exact expected relative path (chunk math), so a
# misplaced parquet is not silently matched by index. A corrupt parquet aborts
# the fast glob read, so it falls back to per-episode reads.

check_temporal() {
    local root="$1"
    local glob="${root}/data/**/*.parquet"
    local -A tinfo=()
    _temporal_collect "$root" "$glob" tinfo

    local fps="${META[fps]}"
    if [[ ! "$fps" =~ ^[0-9]+([.][0-9]+)?$ ]] || ! awk -v f="$fps" 'BEGIN{exit !(f>0)}'; then
        emit_result "temporal_integrity" "warn" \
            "cannot validate timing: declared fps is invalid ('${fps}')" "meta/info.json"
        return
    fi

    local tol="${META[recommended_tolerance_s]}"
    [[ "$tol" =~ ^[0-9]+([.][0-9]+)?$ ]] || tol="${LEROBOT_INSPECT_FPS_TOLERANCE_S:-0.04}"
    local rel_tol="${LEROBOT_INSPECT_FPS_REL_TOL:-0.10}"

    local status="ok"
    local -a issues=()
    local chunks_size="${META[chunks_size]}"
    local idx chunk pqrel rec count mints maxts nonmono maxgap emp_fps
    for idx in "${EP_INDICES[@]}"; do
        chunk=$(( idx / chunks_size ))
        pqrel=$(_expand_path "${META[data_path]}" "$chunk" "$idx")
        rec="${tinfo[$pqrel]:-}"
        if [[ -z "$rec" ]]; then
            if [[ -f "${root}/${pqrel}" ]]; then
                issues+=("episode_$(printf '%06d' "$idx"): parquet unreadable (corrupt or missing timestamp)")
                status="fail"
            fi
            continue
        fi
        IFS='|' read -r count mints maxts nonmono maxgap <<< "$rec"

        if [[ "$nonmono" =~ ^[0-9]+$ ]] && (( nonmono > 0 )); then
            issues+=("episode_$(printf '%06d' "$idx"): ${nonmono} non-monotonic timestamp(s)")
            status="fail"
        fi

        if [[ "$count" =~ ^[0-9]+$ ]] && (( count > 1 )); then
            emp_fps=$(awk -v c="$count" -v lo="$mints" -v hi="$maxts" 'BEGIN{ if(hi>lo) printf "%.3f",(c-1)/(hi-lo); else print "inf" }')
            # Rate mismatch (absolute per-frame OR relative fps) and large gaps
            # are data-quality WARNINGS; only non-monotonic timestamps are FAIL.
            if _temporal_rate_off "$count" "$mints" "$maxts" "$fps" "$tol" "$rel_tol"; then
                issues+=("episode_$(printf '%06d' "$idx"): empirical fps=${emp_fps} != declared ${fps}")
                status=$(status_worst "$status" "warn")
            fi
            if awk -v g="$maxgap" -v fps="$fps" -v tol="$tol" 'BEGIN{ exit !(g > 1/fps + tol) }'; then
                issues+=("episode_$(printf '%06d' "$idx"): max gap ${maxgap}s > one frame period (dropped frames?)")
                status=$(status_worst "$status" "warn")
            fi
        fi
    done

    local detail="all ${#EP_INDICES[@]} episodes: timestamps monotonic, empirical fps within tolerance of declared"
    (( ${#issues[@]} > 0 )) && detail="${#issues[@]} issue(s): $(_files_sample "${issues[@]}")"
    emit_result "temporal_integrity" "$status" "$detail" ""
}

# _temporal_rate_off COUNT MIN MAX FPS ABS_TOL REL_TOL -> exit 0 if the empirical
# frame period differs from 1/fps by more than ABS_TOL seconds, OR the empirical
# fps differs from the declared fps by more than the REL_TOL fraction.
_temporal_rate_off() {
    awk -v c="$1" -v lo="$2" -v hi="$3" -v fps="$4" -v tol="$5" -v rel="$6" 'BEGIN{
        if (hi <= lo) exit 0
        ep = (hi - lo) / (c - 1); dp = 1 / fps
        d = ep - dp; if (d < 0) d = -d
        ef = (c - 1) / (hi - lo); rd = (ef - fps) / fps; if (rd < 0) rd = -rd
        exit !(d > tol || rd > rel)
    }'
}

# _temporal_collect ROOT GLOB ASSOC -> fill ASSOC keyed by relative path ->
# "count|min|max|nonmono|gap". Fast glob path with per-episode fallback.
_temporal_collect() {
    local root="$1" glob="$2"
    local -n _t="$3"
    local out
    if out=$(pq_temporal_glob "$glob"); then
        local path rest rel
        while IFS='|' read -r path rest; do
            [[ -z "$path" ]] && continue
            rel="${path#"${root}/"}"
            _t["$rel"]="$rest"
        done <<< "$out"
        return 0
    fi
    log_debug "temporal glob failed; per-episode fallback (a parquet is likely corrupt)"
    local chunks_size="${META[chunks_size]}"
    local idx chunk pqrel pq single
    for idx in "${EP_INDICES[@]}"; do
        chunk=$(( idx / chunks_size ))
        pqrel=$(_expand_path "${META[data_path]}" "$chunk" "$idx")
        pq="${root}/${pqrel}"
        [[ -f "$pq" ]] || continue
        single=$(pq_temporal "$pq") && _t["$pqrel"]="$single"
    done
}
