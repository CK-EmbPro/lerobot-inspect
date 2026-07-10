# shellcheck shell=bash
#
# check_files.sh — check 8 (file accounting). Expands the data_path and
# video_path templates from info.json for every declared episode and camera,
# using chunk math (episode_index / chunks_size), to compute the exact set of
# files that SHOULD exist. Diffs that against what is actually on disk and
# reports both directions: missing (referenced but absent) and orphan (present
# but never referenced — e.g. an unregistered episode or a stray chunk dir).

# _expand_path TEMPLATE CHUNK EPISODE [VIDEO_KEY] -> concrete relative path.
# Honors the template tokens rather than hardcoding the layout.
_expand_path() {
    local out="$1" chunk="$2" idx="$3" cam="${4:-}"
    out="${out//\{episode_chunk:03d\}/$(printf '%03d' "$chunk")}"
    out="${out//\{episode_index:06d\}/$(printf '%06d' "$idx")}"
    out="${out//\{video_key\}/$cam}"
    printf '%s' "$out"
}

check_files() {
    local root="$1"
    local -A expected=() seen=()
    local -a missing=() orphan=()

    if [[ ! "${META[chunks_size]}" =~ ^[0-9]+$ ]] || (( META[chunks_size] <= 0 )); then
        emit_result "file_accounting" "fail" \
            "cannot compute file layout: invalid chunks_size '${META[chunks_size]}'" "meta/info.json"
        return
    fi

    # Build the expected set from templates + chunk math.
    local idx chunk rel cam
    for idx in "${EP_INDICES[@]}"; do
        chunk=$(( idx / META[chunks_size] ))
        rel=$(_expand_path "${META[data_path]}" "$chunk" "$idx")
        expected["$rel"]=1
        for cam in "${CAM_KEYS[@]}"; do
            rel=$(_expand_path "${META[video_path]}" "$chunk" "$idx" "$cam")
            expected["$rel"]=1
        done
    done

    # Walk actual files once; classify each as expected (seen) or orphan.
    local abs
    while IFS= read -r abs; do
        rel="${abs#"${root}/"}"
        if [[ -n "${expected[$rel]:-}" ]]; then
            seen["$rel"]=1
        else
            orphan+=("$rel")
        fi
    done < <(find "$root/data" "$root/videos" -type f \( -name '*.parquet' -o -name '*.mp4' \) 2>/dev/null)

    # Anything expected but never seen is missing.
    for rel in "${!expected[@]}"; do
        [[ -n "${seen[$rel]:-}" ]] || missing+=("$rel")
    done

    local status="ok" detail="all ${#expected[@]} referenced files present, no orphans"
    if (( ${#missing[@]} > 0 || ${#orphan[@]} > 0 )); then
        status="fail"
        detail="$(( ${#missing[@]} )) missing, $(( ${#orphan[@]} )) orphan"
        [[ ${#missing[@]} -gt 0 ]] && detail+="; missing: $(_files_sample "${missing[@]}")"
        [[ ${#orphan[@]}  -gt 0 ]] && detail+="; orphan: $(_files_sample "${orphan[@]}")"
    fi
    emit_result "file_accounting" "$status" "$detail" ""
}

# _files_sample PATHS... -> comma list of up to 5 paths, then "(+N more)".
_files_sample() {
    local -a all=("$@")
    local n="${#all[@]}" shown=5 out="" i
    (( shown > n )) && shown=n
    for (( i = 0; i < shown; i++ )); do
        [[ -n "$out" ]] && out+=", "
        out+="${all[$i]}"
    done
    (( n > shown )) && out+=" (+$(( n - shown )) more)"
    printf '%s' "$out"
}
