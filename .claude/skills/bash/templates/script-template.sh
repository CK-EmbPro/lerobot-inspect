#!/usr/bin/env bash

# Script: {{SCRIPT_NAME}}
# Description: {{DESCRIPTION}}
# Author: {{AUTHOR}}
# Date: {{DATE}}

# Global declarations
DEPENDENCIES=()  # Add required external tools: (jq curl git)
SCRIPT_NAME=$(basename "$0")
VERSION="1.0.0"

# Color definitions for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Allow users to disable colors via environment variable
if [[ -n "${NO_COLOR:-}" ]] || [[ "${TERM:-}" == "dumb" ]]; then
    RED=""
    GREEN=""
    YELLOW=""
    BLUE=""
    NC=""
fi

function usage() {
    cat <<EOM

{{DESCRIPTION}}

usage: ${SCRIPT_NAME} [options]

options:
    -i|--input        <file>     Input file to process (required)
    -o|--output       <file>     Output file (optional, defaults to stdout)
    -v|--verbose                 Enable verbose output
    -h|--help                    Show this help message
    --version                    Show version information

dependencies: ${DEPENDENCIES[@]}

examples:
    ${SCRIPT_NAME} -i data.txt -o result.txt
    ${SCRIPT_NAME} --input data.txt --verbose
    cat data.txt | ${SCRIPT_NAME} -o result.txt

EOM
    exit 1
}

function main() {
    # Default values
    local input_file=""
    local output_file=""
    local verbose=false

    # Parse arguments
    while [ "$1" != "" ]; do
        case $1 in
        -i | --input)
            shift
            input_file="$1"
            ;;
        -o | --output)
            shift
            output_file="$1"
            ;;
        -v | --verbose)
            verbose=true
            ;;
        --version)
            echo "${SCRIPT_NAME} version ${VERSION}"
            exit 0
            ;;
        -h | --help)
            usage
            ;;
        *)
            echo "Error: Unknown option '$1'" >&2
            usage
            ;;
        esac
        shift
    done

    # Validate required arguments
    if [ -z "$input_file" ] && [ -t 0 ]; then
        echo "Error: Input file is required when not piping data" >&2
        usage
    fi

    # Check dependencies
    exit_on_missing_tools "${DEPENDENCIES[@]}"

    # Main script logic
    if [ "$verbose" = true ]; then
        print_header "Starting ${SCRIPT_NAME}"
    fi

    process_data "$input_file" "$output_file" "$verbose"

    if [ "$verbose" = true ]; then
        print_success "Operation completed successfully"
    fi
}

# Business logic functions
function process_data() {
    local input_file="$1"
    local output_file="$2"
    local verbose="$3"

    # TODO: Implement main processing logic here
    if [ "$verbose" = true ]; then
        print_step 1 3 "Reading input data..."
    fi

    # Read from file or stdin
    local data
    if [ -n "$input_file" ]; then
        if [ ! -f "$input_file" ]; then
            print_error "Input file not found: $input_file"
            exit 1
        fi
        data=$(cat "$input_file")
    else
        data=$(cat)
    fi

    if [ "$verbose" = true ]; then
        print_step 2 3 "Processing data..."
    fi

    # TODO: Add actual processing logic
    local result="$data"

    if [ "$verbose" = true ]; then
        print_step 3 3 "Writing output..."
    fi

    # Write to file or stdout
    if [ -n "$output_file" ]; then
        echo "$result" > "$output_file"
        if [ "$verbose" = true ]; then
            print_success "Output written to: $output_file"
        fi
    else
        echo "$result"
    fi
}

# Utility functions
function exit_on_missing_tools() {
    for cmd in "$@"; do
        if command -v "$cmd" &>/dev/null; then
            continue
        fi
        printf "Error: Required tool '%s' is not installed or not in PATH\n" "$cmd" >&2
        exit 1
    done
}

function print_header() {
    local title="$1"
    echo -e "${BLUE}==================================================${NC}"
    echo -e "${BLUE}${title}${NC}"
    echo -e "${BLUE}==================================================${NC}"
    echo
}

function print_step() {
    local step_num="$1"
    local total_steps="$2"
    local message="$3"
    echo -e "${YELLOW}[${step_num}/${total_steps}] ${message}${NC}"
}

function print_success() {
    local message="$1"
    echo -e "${GREEN}✅ ${message}${NC}"
}

function print_error() {
    local message="$1"
    echo -e "${RED}❌ Error: ${message}${NC}" >&2
}

function print_warning() {
    local message="$1"
    echo -e "${YELLOW}⚠️  Warning: ${message}${NC}"
}

# Guard clause - only execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit 0
fi