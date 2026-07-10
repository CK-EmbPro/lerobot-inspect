# Claude Skill: Bash Best Practices

A Claude Code skill that ensures bash scripts follow enterprise-grade best practices for maintainability, reliability, and user-friendliness.

## Breaking change in 2.0.0

This skill now lives at `bentsolheim/public-skills` (renamed from `claude-skill-bash`; the old URL redirects). The skill itself moved into `skills/bash/`, joining sibling skills under the same umbrella repo.

Install:

```bash
# Just this skill:
npx skills add bentsolheim/public-skills -s bash

# Or all skills in the umbrella:
npx skills add bentsolheim/public-skills
```

The unscoped install (`npx skills add bentsolheim/public-skills`) now pulls every skill in the repo, not just bash. Pin with `-s bash` if you only want this one.

## Overview

This skill automatically activates when working with bash scripts to enforce consistent patterns. It recognizes two script types:

### Simple Scripts (<30 lines, no arguments)
For scripts that do one simple thing well:
- Direct execution without main function
- No argument parsing needed
- Minimal boilerplate
- Clear purpose comment

### Ordinary Scripts (larger scope)
For scripts with broader functionality:
- Main function pattern with guard clause
- Comprehensive usage documentation
- Structured argument parsing
- Dependency validation
- Organized function structure
- User-friendly colored output

Both types enforce:
- Explicit error handling (no `set -e`)
- Proper stream usage (stdout vs stderr)
- Meaningful exit codes
- Variable safety

## Features

- **Automatic Activation**: Triggers when creating or editing bash scripts
- **Comprehensive Standards**: 1000+ lines of battle-tested best practices
- **Script Generation**: Includes scaffolding tool for new scripts
- **Template System**: Reusable templates for common patterns
- **Version Controlled**: Deploy consistent standards across projects

## What a typical script looks like

Here's an "ordinary" script produced by this skill — archives log files in a directory older than N days, optionally gzipping them:

```bash
#!/usr/bin/env bash

# Script: rotate-logs.sh
# Description: Archive log files older than N days, optionally gzipping them.
# Author: Bent André Solheim
# Date: 2026-06-08

DEPENDENCIES=(find gzip)
SCRIPT_NAME=$(basename "$0")
VERSION="1.0.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [[ -n "${NO_COLOR:-}" ]] || [[ "${TERM:-}" == "dumb" ]]; then
    RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
fi

function usage() {
    cat <<EOM

Archive log files older than N days, optionally gzipping them.

usage: ${SCRIPT_NAME} -d <dir> [options]

options:
    -d|--dir       <path>     Directory to scan (required)
    -a|--age       <days>     Archive files older than this (default: 7)
    -g|--gzip                 Compress archived files with gzip
    -n|--dry-run              Show what would happen without doing it
    -v|--verbose              Enable verbose output
    -h|--help                 Show this help
    --version                 Show version

dependencies: ${DEPENDENCIES[@]}

examples:
    ${SCRIPT_NAME} -d /var/log/myapp
    ${SCRIPT_NAME} -d /var/log/myapp -a 30 -g
    ${SCRIPT_NAME} -d /var/log/myapp --dry-run -v

EOM
    exit 1
}

function main() {
    local dir=""
    local age=7
    local do_gzip=false
    local dry_run=false
    local verbose=false

    while [ "$1" != "" ]; do
        case $1 in
            -d|--dir)     shift; dir="$1" ;;
            -a|--age)     shift; age="$1" ;;
            -g|--gzip)    do_gzip=true ;;
            -n|--dry-run) dry_run=true ;;
            -v|--verbose) verbose=true ;;
            --version)    echo "${SCRIPT_NAME} ${VERSION}"; exit 0 ;;
            -h|--help)    usage ;;
            *) echo "Error: Unknown option '$1'" >&2; usage ;;
        esac
        shift
    done

    if [ -z "$dir" ]; then
        echo "Error: -d/--dir is required" >&2
        usage
    fi
    if [ ! -d "$dir" ]; then
        print_error "Directory does not exist: $dir"
        exit 1
    fi
    if ! [[ "$age" =~ ^[0-9]+$ ]]; then
        print_error "--age must be a non-negative integer (got: $age)"
        exit 1
    fi

    exit_on_missing_tools "${DEPENDENCIES[@]}"

    [ "$verbose" = true ] && print_header "Rotating logs in $dir (older than $age days)"

    archive_old_logs "$dir" "$age" "$do_gzip" "$dry_run" "$verbose"

    [ "$verbose" = true ] && print_success "Done"
}

function archive_old_logs() {
    local dir="$1"
    local age="$2"
    local do_gzip="$3"
    local dry_run="$4"
    local verbose="$5"

    local count=0
    while IFS= read -r -d '' file; do
        count=$((count + 1))
        if [ "$dry_run" = true ]; then
            echo "would archive: $file"
            continue
        fi
        [ "$verbose" = true ] && echo "archiving: $file"
        if [ "$do_gzip" = true ]; then
            gzip -f "$file" || { print_error "gzip failed: $file"; return 1; }
        fi
    done < <(find "$dir" -type f -mtime +"$age" -print0)

    [ "$verbose" = true ] && echo "Processed $count file(s)"
}

# --- Helpers ---

function exit_on_missing_tools() {
    for cmd in "$@"; do
        command -v "$cmd" &>/dev/null && continue
        printf "Error: Required tool '%s' is not installed\n" "$cmd" >&2
        exit 1
    done
}

function print_header()  { echo -e "${BLUE}== $1 ==${NC}"; }
function print_success() { echo -e "${GREEN}✅ $1${NC}"; }
function print_error()   { echo -e "${RED}❌ Error: $1${NC}" >&2; }

# Guard clause — only run main if executed directly, not when sourced
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit 0
fi
```

Run it:

```console
$ ./rotate-logs.sh --help
$ ./rotate-logs.sh -d /var/log/myapp -a 30 -g -v
== Rotating logs in /var/log/myapp (older than 30 days) ==
archiving: /var/log/myapp/access.2026-04-01.log
archiving: /var/log/myapp/access.2026-04-02.log
Processed 2 file(s)
✅ Done
```

### What this demonstrates

| Pattern | Where it appears |
|---|---|
| Shebang + four-line header comment (purpose, author, date) | top of file |
| `DEPENDENCIES`, `SCRIPT_NAME`, `VERSION` declared once at the top | global declarations |
| Colors guarded by `NO_COLOR`/`TERM=dumb` for non-terminal output | terminal-friendly defaults |
| `usage()` reads like a man page; exits 1 (use is misuse) | shown on `-h` or bad args |
| `main()` parses args, validates, then dispatches | single entry point |
| One business-logic function per concern (`archive_old_logs`) | predictable structure |
| `exit_on_missing_tools` runs before doing real work | fail fast on missing deps |
| Errors go to `stderr` (`>&2`), stdout reserved for data | safe in pipelines |
| `--dry-run` and `--verbose` are first-class flags | scriptable and inspectable |
| Guard clause `[[ "${BASH_SOURCE[0]}" == "${0}" ]]` | safe to `source` from tests |
| No `set -e` — failures handled explicitly per call | predictable, no surprise exits |

## Simple scripts

For one-shot scripts under ~30 lines with no arguments, the skill skips the `main()` ceremony:

```bash
#!/usr/bin/env bash
# Purpose: Print the line count of each file given as an argument.
# Usage: count-lines.sh <file> [<file>...]

if [ "$#" -eq 0 ]; then
    echo "Error: at least one file is required" >&2
    exit 1
fi

for f in "$@"; do
    if [ ! -f "$f" ]; then
        echo "skip: $f (not a file)" >&2
        continue
    fi
    printf "%-40s %d\n" "$f" "$(wc -l < "$f")"
done
```

Still enforced: header comment, errors to `stderr`, quoted variables, non-zero exit on misuse. Skipped: arg parser, colors, helper functions, guard clause.

If a simple script grows arguments, branching, or much past 30 lines, refactor it to the ordinary template. The decision tree for "simple vs ordinary" lives in `SKILL.md`.

## More

- Full conventions, decision tree, anti-patterns, and the scaffolding utility: see [`SKILL.md`](SKILL.md) and [`scripts/scaffold.sh`](scripts/scaffold.sh).
- Templates: [`templates/script-template.sh`](templates/script-template.sh) (ordinary), [`templates/simple-script-template.sh`](templates/simple-script-template.sh) (simple).