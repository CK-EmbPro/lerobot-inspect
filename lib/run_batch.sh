# shellcheck shell=bash
#
# run_batch.sh — inspect a list of datasets with bounded concurrency (check 13):
# up to JOBS at a time, each worker writing to its own temp file so there is no
# shared-output race, then merged into a JSON array in input order. A crashed
# worker becomes a synthesized FAIL record — never a dropped dataset or an
# invalid document.

# run_batch STRICT JOBS ROOT... -> JSON array of per-dataset objects.
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
