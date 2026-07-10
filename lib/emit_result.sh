# shellcheck shell=bash
#
# emit_result.sh — the single structured-result primitive. Every check emits exactly
# one result object; those objects are the ONE source of truth from which both
# the human report and the --json report are rendered, so the two can never
# disagree. jq builds the object, guaranteeing correct escaping of any detail
# text (episode names, file paths) without hand-rolled quoting.

# emit_result CHECK STATUS DETAIL [LOCATION]
#   CHECK    stable snake_case check id (e.g. cross_modal_consistency)
#   STATUS   ok | warn | fail
#   DETAIL   human sentence summarizing the outcome
#   LOCATION dataset-relative path the finding anchors to (optional)
emit_result() {
    jq -cn \
        --arg check "$1" \
        --arg status "$2" \
        --arg detail "$3" \
        --arg location "${4:-}" \
        '{check: $check, status: $status, detail: $detail, location: $location}'
}
