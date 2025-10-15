#!/bin/bash

# ==============================================================================
# Docker Compose Initializer & .env Generator
# Version: V0.2.0-alpha
# ==============================================================================
# This script automates the initial setup for Docker Compose projects.
# It fetches a docker-compose.yaml file, intelligently scans it for environment
# variables (like ${DB_USER}), and generates a ready-to-use .env file.
# This eliminates the need to manually find and create configuration files.
# ==============================================================================

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[ℹ]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_update() {
    echo -e "${CYAN}[⟳]${NC} $1"
}

process_file() {
    local input="$1"
    local file_type="$2"
    local output_name="$3"
    
    if [[ -z "$input" ]]; then
        return 1
    fi
    
    if [[ "$input" =~ ^https?:// ]]; then
        print_info "Downloading $file_type from: $input"
        if curl -fsSL "$input" -o "$output_name"; then
            print_success "$file_type file downloaded successfully: $output_name"
            echo "$output_name"
            return 0
        else
            print_error "Failed to download $file_type file"
            return 1
        fi
    else
        if [[ -f "$input" ]]; then
            local absolute_input
            absolute_input=$(realpath "$input")
            
            print_success "$file_type file found: $absolute_input"
            
            if [[ "$absolute_input" != "$output_name" ]]; then
                cp "$absolute_input" "$output_name"
                print_success "$file_type file copied to: $output_name"
            fi
            
            echo "$output_name"
            return 0
        else
            print_error "$file_type file not found at given path: $input"
            return 1
        fi
    fi
}

YAML_INPUT=""
NGINX_INPUT=""
UPDATE_MODE=false

while getopts "y:n:uh" opt; do
    case $opt in
        y)
            YAML_INPUT="$OPTARG"
            ;;
        n)
            NGINX_INPUT="$OPTARG"
            ;;
        u)
            UPDATE_MODE=true
            ;;
        h)
            echo "Usage:"
            echo "  $0 [-u] -y <yaml_file_or_url> [-n <nginx_file_or_url>]"
            echo ""
            echo "Options:"
            echo "  -y    Specify docker-compose.yaml file or URL"
            echo "  -n    Specify nginx.conf file or URL (optional)"
            echo "  -u    Update mode: Pull latest images when running compose"
            echo "  -h    Show this help message"
            echo ""
            echo "Examples:"
            echo "  $0 -y docker-compose.yaml -n nginx.conf"
            echo "  $0 -u -y https://example.com/compose.yaml"
            echo "  $0 -u -y ./compose.yaml -n https://example.com/nginx.conf"
            echo "  $0  (interactive mode)"
            exit 0
            ;;
        \?)
            print_error "Invalid argument: -$OPTARG"
            exit 1
            ;;
    esac
done

if [[ "$UPDATE_MODE" == true ]]; then
    print_update "UPDATE MODE ENABLED - Images will be pulled to latest versions"
fi

YAML_FILE=""
IN_DIRECTORY_YAML="docker-compose.yaml"
DOWNLOADED_YAML_NAME="docker-compose-downloaded.yaml"

print_info "=== Step 1: Retrieving docker-compose.yaml file ==="

if [[ -z "$YAML_INPUT" ]]; then
    if [[ -f "$IN_DIRECTORY_YAML" ]]; then
        YAML_FILE="$IN_DIRECTORY_YAML"
        print_success "docker-compose.yaml found in current directory"
    else
        print_warning "docker-compose.yaml not found in current directory"
        read -rp "$(echo -e ${YELLOW}[?]${NC}) Enter download URL or file path: " YAML_INPUT
        
        if [[ -z "$YAML_INPUT" ]]; then
            print_error "docker-compose.yaml is required!"
            exit 1
        fi
        
        YAML_FILE=$(process_file "$YAML_INPUT" "docker-compose.yaml" "$DOWNLOADED_YAML_NAME")
        if [[ $? -ne 0 ]]; then
            exit 1
        fi
    fi
else
    YAML_FILE=$(process_file "$YAML_INPUT" "docker-compose.yaml" "$IN_DIRECTORY_YAML")
    if [[ $? -ne 0 ]]; then
        exit 1
    fi
fi

NGINX_FILE=""
IN_DIRECTORY_NGINX="nginx.conf"

print_info ""
print_info "=== Step 2: Retrieving nginx.conf file (optional) ==="

if [[ -z "$NGINX_INPUT" ]]; then
    if [[ -f "$IN_DIRECTORY_NGINX" ]]; then
        print_success "nginx.conf found in current directory"
        read -rp "$(echo -e ${YELLOW}[?]${NC}) Use this file? (y/n): " use_existing
        if [[ "$use_existing" =~ ^[Yy]$ ]]; then
            NGINX_FILE="$IN_DIRECTORY_NGINX"
        fi
    fi
    
    if [[ -z "$NGINX_FILE" ]]; then
        read -rp "$(echo -e ${YELLOW}[?]${NC}) Do you want to specify nginx.conf file? (y/n): " want_nginx
        
        if [[ "$want_nginx" =~ ^[Yy]$ ]]; then
            read -rep "$(echo -e ${YELLOW}[?]${NC}) Enter download URL or file path for nginx.conf: " NGINX_INPUT
            
            if [[ -n "$NGINX_INPUT" ]]; then
                NGINX_FILE=$(process_file "$NGINX_INPUT" "nginx.conf" "nginx.conf")
                if [[ $? -ne 0 ]]; then
                    print_warning "Error retrieving nginx.conf - continuing without nginx file"
                    NGINX_FILE=""
                fi
            fi
        else
            print_warning "nginx.conf not provided - continuing"
        fi
    fi
else
    NGINX_FILE=$(process_file "$NGINX_INPUT" "nginx.conf" "nginx.conf")
    if [[ $? -ne 0 ]]; then
        print_warning "Error retrieving nginx.conf - continuing without nginx file"
        NGINX_FILE=""
    fi
fi

print_info ""
print_info "=== Summary of Retrieved Files ==="
print_success "Docker Compose: $YAML_FILE (File used for execution)"
if [[ -n "$NGINX_FILE" ]]; then
    print_success "Nginx Config: $NGINX_FILE"
else
    print_warning "Nginx Config: Not provided"
fi

print_info ""
print_info "=== Step 3: Creating .env file ==="

ENV_FILE=".env"

if [[ -f "$ENV_FILE" ]]; then
    print_warning ".env file already exists"
    read -rp "$(echo -e ${YELLOW}[?]${NC}) Overwrite existing file (Y) or create new file (N)? (Y/n): " choice
    case "$choice" in
        [Nn]*)
            read -rp "$(echo -e ${YELLOW}[?]${NC}) Enter new file name (e.g. .env.dev): " NEW_ENV
            if [[ -n "$NEW_ENV" ]]; then
                ENV_FILE="$NEW_ENV"
                print_info "New file: $ENV_FILE"
            else
                print_error "Invalid file name!"
                exit 1
            fi
            ;;
        *)
            print_info "Existing file will be overwritten"
            ;;
    esac
fi

print_info "Extracting environment variables from $YAML_FILE..."

grep -oP '\$\{([A-Z_][A-Z0-9_]*)(:-([^}]*))?\}' "$YAML_FILE" | \
    sed -E 's/\$\{([A-Z_][A-Z0-9_]*)(\:\-([^}]*))?\}/\1=\3/g' | \
    awk -F= '{
        if (length($2) == 0 && NF == 2) {
            print "# MANDATORY: "$1"=[VALUE_NEEDED]"
        } else {
            print $0
        }
    }' | sort -u > "$ENV_FILE"

VARS_COUNT=$(wc -l < "$ENV_FILE")

if [[ $VARS_COUNT -eq 0 ]]; then
    print_warning "No environment variables found in YAML file"
    echo "# No environment variables found in docker-compose.yaml" > "$ENV_FILE"
else
    print_success "$VARS_COUNT variables extracted"
fi

print_info ""
read -rp "$(echo -e ${YELLOW}[?]${NC}) Do you want to edit $ENV_FILE file? (y/n): " edit_choice

if [[ "$edit_choice" =~ ^[Yy]$ ]]; then
    EDITOR_CMD=${EDITOR:-nano}
    
    if ! command -v "$EDITOR_CMD" &> /dev/null; then
        print_warning "Editor $EDITOR_CMD not found, using vi"
        EDITOR_CMD="vi"
        if ! command -v "$EDITOR_CMD" &> /dev/null; then
            print_error "No editor found!"
            exit 1
        fi
    fi
    
    print_info "Opening file in $EDITOR_CMD..."
    "$EDITOR_CMD" "$ENV_FILE"
    print_success "$ENV_FILE file has been edited"
else
    print_warning "Continuing without editing (default values will be used)"
fi

print_info ""
read -rp "$(echo -e ${YELLOW}[?]${NC}) Do you want to run Docker Compose? (y/n): " run_docker

if [[ "$run_docker" =~ ^[Yy]$ ]]; then
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed!"
        exit 1
    fi
    
    if [[ "$UPDATE_MODE" == true ]]; then
        print_update "Running docker compose with image update (--pull always)..."
        COMPOSE_CMD="docker compose -f $YAML_FILE --env-file $ENV_FILE up -d --pull always"
    else
        print_info "Running docker compose..."
        COMPOSE_CMD="docker compose -f $YAML_FILE --env-file $ENV_FILE up -d"
    fi
    
    if eval "$COMPOSE_CMD"; then
        print_success "Docker Compose executed successfully!"
        echo ""
        if [[ "$UPDATE_MODE" == true ]]; then
            print_update "All images have been pulled to latest versions"
        fi
        print_info "To view logs: docker compose logs -f"
        print_info "To stop services: docker compose down"
    else
        print_error "Error running Docker Compose"
        exit 1
    fi
else
    print_warning "Docker Compose execution cancelled"
    echo ""
    if [[ "$UPDATE_MODE" == true ]]; then
        print_info "To run manually with update, use:"
        echo "  docker compose -f $YAML_FILE --env-file $ENV_FILE up -d --pull always"
    else
        print_info "To run manually, use:"
        echo "  docker compose -f $YAML_FILE --env-file $ENV_FILE up -d"
    fi
fi

print_info ""
print_success "=== Script completed successfully ==="