#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# Docker Compose Initializer & .env Generator
# Version: V1.0.2
# ==============================================================================
# This script automates the initial setup for Docker Compose projects.
# It fetches a docker-compose.yaml file, intelligently scans it for environment
# variables, and generates a ready-to-use .env file with proper security.
# ==============================================================================

readonly VERSION="1.0.2"
readonly COMPOSE_FILE="docker-compose.yaml"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly PROMPT_TIMEOUT=30

# Globals
PULL_LATEST=false
FORCE_YES=false
ENV_OUTPUT=".env"
LOG_FILE=""

# Temp files registry
declare -a __TMP_FILES=()

# Register temp file for cleanup
_register_temp() {
  __TMP_FILES+=("$1")
}

# Global cleanup handler
_cleanup_all() {
  local exit_code=$?
  for f in "${__TMP_FILES[@]:-}"; do
    [[ -n "$f" && -f "$f" ]] && rm -f "$f" 2>/dev/null || true
  done
  return $exit_code
}

# Setup traps for various signals
trap '_cleanup_all' EXIT
trap 'echo ""; err "Interrupted by user"; exit 130' INT TERM

# Colors
readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[1;33m'
readonly BLUE=$'\033[0;34m'
readonly CYAN=$'\033[0;36m'
readonly BOLD=$'\033[1m'
readonly NC=$'\033[0m'

# Logging helpers
err()   { printf "%b\n" "${RED}${BOLD}[✗]${NC} $*" >&2; }
ok()    { printf "%b\n" "${GREEN}${BOLD}[✓]${NC} $*"; }
info()  { printf "%b\n" "${BLUE}${BOLD}[ℹ]${NC} $*"; }
warn()  { printf "%b\n" "${YELLOW}${BOLD}[!]${NC} $*"; }

die() {
  err "$1"
  exit "${2:-1}"
}

newline() { printf "\n"; }

# Usage information
usage() {
  cat <<EOF
${BOLD}Docker Compose Setup Script v${VERSION}${NC}

${BOLD}USAGE:${NC}
    $0 -y <file|url> [OPTIONS]

${BOLD}REQUIRED:${NC}
    ${GREEN}-y <source>${NC}     Path or URL to docker-compose.yaml

${BOLD}OPTIONS:${NC}
    ${GREEN}-n <source>${NC}     Path or URL to nginx.conf (optional)
    ${GREEN}-e <filename>${NC}   Output .env filename (default: .env)
    ${GREEN}-u${NC}              Pull latest images on startup
    ${GREEN}-f${NC}              Force yes to all prompts (non-interactive)
    ${GREEN}-l <logfile>${NC}    Write logs to file (append)
    ${GREEN}-h${NC}              Show this help

${BOLD}EXAMPLES:${NC}
    $0 -y docker-compose.yaml
    $0 -f -y ./compose.yaml -e .env.prod
    $0 -y https://example.com/docker-compose.yaml -u

${BOLD}EXIT CODES:${NC}
    0   Success
    1   General error
    64  Invalid input
    65  File not found
    69  Download failed
    70  Docker not available
    71  Validation failed
    127 Missing dependencies
    130 Interrupted by user
EOF
}

# Parse command line arguments
parse_args() {
  compose_source=""
  nginx_source=""
  
  while getopts ":y:n:e:ufl:h" opt; do
    case "$opt" in
      y) compose_source="$OPTARG" ;;
      n) nginx_source="$OPTARG" ;;
      e) ENV_OUTPUT="$OPTARG" ;;
      u) PULL_LATEST=true ;;
      f) FORCE_YES=true ;;
      l) LOG_FILE="$OPTARG" ;;
      h) usage; exit 0 ;;
      \?) err "Unknown option: -$OPTARG"; newline; usage; exit 64 ;;
      :) die "Option -$OPTARG requires an argument" 64 ;;
    esac
  done
  shift $((OPTIND-1))

  # Validate required arguments
  if [[ -z "${compose_source:-}" ]]; then
    err "Error: -y flag is required!"
    newline
    usage
    exit 64
  fi

  # Validate ENV_OUTPUT filename
  if [[ "$ENV_OUTPUT" =~ [[:space:]/\\\'\"] ]]; then
    die "Invalid .env filename (contains spaces or special chars): $ENV_OUTPUT" 64
  fi

  # Setup logging
  if [[ -n "$LOG_FILE" ]]; then
    touch "$LOG_FILE" 2>/dev/null || die "Cannot write to log file: $LOG_FILE" 1
    exec > >(tee -a "$LOG_FILE") 2>&1
    info "Logging to: $LOG_FILE"
  fi
}

# Check required dependencies
check_dependencies() {
  local missing=()
  
  for cmd in curl grep sed awk docker; do
    if ! command -v "$cmd" &>/dev/null; then
      missing+=("$cmd")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    die "Missing required commands: ${missing[*]}" 127
  fi

  # Check Docker daemon
  if ! docker info &>/dev/null; then
    warn "Docker daemon not accessible (may be needed later)"
  fi
}

# Validate YAML syntax
check_yaml_syntax() {
  local yaml_file="$1"
  info "Validating YAML syntax..."

  # Try yamllint first
  if command -v yamllint &>/dev/null; then
    if yamllint -d relaxed "$yaml_file" 2>&1 | grep -qi error; then
      warn "YAML validation found issues"
      return 1
    fi
    ok "YAML syntax valid (yamllint)"
    return 0
  fi

  # Fallback to Python
  if command -v python3 &>/dev/null; then
    if python3 -c "import yaml; yaml.safe_load(open('$yaml_file'))" 2>/dev/null; then
      ok "YAML syntax valid (python)"
      return 0
    else
      warn "YAML may have syntax errors"
      return 1
    fi
  fi

  warn "Cannot validate YAML (install yamllint or python3-yaml)"
  return 0
}

# Secure file download with retries
get_file() {
  local src="$1"
  local dest="$2"
  local max_retries=3
  local retry_count=0

  if [[ "$src" =~ ^https?:// ]]; then
    info "Downloading from: ${src}"
    
    # Validate URL format
    if [[ ! "$src" =~ ^https:// ]]; then
      warn "URL is not HTTPS: $src"
      if ! ask "Continue with non-HTTPS URL?"; then
        die "Download cancelled" 69
      fi
    fi

    # Download with retries
    while [[ $retry_count -lt $max_retries ]]; do
      if curl --fail --proto '=https' --tlsv1.2 -fsSL \
              --retry 2 --max-time 60 --connect-timeout 10 \
              -A "docker-compose-init/$VERSION" \
              "$src" -o "$dest" 2>/dev/null; then
        ok "Downloaded: $dest"
        return 0
      fi
      
      retry_count=$((retry_count + 1))
      [[ $retry_count -lt $max_retries ]] && sleep 2
    done
    
    die "Download failed after $max_retries attempts: $src" 69

  else
    # Local file
    if [[ ! -f "$src" ]]; then
      die "File not found: $src" 65
    fi
    
    if [[ ! -r "$src" ]]; then
      die "File not readable: $src" 65
    fi

    cp -f -- "$src" "$dest" || die "Failed to copy: $src" 1
    ok "Copied: $dest"
  fi
}

# Enhanced variable extraction with better regex and context awareness
extract_vars() {
  local yaml_file="$1"
  local env_file="$2"
  
  info "Extracting environment variables from: $yaml_file"

  local temp_raw temp_processed
  temp_raw=$(mktemp) || die "mktemp failed" 1
  temp_processed=$(mktemp) || die "mktemp failed" 1
  _register_temp "$temp_raw"
  _register_temp "$temp_processed"

  # Extract variables from relevant YAML sections only
  awk '
    /^[[:space:]]*(environment|env_file):[[:space:]]*$/ { in_section=1; next }
    /^[[:space:]]*[a-zA-Z_]/ && in_section && /^[^[:space:]]/ { in_section=0 }
    in_section { print }
  ' "$yaml_file" > "$temp_raw"

  # If nothing found in structured sections, try global search
  if [[ ! -s "$temp_raw" ]]; then
    cat "$yaml_file" > "$temp_raw"
  fi

  # Extract variable references
  grep -aoE '(\$\{[A-Za-z_][A-Za-z0-9_]*[^}]*\}|\$[A-Za-z_][A-Za-z0-9_]*)' "$temp_raw" 2>/dev/null | \
  while IFS= read -r token; do
    # Remove ${ } or $
    if [[ "$token" =~ ^\$\{(.+)\}$ ]]; then
      inner="${BASH_REMATCH[1]}"
    else
      inner="${token#\$}"
    fi

    # Parse different patterns
    if [[ "$inner" =~ ^([A-Za-z_][A-Za-z0-9_]*):=(.*)$ ]]; then
      printf "%s=%s\n" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    elif [[ "$inner" =~ ^([A-Za-z_][A-Za-z0-9_]*):-(.*)$ ]]; then
      printf "%s=%s\n" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    elif [[ "$inner" =~ ^([A-Za-z_][A-Za-z0-9_]*)\?(.*)$ ]]; then
      printf "# REQUIRED: %s=    # Error if unset: %s\n" "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    elif [[ "$inner" =~ ^([A-Za-z_][A-Za-z0-9_]*)$ ]]; then
      printf "# REQUIRED: %s=\n" "${BASH_REMATCH[1]}"
    else
      warn "Complex variable pattern: $token"
      printf "# FIXME: %s=    # Complex pattern, verify manually\n" "$inner"
    fi
  done | \
  awk '!seen[$0]++' > "$temp_processed"

  # Count variables
  local count
  count=$(grep -cE '^(# REQUIRED:|# FIXME:|[A-Za-z_][A-Za-z0-9_]*=)' "$temp_processed" 2>/dev/null || echo "0")

  if [[ $count -eq 0 ]]; then
    warn "No environment variables detected"
    {
      echo "# No environment variables detected in $yaml_file"
      echo "# Generated by docker-compose-init v${VERSION}"
      echo "# Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
    } > "$env_file"
  else
    ok "Extracted $count variable references"
    {
      echo "# Environment variables for docker-compose"
      echo "# Generated by docker-compose-init v${VERSION}"
      echo "# Date: $(date -u '+%Y-%m-%d %H:%M:%S UTC')"
      echo "# Source: $yaml_file"
      echo ""
      cat "$temp_processed"
    } > "$env_file"
  fi

  ok "Created: $env_file"
}

# Validate .env file after editing
validate_env() {
  local env_file="$1"
  
  info "Validating .env file..."

  # Check for unfilled REQUIRED variables
  local unfilled
  unfilled=$(grep -c '^# REQUIRED:.*=\s*$' "$env_file" 2>/dev/null || echo "0")
  
  if [[ "$unfilled" -gt 0 ]]; then
    warn "Found $unfilled unfilled REQUIRED variables:"
    grep '^# REQUIRED:.*=\s*$' "$env_file" | head -5
    [[ "$unfilled" -gt 5 ]] && echo "  ... and $((unfilled - 5)) more"
    
    if [[ "$FORCE_YES" != true ]]; then
      newline
      if ! ask "Continue with unfilled variables?"; then
        die "Please complete required variables in $env_file" 71
      fi
    fi
  fi

  # Check for FIXME markers
  local fixme
  fixme=$(grep -c '^# FIXME:' "$env_file" 2>/dev/null || echo "0")
  
  if [[ "$fixme" -gt 0 ]]; then
    warn "Found $fixme variables needing manual review"
    grep '^# FIXME:' "$env_file"
  fi

  # Check for empty values
  local empty_vals
  empty_vals=$(grep -cE '^[A-Za-z_][A-Za-z0-9_]*=\s*$' "$env_file" 2>/dev/null || echo "0")
  
  if [[ "$empty_vals" -gt 0 ]]; then
    warn "Found $empty_vals variables with empty values"
  fi

  ok "Validation complete"
}

# Safe yes/no prompt with timeout
ask() {
  local prompt="$1"

  if [[ "$FORCE_YES" == true ]]; then
    info "Auto-answering YES: $prompt"
    return 0
  fi

  if [[ ! -t 0 ]]; then
    warn "Non-interactive mode: defaulting to NO for: $prompt"
    return 1
  fi

  local reply
  # Use read with timeout
  if read -t "$PROMPT_TIMEOUT" -rp "$(printf "%b" "${YELLOW}${BOLD}[?]${NC} $prompt ${CYAN}(Y/n) [${PROMPT_TIMEOUT}s]:${NC} ")" reply; then
    case "$reply" in
      [Nn]*) return 1 ;;
      *) return 0 ;;  # Default to yes
    esac
  else
    # Timeout - default to yes
    echo ""
    info "Timeout - defaulting to YES"
    return 0
  fi
}

# Edit .env with proper editor handling
edit_env() {
  local env_file="$1"

  newline
  if ! ask "Edit $env_file now?"; then
    info "Skipping edit"
    return 0
  fi

  # Find suitable editor
  local editor="${EDITOR:-}"
  if [[ -z "$editor" ]]; then
    for ed in nano vim vi emacs; do
      if command -v "$ed" &>/dev/null; then
        editor="$ed"
        break
      fi
    done
  fi

  if [[ -z "$editor" ]]; then
    warn "No editor found. Set EDITOR environment variable."
    return 1
  fi

  info "Opening with: $editor"
  
  # Handle editor with arguments
  if [[ "$editor" =~ [[:space:]] ]]; then
    eval "$editor \"$env_file\"" || warn "Editor exited with error"
  else
    "$editor" "$env_file" || warn "Editor exited with error"
  fi

  # Set secure permissions
  chmod 600 "$env_file" 2>/dev/null || warn "Could not set permissions on $env_file"
  ok "File edited"

  # Ownership warning
  local owner_uid
  owner_uid=$(stat -c %u "$env_file" 2>/dev/null || stat -f %u "$env_file" 2>/dev/null || echo "")
  if [[ "$owner_uid" == "0" ]]; then
    warn "File is owned by root - ensure proper access for Docker"
  fi

  # Validate after edit
  validate_env "$env_file"
}

# Run docker compose with comprehensive checks
run_compose() {
  local compose_file="$1"
  local env_file="$2"

  newline
  if ! ask "Start Docker Compose now?"; then
    info "Skipped. To run manually:"
    newline
    if [[ "$PULL_LATEST" == true ]]; then
      echo "  docker compose -f $compose_file --env-file $env_file up -d --pull always"
    else
      echo "  docker compose -f $compose_file --env-file $env_file up -d"
    fi
    newline
    info "Useful commands:"
    echo "  docker compose -f $compose_file logs -f     # View logs"
    echo "  docker compose -f $compose_file ps          # List containers"
    echo "  docker compose -f $compose_file down        # Stop all"
    return 0
  fi

  # Detect compose command
  local -a compose_cmd
  if docker compose version &>/dev/null 2>&1; then
    compose_cmd=(docker compose)
  elif command -v docker-compose &>/dev/null; then
    compose_cmd=(docker-compose)
  else
    die "Neither 'docker compose' nor 'docker-compose' available" 70
  fi

  # Check Docker daemon
  if ! docker info &>/dev/null; then
    die "Docker daemon not running or not accessible" 70
  fi

  # Build command arguments
  local -a args=(
    "-f" "$compose_file"
    "--env-file" "$env_file"
  )

  # Pre-pull images if requested
  if [[ "$PULL_LATEST" == true ]]; then
    info "Pulling latest images..."
    if ! "${compose_cmd[@]}" "${args[@]}" pull; then
      warn "Some images failed to pull (will try to start anyway)"
    fi
  fi

  # Start containers
  info "Starting containers..."
  args+=("up" "-d")
  
  if "${compose_cmd[@]}" "${args[@]}"; then
    newline
    ok "Docker Compose started successfully!"
    newline
    
    # Show running containers
    info "Running containers:"
    "${compose_cmd[@]}" -f "$compose_file" ps
    
    newline
    info "Useful commands:"
    echo "  ${compose_cmd[*]} -f $compose_file logs -f        # Follow logs"
    echo "  ${compose_cmd[*]} -f $compose_file ps             # List containers"
    echo "  ${compose_cmd[*]} -f $compose_file restart        # Restart all"
    echo "  ${compose_cmd[*]} -f $compose_file down           # Stop and remove"
    echo "  ${compose_cmd[*]} -f $compose_file down -v        # Stop and remove volumes"
  else
    die "Docker Compose failed to start" 1
  fi
}

# Handle .env overwrite with simple y/n
handle_env_overwrite() {
  if [[ ! -f "$ENV_OUTPUT" ]]; then
    return 0
  fi

  warn "File already exists: $ENV_OUTPUT"
  
  if [[ "$FORCE_YES" == true ]]; then
    info "Force mode: Overwriting $ENV_OUTPUT"
    return 0
  fi

  newline
  if ask "Overwrite $ENV_OUTPUT?"; then
    info "Overwriting: $ENV_OUTPUT"
    return 0
  else
    # Ask for new filename
    local new_name
    read -rp "$(printf "%b" "${CYAN}Enter new filename (or press Enter to cancel):${NC} ")" new_name
    if [[ -z "$new_name" ]]; then
      die "Cancelled by user" 0
    fi
    if [[ "$new_name" =~ [[:space:]/\\\'\"] ]]; then
      die "Invalid filename (contains spaces or special characters)" 64
    fi
    ENV_OUTPUT="$new_name"
    info "Using: $ENV_OUTPUT"
    # Recursive check in case new name also exists
    handle_env_overwrite
  fi
}

# Generate .env file workflow
generate_env() {
  newline
  info "=== Generating .env File ==="
  handle_env_overwrite
  extract_vars "$COMPOSE_FILE" "$ENV_OUTPUT"
  edit_env "$ENV_OUTPUT"
}

# Retrieve docker-compose.yaml
retrieve_compose() {
  newline
  info "=== Retrieving docker-compose.yaml ==="
  get_file "$compose_source" "$COMPOSE_FILE"
  check_yaml_syntax "$COMPOSE_FILE"
}

# Retrieve optional nginx.conf
retrieve_nginx() {
  if [[ -z "${nginx_source:-}" ]]; then
    return 0
  fi

  newline
  info "=== Retrieving nginx.conf ==="
  if ! get_file "$nginx_source" "nginx.conf"; then
    warn "Failed to retrieve nginx.conf - continuing without it"
  fi
}

# Print final summary
print_summary() {
  newline
  ok "=== Setup Complete ==="
  newline
  
  info "Summary:"
  echo "  ${GREEN}✓${NC} Docker Compose: $COMPOSE_FILE"
  echo "  ${GREEN}✓${NC} Environment:    $ENV_OUTPUT"
  [[ -f "nginx.conf" ]] && echo "  ${GREEN}✓${NC} Nginx Config:   nginx.conf"
  
  newline
  info "Next steps:"
  echo "  Review and adjust $ENV_OUTPUT as needed"
  echo "  Start services: docker compose -f $COMPOSE_FILE up -d"
}

# Main execution flow
main() {
  # Show banner
  printf "%b\n" "${BOLD}${BLUE}╔═══════════════════════════════════════════╗${NC}"
  printf "%b\n" "${BOLD}${BLUE}║  Docker Compose Initializer v${VERSION}  ║${NC}"
  printf "%b\n" "${BOLD}${BLUE}╚═══════════════════════════════════════════╝${NC}"
  newline

  parse_args "$@"
  check_dependencies

  # Display mode indicators
  [[ "$PULL_LATEST" == true ]] && info "Mode: Pull latest images"
  [[ "$FORCE_YES" == true ]]   && info "Mode: Force yes (non-interactive)"

  retrieve_compose
  retrieve_nginx
  generate_env
  run_compose "$COMPOSE_FILE" "$ENV_OUTPUT"
  print_summary
}

# Execute main if script is run directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  main "$@"
fi
