# shellcheck shell=bash disable=SC2034
# (SC2034: the META/EP_*/CAM_*/TASK_* globals populated here are read by the
#  check libraries that source this file, not within meta.sh itself.)
#
# meta.sh — version-aware readers for LeRobot metadata. meta_load() parses
# meta/info.json, episodes.jsonl and tasks.jsonl exactly once into globals the
# check libraries consume. Parsing is intentionally permissive: a missing or
# empty field is recorded as "" and left for check_metadata to judge, so the
# tool never dies mid-inspection on metadata that is merely wrong.
#
# Globals populated by meta_load (reset on every call):
#   META         assoc: scalar info.json fields (fps, chunks_size, total_*, ...)
#   CAM_KEYS     array: video feature keys, e.g. observation.images.wrist_left
#   CAM_SHAPE    assoc: cam key -> "WIDTHxHEIGHT" declared in features
#   CAM_FPS      assoc: cam key -> declared video fps (v2.0/v2.1 nesting handled)
#   EP_INDICES   array: episode_index of every line in episodes.jsonl (in order)
#   EP_LEN       assoc: episode_index -> declared frame length
#   TASK_LIST    array: task strings from tasks.jsonl (in order)
#
# meta_load returns non-zero (with META_ERROR set) when info.json is absent or
# malformed; the caller turns that into a dataset-level FAIL.

declare -gA META EP_LEN CAM_SHAPE CAM_FPS
declare -ga CAM_KEYS EP_INDICES TASK_LIST
declare -g META_ERROR

meta_load() {
    local root="$1"
    META=(); EP_LEN=(); CAM_SHAPE=(); CAM_FPS=(); CAM_KEYS=(); EP_INDICES=(); TASK_LIST=()
    META_ERROR=""

    local info="${root}/meta/info.json"
    if [[ ! -f "$info" ]]; then
        META_ERROR="meta/info.json not found (is this a LeRobot dataset root?)"
        return 1
    fi
    if ! jq empty "$info" 2>/dev/null; then
        META_ERROR="meta/info.json is not valid JSON"
        return 1
    fi

    _meta_load_info "$info"       || return 1
    _meta_load_cameras "$info"
    _meta_load_episodes "$root"   || return 1
    _meta_load_tasks "$root"      || return 1
    _meta_resolve_stats_mode "$root"
    return 0
}

# Scalar info.json fields. Absent fields become "" (empty), not the string
# "null" — check_metadata distinguishes present-but-invalid from absent.
_meta_load_info() {
    local info="$1" key
    local -A q=(
        [version]='.codebase_version'
        [robot_type]='.robot_type'
        [fps]='.fps'
        [chunks_size]='.chunks_size'
        [total_episodes]='.total_episodes'
        [total_frames]='.total_frames'
        [total_videos]='.total_videos'
        [total_tasks]='.total_tasks'
        [total_chunks]='.total_chunks'
        [recommended_tolerance_s]='.recommended_tolerance_s'
        [data_path]='.data_path'
        [video_path]='.video_path'
    )
    for key in "${!q[@]}"; do
        META[$key]=$(jq -r "${q[$key]} // empty" "$info" 2>/dev/null) || {
            META_ERROR="failed reading ${q[$key]} from info.json"
            return 1
        }
    done
    return 0
}

# Camera (video) features: name, declared resolution, declared fps. shape is
# [height, width, channels]; resolution is reported width-first (WxH).
_meta_load_cameras() {
    local info="$1" line key res fps
    while IFS=$'\t' read -r key res fps; do
        [[ -z "$key" ]] && continue
        CAM_KEYS+=("$key")
        CAM_SHAPE[$key]="$res"
        CAM_FPS[$key]="$fps"
    done < <(jq -r '
        .features // {} | to_entries[]
        | select(.value.dtype == "video")
        | [ .key,
            "\(.value.shape[1])x\(.value.shape[0])",
            ((.value.video_info["video.fps"]) // (.value.info["video.fps"]) // "") | tostring
          ] | @tsv' "$info" 2>/dev/null)
    return 0
}

# episodes.jsonl -> ordered indices + index->length map, parsed in one pass.
_meta_load_episodes() {
    local root="$1"
    local episodes="${root}/meta/episodes.jsonl" idx len
    if [[ ! -f "$episodes" ]]; then
        META_ERROR="meta/episodes.jsonl not found"
        return 1
    fi
    # Validate the whole file parses as JSONL first; a single malformed line
    # (e.g. a truncated object) must surface as an error, never a silent
    # partial read that under-counts episodes.
    if ! jq empty "$episodes" 2>/dev/null; then
        META_ERROR="meta/episodes.jsonl contains malformed JSON"
        return 1
    fi
    while IFS=$'\t' read -r idx len; do
        [[ -z "$idx" ]] && continue
        # episode_index MUST be a non-negative integer: it drives chunk math and
        # bare arithmetic downstream. A non-integer here (corrupt line) would, if
        # admitted, crash `(( idx ... ))` under set -u. Reject it as a clean FAIL.
        if [[ ! "$idx" =~ ^[0-9]+$ ]]; then
            META_ERROR="meta/episodes.jsonl has a non-integer episode_index ('${idx}')"
            return 1
        fi
        EP_INDICES+=("$idx")
        EP_LEN[$idx]="$len"
    done < <(jq -r '[.episode_index, .length] | @tsv' "$episodes" 2>/dev/null)

    if (( ${#EP_INDICES[@]} == 0 )); then
        META_ERROR="meta/episodes.jsonl is empty or malformed"
        return 1
    fi
    return 0
}

# tasks.jsonl -> ordered task strings. Optional-tolerant: absent file yields [].
_meta_load_tasks() {
    local root="$1"
    local tasks="${root}/meta/tasks.jsonl"
    [[ -f "$tasks" ]] || return 0
    # Validate before reading: jq streams valid lines to mapfile before hitting a
    # malformed one, so without this guard a corrupt tasks.jsonl silently yields a
    # truncated-but-plausible task list and a false PASS.
    if ! jq empty "$tasks" 2>/dev/null; then
        META_ERROR="meta/tasks.jsonl contains malformed JSON"
        return 1
    fi
    mapfile -t TASK_LIST < <(jq -r '.task // empty' "$tasks" 2>/dev/null)
    return 0
}

# Version awareness (check 12): v2.0 stores global stats.json; v2.1 stores
# per-episode episodes_stats.jsonl. Resolve by version AND by which file exists.
_meta_resolve_stats_mode() {
    local root="$1"
    if [[ -f "${root}/meta/episodes_stats.jsonl" ]]; then
        META[stats_mode]="per_episode"
        META[stats_file]="${root}/meta/episodes_stats.jsonl"
    elif [[ -f "${root}/meta/stats.json" ]]; then
        META[stats_mode]="global"
        META[stats_file]="${root}/meta/stats.json"
    else
        META[stats_mode]="none"
        META[stats_file]=""
    fi
}
