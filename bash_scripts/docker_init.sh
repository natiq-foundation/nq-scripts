#!/usr/bin/env bash

# ==============================================================================
# Docker Compose Initializer & .env Generator
# Version: V1.0.0-stable
# ==============================================================================
# This script automates the initial setup for Docker Compose projects.
# It fetches a docker-compose.yaml file, intelligently scans it for environment
# variables, and generates a ready-to-use .env file with proper security.
# ==============================================================================

set -euo pipefail

# ==============================================================================
# CONSTANTS
# ==============================================================================
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_NAME=$(basename "$0")
readonly LOG_FILE="${LOG_FILE:-/tmp/${SCRIPT_NAME%.*}.log}"
readonly TEMP_DIR=$(mktemp -d -t docker-compose-setup.XXXXXX)

readonly VAR_PATTERN='\$\{([A-Za-z_][A-Za-z0-9_]*)(:-([^}]*))?\}'
readonly IN_DIRECTORY_YAML="docker-compose.yaml"
readonly IN_DIRECTORY_NGINX="nginx.conf"

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_INVALID_INPUT=64
readonly EXIT_FILE_NOT_FOUND=65
readonly EXIT_SERVICE_UNAVAILABLE=69
readonly EXIT_DEPENDENCY_MISSING=127

# Colors
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly NC='\033[0m'

# ==============================================================================
# GLOBAL VARIABLES
# ==============================================================================
YAML_INPUT=""
NGINX_INPUT=""
UPDATE_MODE=false
VERBOSE=false
NON_INTERACTIVE=false
FORCE_OVERWRITE=false

# Check if running in non-interactive environment
[[ ! -t 0 ]] && NON_INTERACTIVE=true

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp=$(date +'%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "$LOG_FILE"
}

print_info() {
    echo -e "${BLUE}[ℹ]${NC} $1"
    log "INFO" "$1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
    log "SUCCESS" "$1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
    log "WARNING" "$1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1" >&2
    log "ERROR" "$1"
}

print_update() {
    echo -e "${CYAN}[⟳]${NC} $1"
    log "UPDATE" "$1"
}

cleanup() {
    [[ -d "$TEMP_DIR" ]] && rm -rf "$TEMP_DIR"
    log "INFO" "Cleanup completed"
}

trap cleanup EXIT ERR INT TERM

# ==============================================================================
# DEPENDENCY CHECKING
# ==============================================================================

check_dependencies() {
    local deps=(curl grep sed awk sort docker realpath)
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &>/dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing[*]}"
        print_error "Please install them and try again"
        exit $EXIT_DEPENDENCY_MISSING
    fi
    
    [[ "$VERBOSE" == true ]] && print_success "All dependencies are available"
}

# ==============================================================================
# INPUT VALIDATION
# ==============================================================================

validate_url() {
    local url="$1"
    
    # Check if URL starts with http:// or https://
    if [[ ! "$url" =~ ^https?:// ]]; then
        return 1
    fi
    
    # Basic domain validation
    if [[ ! "$url" =~ ^https?://[a-zA-Z0-9.-]+[/]? ]]; then
        print_error "Invalid URL format: $url"
        return 1
    fi
    
    return 0
}

validate_filename() {
    local filename="$1"
    
    # Check for path traversal attempts
    if [[ "$filename" =~ \.\./|\.\. ]]; then
        print_error "Path traversal detected in filename: $filename"
        return 1
    fi
    
    # Check for suspicious characters
    if [[ "$filename" =~ [';'|'&'|'`'|'$'|'('|')'] ]]; then
        print_error "Suspicious characters in filename: $filename"
        return 1
    fi
    
    return 0
}

sanitize_path() {
    local path="$1"
    # Remove potentially dangerous characters
    echo "$path" | sed 's/[;&|`$()]//g'
}

# ==============================================================================
# USER INTERACTION
# ==============================================================================

ask_user() {
    local prompt="$1"
    local default="${2:-}"
    local response
    
    if [[ "$NON_INTERACTIVE" == true ]]; then
        response="$default"
        print_info "Non-interactive mode: using default value '$default' for: $prompt"
    else
        read -rp "$(echo -e "${YELLOW}[?]${NC} $prompt")" response
        response="${response:-$default}"
    fi
    
    echo "$response"
}

ask_yes_no() {
    local prompt="$1"
    local default="${2:-n}"
    local response
    
    if [[ "$NON_INTERACTIVE" == true ]] || [[ "$FORCE_OVERWRITE" == true ]]; then
        response="$default"
        print_info "Auto-answering: $prompt -> $response"
    else
        response=$(ask_user "$prompt (y/n): " "$default")
    fi
    
    [[ "$response" =~ ^[Yy]$ ]]
}

# ==============================================================================
# FILE PROCESSING
# ==============================================================================

download_file() {
    local url="$1"
    local output="$2"
    local temp_file="${TEMP_DIR}/$(basename "$output").tmp"
    
    print_info "Downloading from: $url" >&2
    
    if curl -fsSL --retry 3 --retry-delay 2 --connect-timeout 10 \
        --max-time 60 "$url" -o "$temp_file"; then
        
        # Verify file is not empty
        if [[ ! -s "$temp_file" ]]; then
            print_error "Downloaded file is empty" >&2
            return $EXIT_SERVICE_UNAVAILABLE
        fi
        
        mv "$temp_file" "$output"
        print_success "Downloaded successfully: $output" >&2
        echo "$output"
        return $EXIT_SUCCESS
    else
        print_error "Failed to download file" >&2
        [[ -f "$temp_file" ]] && rm -f "$temp_file"
        return $EXIT_SERVICE_UNAVAILABLE
    fi
}

copy_file() {
    local source="$1"
    local destination="$2"
    
    if [[ ! -f "$source" ]]; then
        print_error "Source file not found: $source" >&2
        return $EXIT_FILE_NOT_FOUND
    fi
    
    local absolute_source
    absolute_source=$(realpath "$source")
    local absolute_dest
    absolute_dest=$(realpath -m "$destination")
    
    print_success "File found: $absolute_source" >&2
    
    if [[ "$absolute_source" != "$absolute_dest" ]]; then
        cp "$absolute_source" "$destination"
        print_success "File copied to: $destination" >&2
    fi
    
    echo "$destination"
    return $EXIT_SUCCESS
}

process_file() {
    local input="$1"
    local file_type="$2"
    local output_name="$3"
    
    if [[ -z "$input" ]]; then
        return $EXIT_INVALID_INPUT
    fi
    
    # Validate and sanitize
    if ! validate_filename "$output_name"; then
        return $EXIT_INVALID_INPUT
    fi
    
    if [[ "$input" =~ ^https?:// ]]; then
        if ! validate_url "$input"; then
            return $EXIT_INVALID_INPUT
        fi
        
        if download_file "$input" "$output_name" >/dev/null; then
            echo "$output_name"
            return $EXIT_SUCCESS
        else
            return $EXIT_SERVICE_UNAVAILABLE
        fi
    else
        if copy_file "$input" "$output_name"; then
            return $EXIT_SUCCESS
        else
            return $EXIT_FILE_NOT_FOUND
        fi
    fi
}

# ==============================================================================
# YAML HANDLING
# ==============================================================================

handle_yaml_input() {
    print_info "=== Step 1: Retrieving docker-compose.yaml file ===" >&2
    
    if [[ -z "$YAML_INPUT" ]]; then
        print_error "docker-compose.yaml is required! Use -y flag to specify the file."
        print_error "Run '$SCRIPT_NAME -h' for help"
        exit $EXIT_INVALID_INPUT
    fi
    
    local yaml_file
    if ! yaml_file=$(process_file "$YAML_INPUT" "docker-compose.yaml" "$IN_DIRECTORY_YAML" 2>/dev/null); then
        exit $?
    fi
    
    echo "$yaml_file"
}

# ==============================================================================
# NGINX HANDLING
# ==============================================================================

handle_nginx_input() {
    local nginx_file=""
    
    print_info "" >&2
    print_info "=== Step 2: Retrieving nginx.conf file (optional) ===" >&2
    
    if [[ -z "$NGINX_INPUT" ]]; then
        print_warning "nginx.conf not specified - continuing without nginx file" >&2
    else
        if ! nginx_file=$(process_file "$NGINX_INPUT" "nginx.conf" "nginx.conf" 2>/dev/null); then
            print_warning "Error retrieving nginx.conf - continuing without nginx file" >&2
            nginx_file=""
        fi
    fi
    
    echo "$nginx_file"
}

# ==============================================================================
# ENV FILE HANDLING
# ==============================================================================

handle_env_file() {
    local yaml_file="$1"
    local env_file=".env"
    
    print_info "" >&2
    print_info "=== Step 3: Creating .env file ===" >&2
    
    if [[ -f "$env_file" ]] && [[ "$FORCE_OVERWRITE" == false ]]; then
        print_warning ".env file already exists" >&2
        if ask_yes_no "Overwrite existing file (Y) or create new file (N)?" "y"; then
            print_info "Existing file will be overwritten" >&2
        else
            local new_env
            new_env=$(ask_user "Enter new file name (e.g. .env.dev): " ".env.dev")
            
            if [[ -n "$new_env" ]] && validate_filename "$new_env"; then
                env_file="$new_env"
                print_info "New file: $env_file" >&2
            else
                print_error "Invalid file name!" >&2
                exit $EXIT_INVALID_INPUT
            fi
        fi
    fi
    
    extract_variables "$yaml_file" "$env_file"
    
    echo "$env_file"
}

extract_variables() {
    local yaml_file="$1"
    local env_file="$2"
    
    print_info "Extracting environment variables from $yaml_file..." >&2
    
    # Extract and process variables
    if grep -oP "$VAR_PATTERN" "$yaml_file" 2>/dev/null | \
        sed -E 's/\$\{([A-Za-z_][A-Za-z0-9_]*)(\:\-([^}]*))?\}/\1=\3/g' | \
        awk -F= '{
            if (length($2) == 0 && NF == 2) {
                print "# MANDATORY: "$1"=[VALUE_NEEDED]"
            } else {
                print $0
            }
        }' | sort -u > "$env_file"; then
        
        local vars_count
        vars_count=$(wc -l < "$env_file")
        
        if [[ $vars_count -eq 0 ]]; then
            print_warning "No environment variables found in YAML file" >&2
            echo "# No environment variables found in docker-compose.yaml" > "$env_file"
        else
            print_success "$vars_count variables extracted" >&2
        fi
    else
        print_error "Failed to extract variables" >&2
        exit $EXIT_GENERAL_ERROR
    fi
}

# ==============================================================================
# EDITOR HANDLING
# ==============================================================================

edit_env_file() {
    local env_file="$1"
    
    print_info ""
    if ! ask_yes_no "Do you want to edit $env_file file?" "n"; then
        print_warning "Continuing without editing (default values will be used)"
        return
    fi
    
    local editor_cmd="${EDITOR:-nano}"
    
    if ! command -v "$editor_cmd" &>/dev/null; then
        print_warning "Editor $editor_cmd not found, trying vi"
        editor_cmd="vi"
        if ! command -v "$editor_cmd" &>/dev/null; then
            print_error "No editor found!"
            return
        fi
    fi
    
    print_info "Opening file in $editor_cmd..."
    "$editor_cmd" "$env_file"
    # Set secure permissions after editing
    chmod 600 "$env_file"
    print_success "Secure permissions set (600) for $env_file"
    print_success "$env_file file has been edited"
}

# ==============================================================================
# DOCKER COMPOSE EXECUTION
# ==============================================================================

run_docker_compose() {
    local yaml_file="$1"
    local env_file="$2"
    
    print_info ""
    print_info "Running Docker Compose automatically..."
    
    if ! command -v docker &>/dev/null; then
        print_error "Docker is not installed!"
        exit $EXIT_DEPENDENCY_MISSING
    fi
    
    local compose_args=(-f "$yaml_file" --env-file "$env_file" up -d)
    
    if [[ "$UPDATE_MODE" == true ]]; then
        print_update "Running docker compose with image update (--pull always)..."
        compose_args+=(--pull always)
    else
        print_info "Running docker compose..."
    fi
    
    [[ "$VERBOSE" == true ]] && print_info "Command: docker compose ${compose_args[*]}"
    
    if docker compose "${compose_args[@]}"; then
        print_success "Docker Compose executed successfully!"
        echo ""
        if [[ "$UPDATE_MODE" == true ]]; then
            print_update "All images have been pulled to latest versions"
        fi
        print_info "To view logs: docker compose logs -f"
        print_info "To stop services: docker compose down"
    else
        print_error "Error running Docker Compose"
        exit $EXIT_GENERAL_ERROR
    fi
}

# ==============================================================================
# HELP & USAGE
# ==============================================================================

show_help() {
    cat <<EOF
Docker Compose Initializer & .env Generator v${SCRIPT_VERSION}

USAGE:
    $SCRIPT_NAME -y <file|url> [OPTIONS]

REQUIRED:
    -y <file|url>    Specify docker-compose.yaml file or URL (REQUIRED)

OPTIONS:
    -n <file|url>    Specify nginx.conf file or URL (optional)
    -u               Update mode: Pull latest images when running compose
    -f               Force mode: Overwrite files without asking
    -v               Verbose mode: Show detailed output
    -h               Show this help message

EXAMPLES:
    # Basic usage:
    $SCRIPT_NAME -y docker-compose.yaml

    # With nginx configuration:
    $SCRIPT_NAME -y docker-compose.yaml -n nginx.conf

    # Update mode with URL:
    $SCRIPT_NAME -u -y https://example.com/compose.yaml

    # Non-interactive (CI/CD):
    $SCRIPT_NAME -f -y ./compose.yaml -n ./nginx.conf

    # Verbose mode for debugging:
    $SCRIPT_NAME -v -y docker-compose.yaml

    # Combined flags:
    $SCRIPT_NAME -u -f -v -y https://raw.githubusercontent.com/user/repo/main/compose.yaml

ENVIRONMENT VARIABLES:
    EDITOR           Preferred text editor (default: nano)
    LOG_FILE         Path to log file (default: /tmp/${SCRIPT_NAME%.*}.log)

EXIT CODES:
    0    Success
    1    General error
    64   Invalid input
    65   File not found
    69   Service unavailable (download failed)
    127  Missing dependencies

NOTES:
    - The -y flag is REQUIRED for script execution
    - Run without arguments to see this help message
    - nginx.conf is optional and can be omitted
    - In non-interactive environments, default values are used automatically

For more information, visit: https://github.com/yourusername/docker-compose-setup
EOF
}

# ==============================================================================
# MAIN FUNCTION
# ==============================================================================

main() {
    # If no arguments provided, show help
    if [[ $# -eq 0 ]]; then
        show_help
        exit $EXIT_SUCCESS
    fi
    
    log "INFO" "Script started: $SCRIPT_NAME v${SCRIPT_VERSION}"
    
    # Parse arguments
    while getopts "y:n:ufvh" opt; do
        case $opt in
            y) YAML_INPUT="$OPTARG" ;;
            n) NGINX_INPUT="$OPTARG" ;;
            u) UPDATE_MODE=true ;;
            f) FORCE_OVERWRITE=true ;;
            v) VERBOSE=true; set -x ;;
            h) show_help; exit $EXIT_SUCCESS ;;
            \?) print_error "Invalid argument: -$OPTARG"; show_help; exit $EXIT_INVALID_INPUT ;;
        esac
    done
    
    # Check if YAML was provided
    if [[ -z "$YAML_INPUT" ]]; then
        print_error "Error: -y flag is required!"
        echo ""
        show_help
        exit $EXIT_INVALID_INPUT
    fi
    
    # Check dependencies
    check_dependencies
    
    # Show mode information
    [[ "$UPDATE_MODE" == true ]] && print_update "UPDATE MODE ENABLED - Images will be pulled to latest versions"
    [[ "$VERBOSE" == true ]] && print_info "VERBOSE MODE ENABLED"
    [[ "$NON_INTERACTIVE" == true ]] && print_info "NON-INTERACTIVE MODE DETECTED"
    [[ "$FORCE_OVERWRITE" == true ]] && print_warning "FORCE MODE ENABLED - Files will be overwritten"
    
    # Execute workflow
    local yaml_file
    yaml_file=$(handle_yaml_input)
    
    local nginx_file
    nginx_file=$(handle_nginx_input)
    
    # Show summary
    print_info ""
    print_info "=== Summary of Retrieved Files ==="
    print_success "Docker Compose: $yaml_file (File used for execution)"
    if [[ -n "$nginx_file" ]]; then
        print_success "Nginx Config: $nginx_file"
    else
        print_warning "Nginx Config: Not provided"
    fi
    
    local env_file
    env_file=$(handle_env_file "$yaml_file")
    
    edit_env_file "$env_file"
    
    run_docker_compose "$yaml_file" "$env_file"
    
    print_info ""
    print_success "=== Script completed successfully ==="
    log "INFO" "Script completed successfully"
}

# ==============================================================================
# SCRIPT EXECUTION
# ==============================================================================

main "$@"