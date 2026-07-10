#!/usr/bin/env bash
# PostToolUse hook: after Claude writes/edits a shell script, run shellcheck.
# The brief requires the tool to be shellcheck-clean at zero warnings, so we
# surface findings back to Claude (exit 2) instead of letting them slip through.
#
# Input : Claude Code passes the tool-call payload as JSON on stdin.
# Output: findings to stderr; exit 2 => fed back to Claude to fix.

read -r payload

# Extract the edited file path (prefer jq; fall back to a grep/sed parse).
if command -v jq >/dev/null 2>&1; then
    file=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')
else
    file=$(printf '%s' "$payload" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//')
fi

[ -z "$file" ] && exit 0
[ -f "$file" ] || exit 0

# Only act on shell scripts: .sh/.bash extension, or a bash/sh shebang.
case "$file" in
    *.sh | *.bash) is_shell=1 ;;
    *) is_shell=0 ;;
esac
if [ "$is_shell" -eq 0 ] && head -1 "$file" 2>/dev/null | grep -qE '^#!.*(bash|/sh)'; then
    is_shell=1
fi
[ "$is_shell" -eq 1 ] || exit 0

if ! command -v shellcheck >/dev/null 2>&1; then
    echo "shellcheck not installed — skipping lint on ${file}. Install it to enforce zero-warning shell scripts (apt install shellcheck)." >&2
    exit 0
fi

if ! output=$(shellcheck "$file" 2>&1); then
    {
        echo "shellcheck found issues in ${file} — the project requires shellcheck-clean scripts at zero warnings. Fix these:"
        echo "$output"
    } >&2
    exit 2
fi

exit 0
