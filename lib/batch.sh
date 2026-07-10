# shellcheck shell=bash
#
# batch.sh — dataset discovery, bounded-concurrency execution (check 13), and
# cross-dataset anomaly flagging. A single dataset and a whole folder of them
# take the SAME path through here: discover_datasets yields a list of roots and
# run_batch inspects them all, N at a time.

# discover_datasets PATH... -> print each dataset root (a dir with meta/info.json)
# found at or below the given paths, de-duplicated and sorted. Returns non-zero
# if no dataset is found anywhere.
discover_datasets() {
    local path info out
    out=$(
        for path in "$@"; do
            if [[ -f "${path}/meta/info.json" ]]; then
                printf '%s\n' "${path%/}"
            elif [[ -d "$path" ]]; then
                # A batch folder: find dataset roots at any depth beneath it.
                while IFS= read -r info; do
                    printf '%s\n' "${info%/meta/info.json}"
                done < <(find "$path" -type f -path '*/meta/info.json' 2>/dev/null)
            else
                log_warn "path is not a dataset or directory: ${path}"
            fi
        done | sort -u
    )

    [[ -n "$out" ]] || return 1
    printf '%s\n' "$out"
    return 0
}

# run_batch STRICT JOBS ROOT... -> JSON array of per-dataset objects (input order
# preserved). Runs up to JOBS inspections concurrently, each writing to its own
# temp file so there is no shared-output race.
run_batch() {
    local strict="$1" jobs="$2"; shift 2
    local -a roots=("$@")
    local tmp; tmp=$(mktemp -d)
    # shellcheck disable=SC2064  # expand tmp now so cleanup targets this dir
    trap "rm -rf '${tmp}'" RETURN

    local i=0 running=0 root
    for root in "${roots[@]}"; do
        inspect_one "$root" "$strict" > "${tmp}/${i}.json" &
        i=$(( i + 1 )); running=$(( running + 1 ))
        if (( running >= jobs )); then
            wait -n 2>/dev/null || true
            running=$(( running - 1 ))
        fi
    done
    wait || true

    local k content
    local -a objs=()
    for (( k = 0; k < i; k++ )); do
        content=$(cat "${tmp}/${k}.json" 2>/dev/null)
        # A crashed inspection leaves an empty OR partial file; never drop a
        # dataset or emit an invalid document — validate and, on anything that is
        # not a complete JSON object, synthesize a FAIL record instead.
        if [[ -z "$content" ]] || ! jq empty <<< "$content" 2>/dev/null; then
            content=$(jq -cn --arg p "${roots[$k]}" \
                '{path:$p, verdict:"FAIL", worst_status:"fail", error:"inspection failed unexpectedly", stats:null, checks:[], issues:["internal: inspection failed"]}')
        fi
        objs+=("$content")
    done
    printf '%s\n' "${objs[@]}" | jq -s '.'
}

# flag_cross_dataset_anomalies DATASETS_ARRAY RATIO -> JSON array of anomaly
# strings: datasets whose fps deviates from the batch median fps by more than
# RATIO. Only meaningful with >= 3 datasets.
flag_cross_dataset_anomalies() {
    local datasets="$1" ratio="$2"
    jq -c --argjson ratio "$ratio" '
        def fabs: if . < 0 then - . else . end;
        def median:
            (sort) as $s | ($s | length) as $n
            | if $n == 0 then null
              elif $n % 2 == 1 then $s[($n - 1) / 2]
              else ($s[$n/2 - 1] + $s[$n/2]) / 2 end;
        . as $ds
        | if ($ds | length) < 3 then []
          else
            ([ $ds[] | .stats.fps | select(. != null and . > 0) ]) as $fps
            | ($fps | median) as $mf
            | [ $ds[]
                | select(.stats.fps != null and $mf != null and $mf > 0
                         and ((((.stats.fps - $mf) / $mf) | fabs) > $ratio))
                | "\(.path): fps=\(.stats.fps) deviates from batch median \($mf)" ]
          end
    ' <<< "$datasets"
}
