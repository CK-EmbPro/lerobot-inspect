# shellcheck shell=bash
#
# discover_datasets.sh — find the dataset roots (directories containing
# meta/info.json) at or below the given paths. This is what lets a single dataset
# and a whole folder of datasets take the same code path: both resolve to a list
# of roots here. Yields a de-duplicated, sorted list; returns non-zero if none.

# discover_datasets PATH... -> print each dataset root, one per line.
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
