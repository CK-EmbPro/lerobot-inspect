#!/usr/bin/env bash

# Script: scaffold.sh
# Description: Generates a new bash script following best practices
# Author: Claude Skill claude-skill-bash
# Version: 1.0.0

SCRIPT_NAME=$(basename "$0")
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TEMPLATE_FILE="${SCRIPT_DIR}/../templates/script-template.sh"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

if [[ -n "${NO_COLOR:-}" ]] || [[ "${TERM:-}" == "dumb" ]]; then
    RED="" GREEN="" YELLOW="" BLUE="" NC=""
fi

function usage() {
    cat <<EOM

Generate a new bash script following best practices.

usage: ${SCRIPT_NAME} [options]

options:
    -n|--name         <name>     Script name (required)
    -d|--description  <desc>     Script description (required)
    -a|--author       <author>   Author name (optional, uses git config if available)
    -o|--output       <path>     Output path (optional, defaults to current directory)
    --dependencies    <deps>     Comma-separated list of dependencies (e.g., "jq,curl,git")
    --no-colors                  Generate script without color support
    --minimal                    Generate minimal template without utility functions
    --simple                     Generate simple script (no main function, <30 lines)
    -h|--help                    Show this help message

examples:
    ${SCRIPT_NAME} -n backup.sh -d "Backup MySQL databases"
    ${SCRIPT_NAME} --name deploy.sh --description "Deploy application" --dependencies "docker,kubectl"
    ${SCRIPT_NAME} -n process.sh -d "Process log files" -o ~/scripts/ --minimal
    ${SCRIPT_NAME} -n version.sh -d "Get git version" --simple

EOM
    exit 1
}

function main() {
    local script_name=""
    local description=""
    local author=""
    local output_path="."
    local dependencies=""
    local no_colors=false
    local minimal=false
    local simple=false

    # Parse arguments
    while [ "$1" != "" ]; do
        case $1 in
        -n | --name)
            shift
            script_name="$1"
            ;;
        -d | --description)
            shift
            description="$1"
            ;;
        -a | --author)
            shift
            author="$1"
            ;;
        -o | --output)
            shift
            output_path="$1"
            ;;
        --dependencies)
            shift
            dependencies="$1"
            ;;
        --no-colors)
            no_colors=true
            ;;
        --minimal)
            minimal=true
            ;;
        --simple)
            simple=true
            ;;
        -h | --help)
            usage
            ;;
        *)
            echo -e "${RED}Error: Unknown option '$1'${NC}" >&2
            usage
            ;;
        esac
        shift
    done

    # Validate required arguments
    if [ -z "$script_name" ]; then
        echo -e "${RED}Error: Script name is required${NC}" >&2
        usage
    fi

    if [ -z "$description" ]; then
        echo -e "${RED}Error: Script description is required${NC}" >&2
        usage
    fi

    # Set defaults
    if [ -z "$author" ]; then
        author=$(git config user.name 2>/dev/null || echo "$(whoami)")
    fi

    # Ensure script name has .sh extension
    if [[ ! "$script_name" =~ \.sh$ ]]; then
        script_name="${script_name}.sh"
    fi

    # Select appropriate template
    if [ "$simple" = true ]; then
        TEMPLATE_FILE="${SCRIPT_DIR}/../templates/simple-script-template.sh"
    fi

    # Check if template exists
    if [ ! -f "$TEMPLATE_FILE" ]; then
        echo -e "${RED}Error: Template file not found: ${TEMPLATE_FILE}${NC}" >&2
        exit 1
    fi

    # Create output directory if needed
    if [ ! -d "$output_path" ]; then
        echo -e "${YELLOW}Creating directory: ${output_path}${NC}"
        mkdir -p "$output_path" || {
            echo -e "${RED}Error: Failed to create output directory${NC}" >&2
            exit 1
        }
    fi

    local output_file="${output_path}/${script_name}"

    # Check if file already exists
    if [ -f "$output_file" ]; then
        echo -e "${YELLOW}Warning: File already exists: ${output_file}${NC}"
        read -p "Overwrite? (y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Operation cancelled"
            exit 0
        fi
    fi

    # Generate the script
    generate_script "$script_name" "$description" "$author" "$dependencies" "$no_colors" "$minimal" "$simple" > "$output_file"

    # Make executable
    chmod +x "$output_file"

    echo -e "${GREEN}✅ Script generated successfully: ${output_file}${NC}"
    echo
    echo "Next steps:"
    if [ "$simple" = true ]; then
        echo "1. Edit the script to add your logic"
        echo "2. Test with: bash -n ${output_file}"
        echo "3. Run with: ${output_file}"
    else
        echo "1. Edit the script to add your business logic"
        echo "2. Update the DEPENDENCIES array if needed"
        echo "3. Customize the argument parsing for your needs"
        echo "4. Test with: bash -n ${output_file}"
        echo "5. Run with: ${output_file} --help"
    fi
}

function generate_script() {
    local name="$1"
    local desc="$2"
    local author="$3"
    local deps="$4"
    local no_colors="$5"
    local minimal="$6"
    local simple="$7"

    # Read template
    local template=$(cat "$TEMPLATE_FILE")

    # Replace placeholders
    template="${template//\{\{SCRIPT_NAME\}\}/$name}"
    template="${template//\{\{DESCRIPTION\}\}/$desc}"
    template="${template//\{\{AUTHOR\}\}/$author}"
    template="${template//\{\{DATE\}\}/$(date +%Y-%m-%d)}"

    # For simple scripts, add output description placeholder
    if [ "$simple" = true ]; then
        template="${template//\{\{OUTPUT_DESCRIPTION\}\}/Result or data to stdout}"
    fi

    # Handle dependencies
    if [ -n "$deps" ]; then
        # Convert comma-separated to space-separated array format
        deps_array=$(echo "$deps" | sed 's/,/ /g')
        template=$(echo "$template" | sed "s/DEPENDENCIES=()/DEPENDENCIES=($deps_array)/")
    fi

    # Remove color support if requested (not for simple scripts)
    if [ "$no_colors" = true ] && [ "$simple" != true ]; then
        # Remove color definition block
        template=$(echo "$template" | sed '/^# Color definitions/,/^fi$/d')
        # Remove color codes from print functions
        template=$(echo "$template" | sed 's/\${[A-Z]*}//g; s/\${NC}//g')
        template=$(echo "$template" | sed 's/\\033\[[0-9;]*m//g')
    fi

    # Generate minimal version if requested (not for simple scripts)
    if [ "$minimal" = true ] && [ "$simple" != true ]; then
        # Remove utility functions except exit_on_missing_tools
        template=$(echo "$template" | sed '/^function print_/,/^}$/d')
        # Remove verbose handling
        template=$(echo "$template" | sed '/-v | --verbose/,+2d')
        template=$(echo "$template" | sed '/verbose=/d')
        template=$(echo "$template" | sed '/if \[ "$verbose"/,/fi$/d')
    fi

    echo "$template"
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

# Guard clause
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
    exit 0
fi