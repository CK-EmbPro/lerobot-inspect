# shellcheck shell=bash
#
# deps.sh — declare and verify external tools. A missing dependency is an
# environment error (exit 4), reported with an exact, actionable message —
# never a raw "command not found" from deep inside a check.

# Required tools and, for the error message, what each is used for.
readonly -A DEP_PURPOSE=(
    [jq]="parse JSON metadata"
    [ffprobe]="read video frame counts and resolution (from ffmpeg)"
    [duckdb]="read parquet row counts and column statistics"
    [awk]="floating-point arithmetic"
    [du]="measure on-disk size"
    [find]="enumerate dataset files"
)

# require_dependencies — verify every declared tool is on PATH, or exit 4.
# Collects ALL missing tools so the user fixes them in one pass, not one per run.
require_dependencies() {
    local missing=() cmd
    for cmd in "${!DEP_PURPOSE[@]}"; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done

    if (( ${#missing[@]} > 0 )); then
        log_error "Missing required dependencies:"
        for cmd in "${missing[@]}"; do
            log_error "  - ${cmd}: needed to ${DEP_PURPOSE[$cmd]}"
        done
        log_error "Install them and retry (e.g. apt install jq ffmpeg; duckdb from duckdb.org)."
        exit "$EX_ENV"
    fi
    log_debug "All dependencies present: ${!DEP_PURPOSE[*]}"
}
