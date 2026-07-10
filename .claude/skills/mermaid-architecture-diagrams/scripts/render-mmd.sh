#!/usr/bin/env bash

# Global declarations
SCRIPT_NAME=$(basename "$0")
VERSION="1.0.0"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'
if [[ -n "${NO_COLOR:-}" ]] || [[ "${TERM:-}" == "dumb" ]]; then
    RED="" GREEN="" YELLOW="" NC=""
fi

function usage() {
    cat <<EOM

Renders a Mermaid .mmd file to PNG plus an inspection preview (max 1200px),
using the pipeline that matches your destination document.

usage: ${SCRIPT_NAME} [options] <diagram.mmd> [output.png]

options:
    -p|--pipeline <auto|quarto|mmdc>   Render pipeline (default: auto — quarto
                                       if installed, else mmdc). Use the pipeline
                                       that will render the diagram in production.
    -w|--width    <px>                 mmdc page width (default 1600; quarto path
                                       uses fig-width 9 and renders ~2960px)
    -h|--help                          Show this help message
    --version                          Show version information

dependencies: quarto OR @mermaid-js/mermaid-cli (mmdc); one of sips/magick/python3
for the preview downscale.

examples:
    ${SCRIPT_NAME} system-sketch.mmd
    ${SCRIPT_NAME} -p mmdc pipeline.mmd out/pipeline.png

EOM
    exit 1
}

function main() {
    local pipeline="auto"
    local width=1600
    local input=""
    local output=""

    while [ "$1" != "" ]; do
        case $1 in
        -p | --pipeline)
            shift; pipeline="$1" ;;
        -w | --width)
            shift; width="$1" ;;
        --version)
            echo "${SCRIPT_NAME} version ${VERSION}"; exit 0 ;;
        -h | --help)
            usage ;;
        *)
            if [ -z "$input" ]; then input="$1"
            elif [ -z "$output" ]; then output="$1"
            else echo "Error: Unknown argument '$1'" >&2; usage; fi ;;
        esac
        shift
    done

    if [ -z "$input" ] || [ ! -f "$input" ]; then
        echo "Error: input .mmd file required" >&2
        usage
    fi
    [ -z "$output" ] && output="${input%.mmd}.png"

    if [ "$pipeline" = "auto" ]; then
        if command -v quarto &>/dev/null; then pipeline="quarto"
        elif command -v mmdc &>/dev/null || command -v npx &>/dev/null; then pipeline="mmdc"
        else
            echo "Error: neither quarto nor mmdc/npx found" >&2
            exit 1
        fi
        echo -e "${YELLOW}pipeline: ${pipeline} (auto)${NC}"
    fi

    case $pipeline in
    quarto) render_quarto "$input" "$output" || exit 1 ;;
    mmdc)   render_mmdc "$input" "$output" "$width" || exit 1 ;;
    *)      echo "Error: unknown pipeline '$pipeline'" >&2; usage ;;
    esac

    make_preview "$output"
    echo -e "${GREEN}OK: ${output} (+ preview)${NC}"
}

function render_quarto() {
    local input="$1" output="$2"
    local workdir
    workdir="$(mktemp -d)"
    {
        printf -- '---\nformat:\n  gfm:\n    mermaid-format: png\n---\n\n```{mermaid}\n%%%%| fig-width: 9\n'
        cat "$input"
        printf '\n```\n'
    } > "$workdir/d.qmd"

    if ! quarto render "$workdir/d.qmd" --to gfm >"$workdir/render.log" 2>&1; then
        echo -e "${RED}quarto render failed:${NC}" >&2
        tail -15 "$workdir/render.log" >&2
        rm -rf "$workdir"
        return 1
    fi
    local png="$workdir/d_files/figure-commonmark/mermaid-figure-1.png"
    if [ ! -f "$png" ]; then
        echo -e "${RED}quarto produced no png${NC}" >&2
        rm -rf "$workdir"
        return 1
    fi
    cp "$png" "$output"
    rm -rf "$workdir"
}

function render_mmdc() {
    local input="$1" output="$2" width="$3"
    local mmdc_cmd="mmdc"
    command -v mmdc &>/dev/null || mmdc_cmd="npx -y @mermaid-js/mermaid-cli"

    local cfg_args=()
    local errlog
    errlog="$(mktemp)"
    if ! $mmdc_cmd -i "$input" -o "$output" -w "$width" -s 2 -b white >"$errlog" 2>&1; then
        if grep -q "Could not find Chrome" "$errlog"; then
            local chrome
            chrome="$(find_chrome)"
            if [ -n "$chrome" ]; then
                echo -e "${YELLOW}puppeteer lacks its pinned Chrome — using system Chrome${NC}"
                local cfg
                cfg="$(mktemp -t puppeteer-config).json"
                printf '{ "executablePath": "%s" }\n' "$chrome" > "$cfg"
                cfg_args=(-p "$cfg")
                if ! $mmdc_cmd "${cfg_args[@]}" -i "$input" -o "$output" -w "$width" -s 2 -b white >"$errlog" 2>&1; then
                    echo -e "${RED}mmdc failed even with system Chrome:${NC}" >&2
                    grep -v "^\s*at " "$errlog" | tail -8 >&2
                    rm -f "$errlog"
                    return 1
                fi
            else
                echo -e "${RED}mmdc cannot find Chrome. Install one:${NC}" >&2
                echo "  npx puppeteer browsers install chrome-headless-shell" >&2
                rm -f "$errlog"
                return 1
            fi
        else
            echo -e "${RED}mmdc failed:${NC}" >&2
            grep -v "^\s*at " "$errlog" | tail -8 >&2
            rm -f "$errlog"
            return 1
        fi
    fi
    rm -f "$errlog"
}

function find_chrome() {
    local candidates=(
        "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
        "/Applications/Chromium.app/Contents/MacOS/Chromium"
        "/usr/bin/google-chrome"
        "/usr/bin/google-chrome-stable"
        "/usr/bin/chromium"
        "/usr/bin/chromium-browser"
    )
    for c in "${candidates[@]}"; do
        if [ -x "$c" ]; then echo "$c"; return 0; fi
    done
    return 1
}

function make_preview() {
    local png="$1"
    local preview="${png%.png}-preview.png"
    if command -v sips &>/dev/null; then
        sips -Z 1200 "$png" --out "$preview" >/dev/null 2>&1 && return 0
    fi
    if command -v magick &>/dev/null; then
        magick "$png" -resize '1200x1200>' "$preview" >/dev/null 2>&1 && return 0
    fi
    if command -v python3 &>/dev/null; then
        python3 - "$png" "$preview" <<'PYEOF' 2>/dev/null && return 0
import sys
from PIL import Image
img = Image.open(sys.argv[1])
img.thumbnail((1200, 1200))
img.save(sys.argv[2])
PYEOF
    fi
    echo "Warning: no downscale tool (sips/magick/PIL) — preview not created; inspect the full PNG" >&2
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit 0
fi
