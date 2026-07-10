#!/usr/bin/env bash
# PostToolUse hook: enforce verb-first, action-oriented names for lib/ modules.
# A developer should understand a file's job from its name alone, so lib/<name>.sh
# must lead with an action verb (read_, build_, check_, render_, probe_, ...), not
# a bare domain noun (video.sh, parquet.sh, batch.sh, statistics.sh). core.sh is
# the sole exception (shared primitives with no single verb).
#
# Input : Claude Code passes the tool-call payload as JSON on stdin.
# Output: guidance to stderr; exit 2 => fed back to Claude to rename.

read -r payload

if command -v jq >/dev/null 2>&1; then
    file=$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty')
else
    file=$(printf '%s' "$payload" | grep -o '"file_path"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*:[[:space:]]*"//; s/"$//')
fi

[ -z "$file" ] && exit 0

# Only govern shell modules that live under a lib/ directory.
case "$file" in
    */lib/*.sh | lib/*.sh) ;;
    *) exit 0 ;;
esac

base=$(basename "$file" .sh)

# Sole allowed non-verb module: shared primitives.
[ "$base" = "core" ] && exit 0

# Approved action-verb prefixes. Extend this list if a new verb is legitimate.
verbs="verify read write probe emit build inspect discover run flag render parse \
load save persist assemble compute check report resolve validate collect fetch \
format count detect compare merge list get make print extract scan apply generate \
summarize describe find filter map transform clean convert encode decode download \
upload install setup init open close start stop"

first=${base%%_*}

# Whole-word membership test (spaces around both sides).
if [[ " ${verbs//$'\n'/ } " == *" ${first} "* ]]; then
    exit 0
fi

{
    echo "Naming convention: lib module '${base}.sh' must lead with an ACTION VERB"
    echo "(verb-first, e.g. read_parquet.sh, build_statistics.sh, check_files.sh,"
    echo "render_human.sh) so a developer understands its job from the name alone —"
    echo "not a bare domain noun like video.sh / parquet.sh / batch.sh."
    echo
    echo "'${first}' is not a recognized action verb. Rename the file to say what it DOES."
    echo "Only core.sh is exempt. If '${first}' is a legitimate new verb, add it to"
    echo ".claude/hooks/naming-convention-hook.sh."
} >&2
exit 2
