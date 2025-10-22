#!/usr/bin/env bash

set -euo pipefail

# ==============================================================================
# Docker Compose Initializer & .env Generator
# Version: V1.0.1-stable
# ==============================================================================
# This script automates the initial setup for Docker Compose projects.
# It fetches a docker-compose.yaml file, intelligently scans it for environment
# variables, and generates a ready-to-use .env file with proper security.
# ==============================================================================

readonly VERSION="1.0.1"
readonly COMPOSE_FILE="docker-compose.yaml"

# Global options
PULL_LATEST=false
FORCE_YES=false
ENV_OUTPUT=".env"

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m'

# Print functions
err()  { echo -e "${RED}[✗]${NC} $*" >&2; }
ok()   { echo -e "${GREEN}[✓]${NC} $*"; }
info() { echo -e "${BLUE}[ℹ]${NC} $*"; }
warn() { echo -e "${YELLOW}[!]${NC} $*"; }

die() { 
    err "$1"
    exit "${2:-1}"
}

# utility: newline
newline() { printf "\n"; }

check_dependencies() {
    local missing=()
    for cmd in curl docker grep sed sort; do
        if ! command -v "$cmd" &>/dev/null; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        die "Missing required commands: ${missing[*]}" 127
    fi
}

# Download or copy file
get_file() {
    local src="$1"
    local dest="$2"
    
    if [[ "$src" =~ ^https?:// ]]; then
        info "Downloading from: $src"
        if ! curl -fsSL --retry 2 --max-time 30 "$src" -o "$dest"; then
            die "Download failed: $src" 69
        fi
    else
        if [[ ! -f "$src" ]]; then
            die "File not found: $src" 65
        fi
        cp "$src" "$dest"
    fi
    
    ok "File ready: $dest"
}

# Extract environment variables from YAML
extract_vars() {
    local yaml_file="$1"
    local env_file="$2"
    
    info "Extracting environment variables from $yaml_file..."
    
    # Create temp file
    local temp_env
    temp_env=$(mktemp)
    
    # Extract ${VAR} and ${VAR:-default} patterns
    if grep -oE '\$\{[A-Za-z_][A-Za-z0-9_]*(:-[^}]*)?\}' "$yaml_file" > "$temp_env" 2>/dev/null; then
        # Process each line
        while IFS= read -r line; do
            # Remove ${ and }
            line="${line#\$\{}"
            line="${line%\}}"
            
            # Check if has default value (:-value)
            if [[ "$line" =~ ^([^:]+):-(.*)$ ]]; then
                # Has default value
                echo "${BASH_REMATCH[1]}=${BASH_REMATCH[2]}"
            else
                # No default value - mark as required
                echo "# REQUIRED: ${line}="
            fi
        done < "$temp_env" | sort -u > "$env_file"
        
        rm -f "$temp_env"
        
        local count
        count=$(grep -cv '^#' "$env_file" || true)
        
        if [[ $count -eq 0 ]]; then
            warn "No variables found"
            echo "# No environment variables detected in $yaml_file" > "$env_file"
        else
            ok "Extracted $count variables"
        fi
    else
        warn "No environment variables found"
        echo "# No environment variables detected in $yaml_file" > "$env_file"
    fi
}

# Interactive yes/no prompt
ask() {
    local prompt="$1"
    
    # If force mode, auto-answer yes
    if [[ "$FORCE_YES" == true ]]; then
        info "Auto-answering YES to: $prompt"
        return 0
    fi
    
    local reply
    read -rp "$(echo -e "${YELLOW}[?]${NC} $prompt (y/N): ")" reply
    [[ "$reply" =~ ^[Yy]$ ]]
}

edit_env() {
    local env_file="$1"
    
    newline
    if ! ask "Do you want to edit $env_file now?"; then
        info "Skipping edit"
        return 0
    fi
    
    # Try to find an editor
    local editor="${EDITOR:-}"
    
    if [[ -z "$editor" ]]; then
        if command -v nano &>/dev/null; then
            editor="nano"
        elif command -v vi &>/dev/null; then
            editor="vi"
        else
            warn "No editor found (nano/vi). Skipping edit."
            return 0
        fi
    fi
    
    info "Opening in $editor..."
    "$editor" "$env_file"
    ok "File edited"
    
    # Set secure permissions
    chmod 600 "$env_file"
    ok "Secure permissions set (600)"
}

run_compose() {
    local compose_file="$1"
    local env_file="$2"
    
    newline
    if ! ask "Do you want to start Docker Compose now?"; then
        info "Skipped. To run manually:"
        if [[ "$PULL_LATEST" == true ]]; then
            echo "  docker compose -f $compose_file --env-file $env_file up -d --pull always"
        else
            echo "  docker compose -f $compose_file --env-file $env_file up -d"
        fi
        return 0
    fi
    
    # Build compose command
    local compose_args=(-f "$compose_file" --env-file "$env_file" up -d)
    
    if [[ "$PULL_LATEST" == true ]]; then
        info "Starting with --pull always (update mode)..."
        compose_args+=(--pull always)
    else
        info "Starting containers..."
    fi
    
    if docker compose "${compose_args[@]}"; then
        ok "Docker Compose started successfully!"
        newline
        info "Useful commands:"
        info "  View logs: docker compose logs -f"
        info "  Stop:      docker compose down"
    else
        die "Docker Compose failed" 1
    fi
}

usage() {
    cat <<EOF
Docker Compose Setup Script v${VERSION}

USAGE: 
    $0 -y <file|url> [OPTIONS]

REQUIRED:
    -y <source>     Path or URL to docker-compose.yaml

OPTIONS:
    -n <source>     Path or URL to nginx.conf (optional)
    -e <filename>   Output .env filename (default: .env)
    -u              Pull latest images on startup
    -f              Force yes to all prompts (non-interactive)
    -h              Show this help

EXAMPLES:
    # Basic usage
    $0 -y docker-compose.yaml

    # With nginx config
    $0 -y docker-compose.yaml -n nginx.conf

    # Download from URL with update mode
    $0 -y https://example.com/compose.yaml -u

    # Non-interactive mode
    $0 -f -y ./compose.yaml -e .env.prod

    # Combined flags
    $0 -u -f -y https://raw.githubusercontent.com/user/repo/main/docker-compose.yaml

EXIT CODES:
    0   Success
    1   General error
    64  Invalid input
    65  File not found
    69  Download failed
    127 Missing dependencies
EOF
}

parse_args() {
    compose_source=""
    nginx_source=""

    if [[ $# -eq 0 ]]; then
        usage
        exit 0
    fi

    while [[ $# -gt 0 ]]; do
        case $1 in
            -y)
                compose_source="$2"
                shift 2
                ;;
            -n)
                nginx_source="$2"
                shift 2
                ;;
            -e)
                ENV_OUTPUT="$2"
                shift 2
                ;;
            -u)
                PULL_LATEST=true
                shift
                ;;
            -f)
                FORCE_YES=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                err "Unknown option: $1"
                newline
                usage
                exit 64
                ;;
        esac
    done

    # export to outer scope
    export compose_source
    export nginx_source
}

validate_required() {
    if [[ -z "${compose_source:-}" ]]; then
        err "Error: -y flag is required!"
        newline
        usage
        exit 64
    fi
}

show_mode_info() {
    if [[ "$PULL_LATEST" == true ]]; then
        info "UPDATE MODE: Will pull latest images"
    fi
    if [[ "$FORCE_YES" == true ]]; then
        info "FORCE MODE: Non-interactive (auto-yes)"
    fi
}

retrieve_compose() {
    newline
    info "=== Step 1: Retrieving docker-compose.yaml ==="
    get_file "${compose_source}" "$COMPOSE_FILE"
}

retrieve_nginx() {
    if [[ -n "${nginx_source:-}" ]]; then
        newline
        info "=== Step 2: Retrieving nginx.conf (optional) ==="
        if ! get_file "${nginx_source}" "nginx.conf"; then
            warn "Failed to get nginx.conf - continuing without it"
        fi
    fi
}

handle_env_overwrite() {
    if [[ -f "$ENV_OUTPUT" ]]; then
        warn "File $ENV_OUTPUT already exists"
        if ! ask "Overwrite it?"; then
            read -rp "$(echo -e "${YELLOW}[?]${NC} Enter new filename: ")" new_name
            if [[ -n "$new_name" ]]; then
                ENV_OUTPUT="$new_name"
                info "Using: $ENV_OUTPUT"
            else
                die "Invalid filename" 64
            fi
        fi
    fi
}

generate_env() {
    newline
    info "=== Step 3: Generating .env file ==="
    handle_env_overwrite
    extract_vars "$COMPOSE_FILE" "$ENV_OUTPUT"
    edit_env "$ENV_OUTPUT"
}

run_compose_flow() {
    newline
    info "=== Step 4: Docker Compose ==="
    run_compose "$COMPOSE_FILE" "$ENV_OUTPUT"
}

main() {
    parse_args "$@"
    validate_required

    check_dependencies
    show_mode_info

    retrieve_compose
    retrieve_nginx

    generate_env

    run_compose_flow

    newline
    ok "=== Setup Complete ==="
}

main "$@"
