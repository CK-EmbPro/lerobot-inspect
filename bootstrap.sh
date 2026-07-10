#!/usr/bin/env bash
#
# bootstrap.sh — provision every dependency lerobot-inspect needs, on a fresh
# machine, with one command. Portable across apt / dnf / pacman / brew; the
# non-packaged duckdb CLI is fetched as a static binary into ~/.local/bin.
#
# System packages use sudo (or run as root); duckdb never needs it. Idempotent:
# anything already present is left alone. It also makes the project scripts
# executable and verifies that datasets are present to inspect — if none are
# found, bootstrap does not report ready. Use --check to report status without
# installing.
set -euo pipefail

SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
readonly SCRIPT_NAME SCRIPT_DIR
readonly VERSION="1.0.0"

# The project's runnable scripts — bootstrap ensures each is executable, since
# the +x bit can be lost on zip downloads or cross-filesystem copies. Sourced
# files (lib/*.sh, conf/*) are NOT executed, so they intentionally stay here.
readonly PROJECT_EXECUTABLES=(
    lerobot-inspect
    bootstrap.sh
    tests/run-tests.sh
    .claude/hooks/shellcheck-hook.sh
)
readonly BIN_DIR="${HOME}/.local/bin"
# Pinned for reproducibility; override with DUCKDB_VERSION=x.y.z ./bootstrap.sh
readonly DUCKDB_VERSION="${DUCKDB_VERSION:-1.5.4}"

# The tool has nothing to run on without data. bootstrap verifies that at least
# one dataset (a folder containing meta/info.json) exists here; if not, it does
# NOT report ready. Override the location with LEROBOT_INSPECT_DATASETS_DIR.
readonly DATASETS_DIR="${LEROBOT_INSPECT_DATASETS_DIR:-${SCRIPT_DIR}/datasets}"

RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'
if [[ ! -t 1 || -n "${NO_COLOR:-}" ]]; then RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""; fi

CHECK_ONLY=false
MGR=""
APT_UPDATED=false
MISSING=0

usage() {
    cat <<EOF

${SCRIPT_NAME} ${VERSION} — install the tools lerobot-inspect depends on.

usage: ${SCRIPT_NAME} [--check] [-h|--help] [--version]

    --check      Report what is installed / missing and what WOULD be done,
                 without installing anything. Exits non-zero if anything missing.
    -h, --help   Show this help.
    --version    Show version.

Installs: jq, ffmpeg (ffprobe), shellcheck, unzip via the system package manager
(apt/dnf/pacman/brew, using sudo), and the duckdb CLI as a static binary into
${BIN_DIR}. Verifies the coreutils (awk, du, find), makes the project scripts
executable, and checks that at least one dataset is present under
${DATASETS_DIR#"${SCRIPT_DIR}/"}/ (bootstrap does not report ready without data).

EOF
}

main() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --check)    CHECK_ONLY=true ;;
            --version)  printf '%s %s\n' "$SCRIPT_NAME" "$VERSION"; exit 0 ;;
            -h|--help)  usage; exit 0 ;;
            *)          err "unknown option: $1 (see --help)"; exit 2 ;;
        esac
        shift
    done

    MGR=$(detect_pkg_manager)
    header "lerobot-inspect bootstrap ($([[ "$CHECK_ONLY" == true ]] && echo 'check only' || echo 'install'))"
    info "package manager: ${MGR}"

    # Package-provided tools: command name + logical package name.
    ensure_pkg_tool jq         jq         || true
    ensure_pkg_tool ffprobe    ffmpeg     || true
    ensure_pkg_tool shellcheck shellcheck || true
    ensure_pkg_tool unzip      unzip      || true

    ensure_duckdb || true

    # Coreutils are effectively always present; verify rather than install.
    local c
    for c in awk du find; do verify_present "$c"; done

    # Make the project's own scripts executable.
    local s
    for s in "${PROJECT_EXECUTABLES[@]}"; do
        ensure_executable "$s" || true
    done

    # The tool needs data — verify at least one dataset is present to inspect.
    check_datasets || true

    check_path_hint
    summarize
}

detect_pkg_manager() {
    if   command -v apt-get >/dev/null 2>&1; then echo apt
    elif command -v dnf     >/dev/null 2>&1; then echo dnf
    elif command -v pacman  >/dev/null 2>&1; then echo pacman
    elif command -v brew    >/dev/null 2>&1; then echo brew
    else echo none
    fi
}

# ensure_pkg_tool CMD LOGICAL_PKG — install CMD's package if CMD is absent.
ensure_pkg_tool() {
    local cmd="$1" logical="$2"
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "${cmd} present ($(command -v "$cmd"))"
        return 0
    fi
    MISSING=$(( MISSING + 1 ))
    if [[ "$CHECK_ONLY" == true ]]; then
        miss "${cmd} MISSING — would install '$(pkg_name "$logical")' via ${MGR}"
        return 1
    fi
    if [[ "$MGR" == none ]]; then
        err "${cmd} missing and no supported package manager found — install it manually"
        return 1
    fi
    info "installing ${cmd} ..."
    if pkg_install "$(pkg_name "$logical")" && command -v "$cmd" >/dev/null 2>&1; then
        MISSING=$(( MISSING - 1 ))
        ok "${cmd} installed"
    else
        err "failed to install ${cmd}"
        return 1
    fi
}

# pkg_name LOGICAL — map a logical package to this manager's actual package name.
pkg_name() {
    case "$1" in
        shellcheck) [[ "$MGR" == dnf ]] && echo ShellCheck || echo shellcheck ;;
        *)          echo "$1" ;;
    esac
}

# pkg_install PKG... — install packages with the detected manager.
pkg_install() {
    case "$MGR" in
        apt)    apt_update_once; run_priv apt-get install -y "$@" ;;
        dnf)    run_priv dnf install -y "$@" ;;
        pacman) run_priv pacman -S --noconfirm "$@" ;;
        brew)   brew install "$@" ;;
        *)      return 1 ;;
    esac
}

apt_update_once() {
    if [[ "$APT_UPDATED" == false ]]; then
        run_priv apt-get update -qq
        APT_UPDATED=true
    fi
}

# run_priv CMD... — run as root directly, else via sudo; fail clearly if neither.
run_priv() {
    if [[ "$(id -u)" -eq 0 ]]; then
        "$@"
    elif command -v sudo >/dev/null 2>&1; then
        sudo "$@"
    else
        err "need root or sudo to run: $*"
        return 1
    fi
}

ensure_duckdb() {
    if command -v duckdb >/dev/null 2>&1; then
        ok "duckdb present ($(command -v duckdb))"
        return 0
    fi
    MISSING=$(( MISSING + 1 ))
    if [[ "$CHECK_ONLY" == true ]]; then
        miss "duckdb MISSING — would download v${DUCKDB_VERSION} to ${BIN_DIR}"
        return 1
    fi
    if install_duckdb; then
        MISSING=$(( MISSING - 1 ))
    else
        return 1
    fi
}

install_duckdb() {
    local os arch asset url tmp
    os=$(uname -s); arch=$(uname -m)
    case "$os" in
        Linux)
            case "$arch" in
                x86_64|amd64)  asset="duckdb_cli-linux-amd64.zip" ;;
                aarch64|arm64) asset="duckdb_cli-linux-arm64.zip" ;;
                *) err "unsupported architecture: ${arch}"; return 1 ;;
            esac ;;
        Darwin) asset="duckdb_cli-osx-universal.zip" ;;
        *) err "unsupported OS: ${os} — install duckdb manually from duckdb.org"; return 1 ;;
    esac
    url="https://github.com/duckdb/duckdb/releases/download/v${DUCKDB_VERSION}/${asset}"

    mkdir -p "$BIN_DIR"
    tmp=$(mktemp -d)
    # shellcheck disable=SC2064  # expand tmp now so cleanup targets this dir
    trap "rm -rf '${tmp}'" RETURN

    info "downloading duckdb ${DUCKDB_VERSION} (${asset}) ..."
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "${tmp}/duckdb.zip" "$url" || { err "download failed: ${url}"; return 1; }
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "${tmp}/duckdb.zip" "$url" || { err "download failed: ${url}"; return 1; }
    else
        err "need curl or wget to download duckdb"
        return 1
    fi

    unzip -oq "${tmp}/duckdb.zip" -d "$tmp" || { err "failed to unzip duckdb archive"; return 1; }
    install -m755 "${tmp}/duckdb" "${BIN_DIR}/duckdb" || { err "failed to install duckdb to ${BIN_DIR}"; return 1; }
    ok "duckdb ${DUCKDB_VERSION} installed to ${BIN_DIR}/duckdb"
}

# ensure_executable REL_PATH — make a project script executable (chmod +x),
# relative to the bootstrap script's own directory. Absent files are skipped.
ensure_executable() {
    local rel="$1" path="${SCRIPT_DIR}/${1}"
    [[ -e "$path" ]] || return 0
    if [[ -x "$path" ]]; then
        ok "${rel} is executable"
        return 0
    fi
    MISSING=$(( MISSING + 1 ))
    if [[ "$CHECK_ONLY" == true ]]; then
        miss "${rel} not executable — would chmod +x"
        return 1
    fi
    if chmod +x "$path"; then
        MISSING=$(( MISSING - 1 ))
        ok "${rel} made executable"
    else
        err "failed to chmod +x ${rel}"
        return 1
    fi
}

# check_datasets — verify at least one inspectable dataset (a directory with
# meta/info.json) exists under DATASETS_DIR. bootstrap cannot install data, so a
# miss is reported (and fails the run) with guidance rather than fixed.
check_datasets() {
    local n=0
    [[ -d "$DATASETS_DIR" ]] && n=$(find "$DATASETS_DIR" -type f -path '*/meta/info.json' 2>/dev/null | wc -l)

    # Friendly location: "./datasets/ in the root folder of this project" for the
    # default (a path inside SCRIPT_DIR), or the given path for an override.
    local where
    if [[ "$DATASETS_DIR" == "${SCRIPT_DIR}/"* ]]; then
        where="./${DATASETS_DIR#"${SCRIPT_DIR}/"}/ in the root folder of this project"
    else
        where="${DATASETS_DIR}/"
    fi

    if (( n > 0 )); then
        ok "datasets present — ${n} dataset(s) under ${where}"
        return 0
    fi
    MISSING=$(( MISSING + 1 ))
    err "no datasets found under ${where}"
    err "  place your LeRobot datasets there — each a folder containing meta/info.json."
    err "  the tool has nothing to inspect until they exist (see README, 'Getting the data')."
    return 1
}

# verify_present CMD — coreutils check (never auto-installed).
verify_present() {
    if command -v "$1" >/dev/null 2>&1; then
        ok "$1 present"
    else
        MISSING=$(( MISSING + 1 ))
        err "$1 missing — install coreutils/findutils/gawk for your system"
    fi
}

check_path_hint() {
    case ":${PATH}:" in
        *":${BIN_DIR}:"*) : ;;
        *) warn "${BIN_DIR} is not on your PATH — add it so duckdb is found:"
           # shellcheck disable=SC2016  # literal command for the user to copy, not for us to expand
           printf '      echo '\''export PATH="$HOME/.local/bin:$PATH"'\'' >> ~/.bashrc && source ~/.bashrc\n' ;;
    esac
}

summarize() {
    echo
    if (( MISSING == 0 )); then
        printf '%s✔ ready.%s Dependencies installed and datasets present. Run: ./lerobot-inspect ./datasets\n' "$GREEN" "$NC"
        exit 0
    fi
    if [[ "$CHECK_ONLY" == true ]]; then
        printf '%s! %d item(s) need attention.%s Run ./%s (without --check) to fix installable ones.\n' \
            "$YELLOW" "$MISSING" "$NC" "$SCRIPT_NAME"
    else
        printf '%s✗ %d item(s) still missing (deps and/or datasets).%s See messages above.\n' \
            "$RED" "$MISSING" "$NC"
    fi
    exit 1
}

header() { printf '%s== %s ==%s\n' "$BLUE" "$1" "$NC"; }
info()   { printf '%s[..]%s %s\n'  "$BLUE"   "$NC" "$*"; }
ok()     { printf '%s[ok]%s %s\n'  "$GREEN"  "$NC" "$*"; }
miss()   { printf '%s[--]%s %s\n'  "$YELLOW" "$NC" "$*"; }
warn()   { printf '%s[!!]%s %s\n'  "$YELLOW" "$NC" "$*" >&2; }
err()    { printf '%s[XX]%s %s\n'  "$RED"    "$NC" "$*" >&2; }

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
