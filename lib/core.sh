# shellcheck shell=bash disable=SC2034
# (SC2034: constants below are consumed by sibling libraries that source this
#  file; shellcheck analyzes each file in isolation and cannot see that use.)
#
# core.sh — foundational primitives shared by every other library:
# exit codes, the ok/warn/fail status algebra, colored logging to STDERR,
# and the awk-backed float helpers (bash has no floating-point math).
#
# Sourced, never executed. Contains no top-level logic.

# Documented exit codes (see README exit-code table).
readonly EX_OK=0        # all checks passed
readonly EX_WARN=1      # warnings, or any failure promoted by --strict
readonly EX_INTEGRITY=2 # a real integrity failure / corruption
readonly EX_USAGE=3     # usage / argument error
readonly EX_ENV=4       # missing dependency or environment error

# Colors, honoring NO_COLOR and dumb terminals. Empty when not a TTY so that
# piped/redirected output (and the JSON report) never carries escape codes.
if [[ -t 2 && -z "${NO_COLOR:-}" && "${TERM:-}" != "dumb" ]]; then
    C_RED=$'\033[0;31m'; C_GREEN=$'\033[0;32m'; C_YELLOW=$'\033[1;33m'
    C_BLUE=$'\033[0;34m'; C_DIM=$'\033[2m'; C_NC=$'\033[0m'
else
    C_RED=""; C_GREEN=""; C_YELLOW=""; C_BLUE=""; C_DIM=""; C_NC=""
fi

# All human logging goes to STDERR so STDOUT stays a clean data channel
# (human report or JSON) that composes in a pipe.
log_error() { printf '%s[ERROR]%s %s\n' "$C_RED"    "$C_NC" "$*" >&2; }
log_warn()  { printf '%s[WARN]%s %s\n'  "$C_YELLOW" "$C_NC" "$*" >&2; }
log_info()  { printf '%s[INFO]%s %s\n'  "$C_BLUE"   "$C_NC" "$*" >&2; }
log_debug() { [[ -n "${LEROBOT_INSPECT_VERBOSE:-}" ]] && printf '%s[DEBUG] %s%s\n' "$C_DIM" "$*" "$C_NC" >&2; return 0; }

# die MESSAGE EXIT_CODE — log and terminate with a documented code.
die() {
    local message="$1" code="${2:-$EX_USAGE}"
    log_error "$message"
    exit "$code"
}

# ---- status algebra -----------------------------------------------------
# The three check statuses are totally ordered: ok < warn < fail.
# A dataset's verdict is driven by the worst status among its checks.

status_rank() {
    case "$1" in
        ok)   echo 0 ;;
        warn) echo 1 ;;
        fail) echo 2 ;;
        *)    echo 2 ;;  # unknown is treated as the worst, never a silent pass
    esac
}

# status_worst A B -> echoes whichever of the two is more severe.
status_worst() {
    local ra rb
    ra=$(status_rank "$1"); rb=$(status_rank "$2")
    if (( ra >= rb )); then echo "$1"; else echo "$2"; fi
}

# ---- float helpers (awk, since bash is integer-only) --------------------

# within_tol A B TOL -> exit 0 (true) iff |A-B| <= TOL.
within_tol() {
    awk -v a="$1" -v b="$2" -v t="$3" 'BEGIN { d = a - b; if (d < 0) d = -d; exit !(d <= t) }'
}

# is_number STRING -> exit 0 iff STRING is a finite decimal number (scientific
# notation included, since duckdb/jq emit small magnitudes as e.g. 2e-07).
is_number() {
    awk -v s="$1" 'BEGIN { if (s ~ /^-?[0-9]+([.][0-9]+)?([eE][+-]?[0-9]+)?$/) exit 0; exit 1 }'
}

# human_bytes N -> echoes a human-readable size (e.g. "1.3 GiB").
human_bytes() {
    awk -v b="$1" 'BEGIN {
        split("B KiB MiB GiB TiB PiB", u, " ")
        i = 1
        while (b >= 1024 && i < 6) { b /= 1024; i++ }
        if (i == 1) printf "%d %s", b, u[i]; else printf "%.1f %s", b, u[i]
    }'
}
