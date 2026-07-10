# shellcheck shell=bash
#
# check_stats.sh — check 11 (statistical validation). Recomputes min/max/mean/std
# for the numeric feature columns observation.state and action directly from the
# parquet data and diffs them against the stored stats within a configurable
# absolute tolerance. Handles both schemas (check 12): v2.1 per-episode
# episodes_stats.jsonl and v2.0 global stats.json. Stored std is population std
# (numpy default), matched here by duckdb stddev_pop.
#
# Recompute uses one glob query per feature, falling back to per-episode reads if
# that aborts, so a single corrupt parquet does not silently skip validation of
# every other episode (which could hide a perturbed stat elsewhere).
#
# Image-feature stats are intentionally NOT validated: their pixels live in the
# mp4 videos, not the parquet, so they cannot be recomputed from the data here.

readonly STATS_FEATURES=("observation.state" "action")

check_stats() {
    local root="$1"
    local mode="${META[stats_mode]}" statsfile="${META[stats_file]}"
    local tol="${LEROBOT_INSPECT_TOLERANCE:-0.01}"
    [[ "$tol" =~ ^[0-9]+([.][0-9]+)?$ ]] || tol="0.01"
    local glob="${root}/data/**/*.parquet"

    if [[ "$mode" == "none" || -z "$statsfile" ]]; then
        emit_result "statistical_validation" "warn" \
            "no stats file (stats.json / episodes_stats.jsonl) present to validate against" ""
        return
    fi
    if ! jq empty "$statsfile" 2>/dev/null; then
        emit_result "statistical_validation" "fail" \
            "stats file is not valid JSON: ${statsfile##*/}" "meta/${statsfile##*/}"
        return
    fi

    local status="ok"
    local -a issues=()
    local feat
    for feat in "${STATS_FEATURES[@]}"; do
        if [[ "$mode" == "per_episode" ]]; then
            _stats_check_per_episode "$root" "$glob" "$statsfile" "$feat" "$tol"
        else
            _stats_check_global "$glob" "$statsfile" "$feat" "$tol"
        fi
    done

    local detail="recomputed stats for ${STATS_FEATURES[*]} match stored values within ${tol}"
    (( ${#issues[@]} > 0 )) && detail="${#issues[@]} deviation(s) > ${tol}: $(_files_sample "${issues[@]}")"
    emit_result "statistical_validation" "$status" "$detail" ""
}

# Validate v2.1 per-episode stats. Appends to caller-scoped issues/status.
_stats_check_per_episode() {
    local root="$1" glob="$2" statsfile="$3" feat="$4" tol="$5"
    local -A R=()
    _stats_recompute_per_episode "$root" "$glob" "$feat" R
    (( ${#R[@]} == 0 )) && return 0   # feature absent from the parquet data

    local e j smin smax smean sstd key
    while IFS=$'\t' read -r e j smin smax smean sstd; do
        key="${e}:${j}"
        [[ -n "${R[$key]:-}" ]] || continue
        _stats_diff "$feat" "episode_$(printf '%06d' "$e") dim${j}" "${R[$key]}" \
            "$smin" "$smax" "$smean" "$sstd" "$tol"
    done < <(_stats_stored_per_episode "$statsfile" "$feat")
}

# Recompute per-episode, per-dimension stats into R (keyed "idx:dim0based").
# Glob fast path, per-episode fallback when the glob read aborts.
_stats_recompute_per_episode() {
    local root="$1" glob="$2" feat="$3"
    local -n _R="$4"
    local out path i mn mx me sd num idx j single chunks_size pq
    if out=$(pq_array_stats_glob "$glob" "$feat" 2>/dev/null) && [[ -n "$out" ]]; then
        while IFS='|' read -r path i mn mx me sd; do
            [[ -z "$path" ]] && continue
            num="${path##*/}"; num="${num#episode_}"; num="${num%.parquet}"
            # Guard the base-10 conversion: a stray/oddly-named file must be
            # skipped, never crash `$(( 10#$num ))` under set -e.
            [[ "$num" =~ ^[0-9]+$ ]] || continue
            idx=$(( 10#$num )); j=$(( i - 1 ))
            _R["$idx:$j"]="$mn|$mx|$me|$sd"
        done <<< "$out"
        return 0
    fi
    chunks_size="${META[chunks_size]}"
    for idx in "${EP_INDICES[@]}"; do
        pq="${root}/$(_expand_path "${META[data_path]}" "$(( idx / chunks_size ))" "$idx")"
        [[ -f "$pq" ]] || continue
        single=$(pq_array_stats "$pq" "$feat" 2>/dev/null) || continue
        while IFS='|' read -r i mn mx me sd; do
            [[ "$i" =~ ^[0-9]+$ ]] || continue
            j=$(( i - 1 )); _R["$idx:$j"]="$mn|$mx|$me|$sd"
        done <<< "$single"
    done
}

# Validate v2.0 global stats.json over the whole dataset.
_stats_check_global() {
    local glob="$1" statsfile="$2" feat="$3" tol="$4"
    local -A R=()
    local i mn mx me sd j out
    if ! out=$(pq_array_stats_whole "$glob" "$feat" 2>/dev/null); then
        issues+=("${feat}: cannot recompute global stats (unreadable/corrupt parquet)")
        status="fail"
        return
    fi
    [[ -z "$out" ]] && return 0   # feature absent
    while IFS='|' read -r i mn mx me sd; do
        [[ "$i" =~ ^[0-9]+$ ]] || continue
        j=$(( i - 1 )); R["$j"]="$mn|$mx|$me|$sd"
    done <<< "$out"

    local smin smax smean sstd
    while IFS=$'\t' read -r j smin smax smean sstd; do
        [[ -n "${R[$j]:-}" ]] || continue
        _stats_diff "$feat" "global dim${j}" "${R[$j]}" "$smin" "$smax" "$smean" "$sstd" "$tol"
    done < <(_stats_stored_global "$statsfile" "$feat")
}

# Emit stored (episode, dim, min, max, mean, std) rows for a feature (v2.1).
_stats_stored_per_episode() {
    local statsfile="$1" feat="$2"
    jq -r --arg f "$feat" '
        select(.stats[$f] != null and (.stats[$f].mean | type) == "array")
        | .episode_index as $e | .stats[$f] as $s
        | range(0; ($s.mean | length)) as $i
        | [$e, $i, $s.min[$i], $s.max[$i], $s.mean[$i], $s.std[$i]] | @tsv
    ' "$statsfile" 2>/dev/null
}

# Emit stored (dim, min, max, mean, std) rows for a feature (v2.0 global).
_stats_stored_global() {
    local statsfile="$1" feat="$2"
    jq -r --arg f "$feat" '
        (.[$f] // .stats[$f]) as $s
        | select($s != null and ($s.mean | type) == "array")
        | range(0; ($s.mean | length)) as $i
        | [$i, $s.min[$i], $s.max[$i], $s.mean[$i], $s.std[$i]] | @tsv
    ' "$statsfile" 2>/dev/null
}

# _stats_diff FEATURE LABEL "min|max|mean|std"(recomputed) SMIN SMAX SMEAN SSTD TOL
# Compares each of the four statistics; records a deviation beyond TOL via the
# caller's issues[]/status (dynamic scope).
_stats_diff() {
    local feat="$1" label="$2" recomputed="$3" smin="$4" smax="$5" smean="$6" sstd="$7" tol="$8"
    local rmin rmax rmean rstd
    IFS='|' read -r rmin rmax rmean rstd <<< "$recomputed"

    # Accept scientific notation: duckdb (avg/stddev) and jq both render small
    # magnitudes as e.g. 2e-07 / 3.45E-8. Without the exponent the gate would
    # skip near-zero stats entirely — a false OK on those dimensions.
    local num_re='^-?[0-9]+([.][0-9]+)?([eE][+-]?[0-9]+)?$'
    local pair name sval rval
    for pair in "min|$smin|$rmin" "max|$smax|$rmax" "mean|$smean|$rmean" "std|$sstd|$rstd"; do
        IFS='|' read -r name sval rval <<< "$pair"
        [[ "$sval" =~ $num_re && "$rval" =~ $num_re ]] || continue
        if ! within_tol "$rval" "$sval" "$tol"; then
            issues+=("${feat} ${label} ${name}: stored=${sval} recomputed=${rval}")
            status="fail"
        fi
    done
}
