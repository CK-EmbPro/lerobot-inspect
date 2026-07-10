# Bash / Linux Quick-Reference Patterns

Essential day-to-day Bash patterns for Linux/macOS. Companion to
[`../SKILL.md`](../SKILL.md) — that file governs *how to structure scripts*; this
one is a fast lookup for common commands and idioms.

## 1. Operators — chaining commands

| Operator | Meaning | Example |
|----------|---------|---------|
| `;` | Run sequentially | `cmd1; cmd2` |
| `&&` | Run if previous succeeded | `make && make install` |
| `\|\|` | Run if previous failed | `test cmd \|\| echo "failed"` |
| `\|` | Pipe output | `ls \| grep '.sh'` |

## 2. File operations

| Task | Command |
|------|---------|
| List all | `ls -la` |
| Find files | `find . -name '*.sh' -type f` |
| File content | `cat file.txt` |
| First N lines | `head -n 20 file.txt` |
| Last N lines | `tail -n 20 file.txt` |
| Follow log | `tail -f log.txt` |
| Search in files | `grep -r "pattern" --include='*.sh'` |
| File size | `du -sh *` |
| Disk usage | `df -h` |

## 3. Process management

| Task | Command |
|------|---------|
| List processes | `ps aux` |
| Find by name | `ps aux \| grep node` |
| Kill by PID | `kill -9 <PID>` |
| Find port user | `lsof -i :3000` |
| Kill port | `kill -9 "$(lsof -t -i :3000)"` |
| Background | `long-task &` |
| Jobs | `jobs -l` |
| Bring to front | `fg %1` |

## 4. Text processing

| Tool | Purpose | Example |
|------|---------|---------|
| `grep` | Search | `grep -rn "TODO" src/` |
| `sed` | Replace | `sed 's/old/new/g' file.txt` |
| `awk` | Extract columns / float math | `awk '{print $1}' file.txt` |
| `cut` | Cut fields | `cut -d',' -f1 data.csv` |
| `sort` | Sort lines | `sort -u file.txt` |
| `uniq` | Unique lines | `sort file.txt \| uniq -c` |
| `wc` | Count | `wc -l file.txt` |

> Note: `awk` is the go-to for **floating-point math** in Bash (Bash integers
> only) — central to the `lerobot-inspector` duration/fps/tolerance checks.

## 5. Environment variables

| Task | Command |
|------|---------|
| View all | `env` / `printenv` |
| View one | `echo "$PATH"` |
| Set temporary | `export VAR="value"` |
| Set for one command | `VAR="value" command` |
| Add to PATH | `export PATH="$PATH:/new/path"` |

## 6. Network

| Task | Command |
|------|---------|
| Download | `curl -O https://example.com/file` |
| GET request | `curl -X GET https://api.example.com` |
| POST JSON | `curl -X POST -H "Content-Type: application/json" -d '{"k":"v"}' URL` |
| Check port | `nc -zv localhost 3000` |
| Network info | `ip addr` (`ifconfig` on older systems) |

## 7. Common patterns

```bash
# Check if a command exists (dependency check)
if command -v jq &>/dev/null; then
    echo "jq is installed"
fi

# Default value for a positional arg
name=${1:-"default_value"}

# Read a file line by line
while IFS= read -r line; do
    echo "$line"
done < file.txt

# Loop over files safely
for file in *.sh; do
    [ -e "$file" ] || continue   # handle no-match glob
    echo "Processing $file"
done
```

## 8. Error handling & cleanup

```bash
set -euo pipefail   # exit on error, undefined var, and pipe failure
set -x              # debug: print each command as it runs

# Trap for cleanup on exit (temp files, etc.)
cleanup() {
    rm -f "$tmpfile"
}
trap cleanup EXIT
```

> `set -euo pipefail` is what the **LeRobot Dataset Inspector brief mandates**.
> The `../SKILL.md` best-practices doc otherwise prefers explicit error handling
> over bare `set -e`; for that project, follow the brief and use
> `set -euo pipefail`, layering explicit checks on top for precise messages.

## 9. Bash vs PowerShell (quick map)

| Task | PowerShell | Bash |
|------|------------|------|
| List files | `Get-ChildItem` | `ls -la` |
| Find files | `Get-ChildItem -Recurse` | `find . -type f` |
| Environment var | `$env:VAR` | `$VAR` |
| String concat | `"$a$b"` | `"$a$b"` |
| Null/empty check | `if ($x)` | `if [ -n "$x" ]` |
| Pipeline | object-based | text-based |
