#!/usr/bin/env bash
#
# run-tests.sh — deliverable 2: prove lerobot-inspect catches deliberate
# corruption. Starting from a KNOWN-GOOD dataset, it makes an isolated copy,
# injects one defect per case (the classes named in the brief: drop a frame,
# truncate a parquet, corrupt info.json, delete a file, perturb a stat, and
# lie in the metadata), runs the tool, and asserts the right check fails.
#
# Read-only guarantee: the pristine source is never modified. Copies are made
# with hardlinks (instant, no extra space); before any file is mutated its link
# is broken with rm so the write lands on a fresh inode, never the original.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_DIR
readonly TOOL="${SCRIPT_DIR}/../lerobot-inspect"
readonly DEFAULT_SRC="${SCRIPT_DIR}/../datasets_repo/datasets/dataset-4"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; NC=$'\033[0m'
[[ -t 1 ]] || { RED=""; GREEN=""; YELLOW=""; NC=""; }

PASS_COUNT=0
FAIL_COUNT=0
WORK=""
SRC=""

# Don't litter results/ during the defect tests; the save feature has its own
# dedicated test that re-enables saving into a temp dir.
export LEROBOT_INSPECT_SAVE_RESULTS=false

usage() {
    cat <<EOF

run-tests.sh — inject deliberate defects into a copy of a clean dataset and
verify lerobot-inspect detects each one.

usage: $(basename "$0") [clean-dataset]

    clean-dataset   A dataset that passes cleanly (default: ${DEFAULT_SRC}).

The dataset is copied (read-only toward the source); every defect is applied to
an isolated copy under a temp dir that is removed on exit.

EOF
}

main() {
    case "${1:-}" in
        -h|--help) usage; exit 0 ;;
    esac
    SRC="${1:-$DEFAULT_SRC}"

    [[ -x "$TOOL" ]]            || fail_hard "tool not found or not executable: $TOOL"
    [[ -f "$SRC/meta/info.json" ]] || fail_hard "clean dataset not found: $SRC"

    WORK=$(mktemp -d "${SCRIPT_DIR}/../.tests-work.XXXXXX")
    trap 'rm -rf "$WORK"' EXIT

    echo "Baseline: the clean source must PASS before we can trust FAILs."
    if "$TOOL" "$SRC" >/dev/null 2>&1; then
        pass "baseline clean dataset PASSes (exit 0)"
    else
        fail "baseline clean dataset did NOT pass — cannot trust results"
    fi

    test_corrupt_info_json
    test_truncate_parquet
    test_delete_parquet
    test_zero_byte_video
    test_perturb_stat
    test_metadata_lie
    test_drop_video_frame
    test_malformed_tasks
    test_orphan_file
    test_nonmonotonic_timestamp
    test_noninteger_episode_index
    test_misplaced_parquet
    test_strict_exit_code
    test_error_exit_codes
    test_results_saved

    echo
    echo "==================================================="
    printf 'Results: %s%d passed%s, %s%d failed%s\n' \
        "$GREEN" "$PASS_COUNT" "$NC" "$RED" "$FAIL_COUNT" "$NC"
    (( FAIL_COUNT == 0 )) || exit 1
}

# --- defect injectors: each makes a copy, mutates it, and asserts detection ---

test_corrupt_info_json() {
    local d; d=$(make_copy corrupt-info)
    replace "$d/meta/info.json" '{ "codebase_version": broken not json '
    assert_meta_fail "corrupt info.json" "$d"
}

test_truncate_parquet() {
    local d; d=$(make_copy truncate-parquet)
    local rel="data/chunk-000/episode_000000.parquet"
    local sz; sz=$(stat -c%s "$SRC/$rel")
    rm -f "$d/$rel"
    head -c "$(( sz / 2 ))" "$SRC/$rel" > "$d/$rel"
    assert_check_fail "truncated parquet" "$d" "cross_modal_consistency"
}

test_delete_parquet() {
    local d; d=$(make_copy delete-parquet)
    rm -f "$d/data/chunk-000/episode_000002.parquet"
    assert_check_fail "deleted parquet (file accounting)" "$d" "file_accounting"
}

test_zero_byte_video() {
    local d; d=$(make_copy zero-video)
    local v; v=$(find "$d/videos" -name '*.mp4' | head -1)
    rm -f "$v"; : > "$v"
    assert_check_fail "zero-byte video" "$d" "cross_modal_consistency"
}

test_perturb_stat() {
    local d; d=$(make_copy perturb-stat)
    local rel="meta/episodes_stats.jsonl"
    replace "$d/$rel" "$(jq -c 'if .episode_index==0 then .stats["observation.state"].mean[0]=999.0 else . end' "$SRC/$rel")"
    assert_check_fail "perturbed stat (mean=999)" "$d" "statistical_validation"
}

test_metadata_lie() {
    local d; d=$(make_copy metadata-lie)
    replace "$d/meta/info.json" "$(jq '.total_episodes += 7' "$SRC/meta/info.json")"
    assert_check_fail "metadata lie (total_episodes)" "$d" "metadata_consistency"
}

# Optional: needs ffmpeg to re-encode a video one frame short.
test_drop_video_frame() {
    if ! command -v ffmpeg >/dev/null 2>&1; then
        skip "drop one video frame (ffmpeg not installed)"
        return
    fi
    local d; d=$(make_copy drop-frame)
    local rel; rel=$(cd "$SRC" && find videos -name 'episode_000000.mp4' | head -1)
    local n; n=$(ffprobe -v error -select_streams v:0 -show_entries stream=nb_frames -of csv=p=0 "$SRC/$rel")
    rm -f "$d/$rel"
    ffmpeg -y -loglevel error -i "$SRC/$rel" -frames:v "$(( n - 1 ))" "$d/$rel"
    assert_check_fail "dropped one video frame" "$d" "cross_modal_consistency"
}

# A malformed line mid-file must be caught, not silently truncated (regression
# for the tasks.jsonl false-PASS bug).
test_malformed_tasks() {
    local d; d=$(make_copy malformed-tasks)
    rm -f "$d/meta/tasks.jsonl"
    printf '%s\n' '{"task_index":0,"task":"ok"}' 'THIS IS NOT JSON' > "$d/meta/tasks.jsonl"
    assert_meta_fail "malformed tasks.jsonl (mid-file)" "$d"
}

# A present-but-unreferenced file is an orphan (the other half of file accounting).
test_orphan_file() {
    local d; d=$(make_copy orphan-file)
    : > "$d/data/chunk-000/episode_009999.parquet"
    assert_check_fail "orphan parquet (unreferenced)" "$d" "file_accounting"
}

# A timestamp that goes backwards must trip temporal integrity.
test_nonmonotonic_timestamp() {
    if ! command -v duckdb >/dev/null 2>&1; then
        skip "non-monotonic timestamp (duckdb not on PATH)"
        return
    fi
    local d; d=$(make_copy nonmono-ts)
    local rel="data/chunk-000/episode_000000.parquet"
    rm -f "$d/$rel"
    duckdb -c "COPY (SELECT * REPLACE (
                    (CASE WHEN frame_index = 50 THEN timestamp - 10 ELSE timestamp END) AS timestamp)
                 FROM read_parquet('$SRC/$rel'))
               TO '$d/$rel' (FORMAT parquet);" 2>/dev/null
    assert_check_fail "non-monotonic timestamp" "$d" "temporal_integrity"
}

# A non-integer episode_index must be a clean FAIL, never a crash or false PASS.
test_noninteger_episode_index() {
    local d; d=$(make_copy nonint-index)
    replace "$d/meta/episodes.jsonl" \
        "$(jq -c 'if .episode_index==2 then .episode_index="foo" else . end' "$SRC/meta/episodes.jsonl")"
    assert_meta_fail "non-integer episode_index" "$d"
}

# A parquet in the wrong chunk directory must not be silently matched by index.
test_misplaced_parquet() {
    local d; d=$(make_copy misplaced-parquet)
    local rel="data/chunk-000/episode_000002.parquet"
    mkdir -p "$d/data/chunk-001"
    cp "$SRC/$rel" "$d/data/chunk-001/episode_000002.parquet"
    rm -f "$d/$rel"
    assert_check_fail "misplaced parquet (wrong chunk)" "$d" "cross_modal_consistency"
}

# --strict must make a warn-only dataset FAIL and exit 2, while a plain run exits 1.
test_strict_exit_code() {
    local d; d=$(make_copy strict-warn)
    rm -f "$d/meta/episodes_stats.jsonl"   # -> statistical_validation: warn (no stats file)
    local ec
    "$TOOL" "$d" >/dev/null 2>&1 && ec=0 || ec=$?
    assert_eq "warn-only (plain) -> exit 1" 1 "$ec"
    "$TOOL" --strict "$d" >/dev/null 2>&1 && ec=0 || ec=$?
    assert_eq "warn-only (--strict) -> exit 2" 2 "$ec"
}

# Usage errors exit 3; a missing dependency exits 4.
test_error_exit_codes() {
    local ec
    "$TOOL" >/dev/null 2>&1 && ec=0 || ec=$?
    assert_eq "no arguments -> exit 3" 3 "$ec"

    "$TOOL" /nonexistent/path/xyz >/dev/null 2>&1 && ec=0 || ec=$?
    assert_eq "nonexistent path -> exit 3" 3 "$ec"

    # duckdb lives outside /usr/bin:/bin, so this hides only it while keeping
    # jq/ffprobe/awk/du/find available -> a clean missing-dependency (exit 4).
    env PATH="/usr/bin:/bin" "$TOOL" "$SRC" >/dev/null 2>&1 && ec=0 || ec=$?
    assert_eq "missing dependency -> exit 4" 4 "$ec"
}

# A run should persist a markdown report AND an explanatory companion.
test_results_saved() {
    local d; d=$(make_copy results-save)
    local res="$WORK/res"
    LEROBOT_INSPECT_SAVE_RESULTS=true "$TOOL" --results-dir "$res" "$d" >/dev/null 2>&1 || true
    local md json exp
    md=$(find "$res" -name 'run_*.md' ! -name '*_explanation.md' 2>/dev/null | head -1)
    json=$(find "$res" -name 'run_*.json' 2>/dev/null | head -1)
    exp=$(find "$res" -name 'run_*_explanation.md' 2>/dev/null | head -1)
    if [[ -f "$md" && -f "$json" && -f "$exp" ]]; then
        pass "run saved markdown + json report + explanation"
    else
        fail "run missing a file (md='${md}' json='${json}' explanation='${exp}')"
    fi
}

# --- helpers ---------------------------------------------------------------

make_copy() {
    local dst="$WORK/$1"
    cp -al "$SRC" "$dst"
    printf '%s' "$dst"
}

# replace FILE CONTENT — break the hardlink first so the source is untouched.
replace() {
    local file="$1" content="$2"
    rm -f "$file"
    printf '%s' "$content" > "$file"
}

# assert_check_fail NAME DATASET CHECK — tool must exit 2 and mark CHECK failed.
assert_check_fail() {
    local name="$1" dst="$2" check="$3" out ec status
    out=$("$TOOL" --json "$dst" 2>/dev/null) && ec=0 || ec=$?
    status=$(jq -r --arg c "$check" '.datasets[0].checks[]? | select(.check==$c) | .status' <<< "$out")
    if [[ "$ec" -eq 2 && "$status" == "fail" ]]; then
        pass "$name -> ${check} FAIL (exit 2)"
    else
        fail "$name -> expected ${check}=fail & exit 2, got status='${status}' exit=${ec}"
    fi
}

# assert_meta_fail NAME DATASET — unparseable metadata: verdict FAIL, exit 2.
assert_meta_fail() {
    local name="$1" dst="$2" out ec verdict
    out=$("$TOOL" --json "$dst" 2>/dev/null) && ec=0 || ec=$?
    verdict=$(jq -r '.datasets[0].verdict' <<< "$out")
    if [[ "$ec" -eq 2 && "$verdict" == "FAIL" ]]; then
        pass "$name -> verdict FAIL (exit 2)"
    else
        fail "$name -> expected verdict FAIL & exit 2, got verdict='${verdict}' exit=${ec}"
    fi
}

# assert_eq NAME EXPECTED ACTUAL
assert_eq() {
    if [[ "$3" -eq "$2" ]]; then
        pass "$1"
    else
        fail "$1 (expected ${2}, got ${3})"
    fi
}

pass() { PASS_COUNT=$(( PASS_COUNT + 1 )); printf '  %s[PASS]%s %s\n' "$GREEN" "$NC" "$1"; }
fail() { FAIL_COUNT=$(( FAIL_COUNT + 1 )); printf '  %s[FAIL]%s %s\n' "$RED" "$NC" "$1"; }
skip() { printf '  %s[SKIP]%s %s\n' "$YELLOW" "$NC" "$1"; }
fail_hard() { printf '%s[ERROR]%s %s\n' "$RED" "$NC" "$1" >&2; exit 1; }

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
