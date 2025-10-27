#!/usr/bin/env bash

#==============================================================================
# NatiqQuran API Full Setup Script
#==============================================================================
# Description: Orchestrates the complete setup process for NatiqQuran API
#              by executing startup, docker-init, and importer scripts in sequence.
# Version: 1.0.0
# Author: Natiq Development Team
# Usage: 
#   Interactive menu: ./full_setup.sh
#   Full setup: ./full_setup.sh --full [options]
#   Update mode: ./full_setup.sh -u /path/to/quran-api [options]
#==============================================================================

set -euo pipefail

#==============================================================================
# SCRIPT METADATA
#==============================================================================
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_AUTHOR="Natiq Development Team"

#==============================================================================
# PROJECT CONFIGURATION
#==============================================================================
readonly PROJECT_FOLDER="quran-api"
readonly REPOSITORY_URL="https://github.com/natiq-foundation/nq-scripts.git"
readonly REPOSITORY_FOLDER="nq-scripts"
readonly SCRIPTS_SUBFOLDER="bash_scripts"

#==============================================================================
# REMOTE SCRIPT URLS
#==============================================================================
readonly STARTUP_SCRIPT_URL="https://raw.githubusercontent.com/NatiqQuran/nq-scripts/main/bash_scripts/startup.sh"
readonly DOCKER_INIT_SCRIPT_URL="https://raw.githubusercontent.com/natiq-foundation/nq-scripts/refs/heads/main/bash_scripts/docker_init.sh"

#==============================================================================
# DOCKER CONFIGURATION FILES
#==============================================================================
readonly COMPOSE_FILE_URL="https://raw.githubusercontent.com/natiq-foundation/quran-api/refs/heads/main/docker-compose.yaml"
readonly NGINX_CONFIG_URL="https://raw.githubusercontent.com/natiq-foundation/quran-api/refs/heads/main/nginx.conf"

#==============================================================================
# SCRIPT SETTINGS
#==============================================================================
readonly DOWNLOAD_TIMEOUT=30
readonly TEMP_SCRIPT_DIR="/tmp"

#==============================================================================
# TERMINAL COLORS
#==============================================================================
readonly COLOR_RESET=$'\033[0m'
readonly COLOR_RED=$'\033[0;31m'
readonly COLOR_GREEN=$'\033[0;32m'
readonly COLOR_YELLOW=$'\033[1;33m'
readonly COLOR_BLUE=$'\033[0;34m'
readonly COLOR_CYAN=$'\033[0;36m'
readonly COLOR_BOLD=$'\033[1m'

#==============================================================================
# RUNTIME VARIABLES
#==============================================================================
EXECUTION_MODE="full"           # Modes: "full" or "update"
UPDATE_TARGET_DIR=""            # Target directory for update mode
INITIAL_WORKING_DIR="$(pwd)"    # Store initial directory for cleanup

# Script-specific options
STARTUP_OPTIONS=()
DOCKER_INIT_OPTIONS=()
IMPORTER_OPTIONS=()

#==============================================================================
# LOGGING FUNCTIONS
#==============================================================================

log_info() {
    echo -e "${COLOR_CYAN}[INFO]${COLOR_RESET} $*"
}

log_success() {
    echo -e "${COLOR_GREEN}[SUCCESS]${COLOR_RESET} $*"
}

log_error() {
    echo -e "${COLOR_RED}[ERROR]${COLOR_RESET} $*" >&2
}

log_warning() {
    echo -e "${COLOR_YELLOW}[WARNING]${COLOR_RESET} $*"
}

log_step() {
    echo -e "${COLOR_BOLD}${COLOR_BLUE}[STEP $1]${COLOR_RESET} $2"
}

#==============================================================================
# UTILITY FUNCTIONS
#==============================================================================

check_command_exists() {
    local cmd="$1"
    if ! command -v "$cmd" &> /dev/null; then
        log_error "Required command not found: $cmd"
        log_error "Please install $cmd and try again."
        exit 1
    fi
}

check_dependencies() {
    log_info "Checking required dependencies..."
    check_command_exists "curl"
    check_command_exists "bash"
    log_success "All dependencies are available"
}

validate_downloaded_script() {
    local file_path="$1"
    if [[ ! -s "$file_path" ]]; then
        log_error "Downloaded file is empty or missing: $file_path"
        return 1
    fi
    
    local first_line
    first_line="$(head -n 1 "$file_path" 2>/dev/null || true)"
    if [[ ! "$first_line" =~ ^#! ]]; then
        log_error "Downloaded script missing shebang: $file_path"
        return 1
    fi
    
    if [[ ! "$first_line" =~ bash && ! "$first_line" =~ sh ]]; then
        log_warning "Shebang does not reference bash/sh: $first_line"
    fi
    
    return 0
}

create_directory_if_not_exists() {
    local dir_path="$1"
    if [[ ! -d "$dir_path" ]]; then
        log_info "Creating directory: $dir_path"
        mkdir -p "$dir_path"
    else
        log_info "Using existing directory: $dir_path"
    fi
}

change_directory_safely() {
    local target_dir="$1"
    if [[ ! -d "$target_dir" ]]; then
        log_error "Directory does not exist: $target_dir"
        exit 1
    fi
    log_info "Changing to directory: $target_dir"
    cd "$target_dir" || exit 1
}

return_to_initial_directory() {
    log_info "Returning to initial directory: $INITIAL_WORKING_DIR"
    cd "$INITIAL_WORKING_DIR" || exit 1
}

#==============================================================================
# SCRIPT DOWNLOAD AND EXECUTION
#==============================================================================

download_and_execute_script() {
    local script_url="$1"
    local script_name="$2"
    shift 2
    local script_options=("$@")
    
    local temp_script_path="${TEMP_SCRIPT_DIR}/${script_name}_$$.sh"
    
    log_info "Downloading $script_name from remote repository..."
    
    if ! curl -fsSL --connect-timeout "$DOWNLOAD_TIMEOUT" "$script_url" -o "$temp_script_path"; then
        log_error "Failed to download $script_name from: $script_url"
        return 1
    fi
    
    if ! validate_downloaded_script "$temp_script_path"; then
        rm -f "$temp_script_path"
        return 1
    fi
    
    chmod +x "$temp_script_path"
    
    log_info "Executing $script_name with options: ${script_options[*]:-none}"
    
    if bash "$temp_script_path" "${script_options[@]}"; then
        log_success "$script_name completed successfully"
        rm -f "$temp_script_path"
        return 0
    else
        local exit_code=$?
        log_error "$script_name failed with exit code: $exit_code"
        rm -f "$temp_script_path"
        return "$exit_code"
    fi
}

#==============================================================================
# INTERACTIVE MENU
#==============================================================================

show_interactive_menu() {
    
    echo "Please select an option:"
    echo
    echo -e "  ${COLOR_GREEN}1)${COLOR_RESET} Full Setup"
    echo "     └─ Run: startup → docker-init → importer"
    echo
    echo -e "  ${COLOR_CYAN}2)${COLOR_RESET} Update Docker Environment"
    echo "     └─ Run: docker-init with -u flag"
    echo
    echo -e "  ${COLOR_YELLOW}0)${COLOR_RESET} Exit"
    echo
    
    local choice
    read -rp "Enter your choice [0-2]: " choice
    echo
    
    case "$choice" in
        1)
            log_info "Selected: Full Setup"
            EXECUTION_MODE="full"
            ;;
        2)
            log_info "Selected: Update Docker Environment"
            EXECUTION_MODE="update"
            
            echo -e "${COLOR_BOLD}Available directories in current path:${COLOR_RESET}"
            echo
            
            if ls -d */ 2>/dev/null | head -10; then
                echo
            else
                log_warning "No directories found in current path"
                echo
            fi
            
            read -rp "Enter path to $PROJECT_FOLDER directory: " UPDATE_TARGET_DIR
            echo
            
            if [[ -z "$UPDATE_TARGET_DIR" ]]; then
                log_error "Directory path cannot be empty"
                exit 1
            fi
            
            if [[ ! -d "$UPDATE_TARGET_DIR" ]]; then
                log_error "Directory does not exist: $UPDATE_TARGET_DIR"
                exit 1
            fi
            
            log_success "Target directory validated: $UPDATE_TARGET_DIR"
            ;;
        0)
            log_info "Exiting..."
            exit 0
            ;;
        *)
            log_error "Invalid choice: $choice"
            exit 1
            ;;
    esac
    
    echo
}

#==============================================================================
# MAIN EXECUTION WORKFLOWS
#==============================================================================

run_full_setup_workflow() {
    log_info "Starting full setup workflow..."
    echo
    
    # Step 1: Execute startup script
    log_step "1/3" "Running startup script"
    download_and_execute_script "$STARTUP_SCRIPT_URL" "startup" "${STARTUP_OPTIONS[@]}"
    echo
    
    # Step 2: Setup Docker environment
    log_step "2/3" "Setting up Docker environment"
    
    create_directory_if_not_exists "$PROJECT_FOLDER"
    change_directory_safely "$PROJECT_FOLDER"
    
    local docker_args=("-y" "$COMPOSE_FILE_URL" "-n" "$NGINX_CONFIG_URL")
    docker_args+=("${DOCKER_INIT_OPTIONS[@]}")
    
    download_and_execute_script "$DOCKER_INIT_SCRIPT_URL" "docker-init" "${docker_args[@]}"
    
    return_to_initial_directory
    echo
    
    # Step 3: Clone repository and run importer
    log_step "3/3" "Running data importer"
    
    if [[ ! -d "$REPOSITORY_FOLDER" ]]; then
        log_info "Cloning repository: $REPOSITORY_URL"
        git clone "$REPOSITORY_URL"
    else
        log_info "Repository already exists, skipping clone"
    fi
    
    change_directory_safely "$REPOSITORY_FOLDER/$SCRIPTS_SUBFOLDER"
    
    log_info "Executing local importer.sh"
    if bash importer.sh "${IMPORTER_OPTIONS[@]}"; then
        log_success "importer.sh completed successfully"
    else
        local exit_code=$?
        log_error "importer.sh failed with exit code: $exit_code"
        return_to_initial_directory
        exit "$exit_code"
    fi
    
    return_to_initial_directory
    echo
    
    log_success "Full setup completed successfully!"
}

run_update_workflow() {
    log_info "Starting update workflow..."
    echo
    
    if [[ ! -d "$UPDATE_TARGET_DIR" ]]; then
        log_error "Target directory does not exist: $UPDATE_TARGET_DIR"
        log_error "Please provide a valid directory path."
        exit 1
    fi
    
    log_step "1/1" "Updating Docker environment in: $UPDATE_TARGET_DIR"
    
    change_directory_safely "$UPDATE_TARGET_DIR"
    
    local docker_args=("-y" "$COMPOSE_FILE_URL" "-u" "-n" "$NGINX_CONFIG_URL")
    docker_args+=("${DOCKER_INIT_OPTIONS[@]}")
    
    download_and_execute_script "$DOCKER_INIT_SCRIPT_URL" "docker-init" "${docker_args[@]}"
    
    return_to_initial_directory
    echo
    
    log_success "Update completed successfully!"
}

#==============================================================================
# ARGUMENT PARSING
#==============================================================================

parse_command_line_arguments() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            # ============================================================
            # Explicit Full Setup Mode
            # ============================================================
            --full)
                EXECUTION_MODE="full"
                shift
                ;;
            
            # ============================================================
            # Update Mode
            # ============================================================
            -u|--update)
                EXECUTION_MODE="update"
                if [[ -z "${2:-}" || "$2" == -* ]]; then
                    log_error "Option -u requires a directory path"
                    exit 1
                fi
                UPDATE_TARGET_DIR="$2"
                shift 2
                ;;
            
            # ============================================================
            # Startup Script Options
            # ============================================================
            --startup-skip-git)
                STARTUP_OPTIONS+=("--skip-git")
                shift
                ;;
            --startup-skip-docker)
                STARTUP_OPTIONS+=("--skip-docker")
                shift
                ;;
            --startup-skip-firewall)
                STARTUP_OPTIONS+=("--skip-firewall")
                shift
                ;;
            --startup-debug)
                STARTUP_OPTIONS+=("--debug")
                shift
                ;;
            
            # ============================================================
            # Docker-Init Script Options
            # ============================================================
            --docker-update)
                DOCKER_INIT_OPTIONS+=("-u")
                shift
                ;;
            --docker-force)
                DOCKER_INIT_OPTIONS+=("-f")
                shift
                ;;
            
            # ============================================================
            # Main Script Options
            # ============================================================
            -h|--help)
                show_help
                exit 0
                ;;
            -v|--version)
                show_version
                exit 0
                ;;
            
            # ============================================================
            # Unknown Option
            # ============================================================
            *)
                log_error "Unknown option: $1"
                echo
                show_help
                exit 1
                ;;
        esac
    done
    
    if [[ "$EXECUTION_MODE" == "update" && -z "$UPDATE_TARGET_DIR" ]]; then
        log_error "Update mode requires a target directory path"
        log_error "Usage: $SCRIPT_NAME -u /path/to/$PROJECT_FOLDER"
        exit 1
    fi
}

#==============================================================================
# HELP AND VERSION DISPLAY
#==============================================================================

show_version() {
    cat << EOF
$SCRIPT_NAME version $SCRIPT_VERSION
Author: $SCRIPT_AUTHOR
EOF
}

show_help() {
    cat << EOF
${COLOR_BOLD}NatiqQuran API Full Setup Script${COLOR_RESET}

${COLOR_BOLD}USAGE:${COLOR_RESET}
    Interactive Menu (default):
        $SCRIPT_NAME

    Full Setup Mode:
        $SCRIPT_NAME --full [startup-options] [docker-options]

    Update Mode:
        $SCRIPT_NAME -u /path/to/$PROJECT_FOLDER [docker-options]

${COLOR_BOLD}MODES:${COLOR_RESET}
    ${COLOR_CYAN}Interactive Menu${COLOR_RESET} (default when no arguments)
        Shows interactive menu to select operation

    ${COLOR_GREEN}Full Setup Mode${COLOR_RESET} (--full)
        Executes complete setup: startup → docker-init → importer

    ${COLOR_YELLOW}Update Mode${COLOR_RESET} (-u)
        Updates existing Docker environment only

${COLOR_BOLD}OPTIONS:${COLOR_RESET}
    ${COLOR_YELLOW}General:${COLOR_RESET}
        -h, --help              Show this help message
        -v, --version           Show version information

    ${COLOR_YELLOW}Execution Mode:${COLOR_RESET}
        --full                  Run full setup (skip interactive menu)
        -u, --update DIR        Run in update mode for specified directory

    ${COLOR_YELLOW}Startup Script:${COLOR_RESET}
        --startup-skip-git      Skip Git installation
        --startup-skip-docker   Skip Docker installation
        --startup-skip-firewall Skip firewall configuration
        --startup-debug         Enable debug mode in startup script

    ${COLOR_YELLOW}Docker-Init Script:${COLOR_RESET}
        --docker-update         Force update mode in docker-init
        --docker-force          Non-interactive mode (CI/CD)

${COLOR_BOLD}EXAMPLES:${COLOR_RESET}
    # Interactive menu (default):
    $SCRIPT_NAME

    # Direct full setup:
    $SCRIPT_NAME --full

    # Full setup with custom options:
    $SCRIPT_NAME --full --startup-skip-firewall

    # Update existing installation:
    $SCRIPT_NAME -u /home/user/$PROJECT_FOLDER

    # CI/CD mode (non-interactive):
    $SCRIPT_NAME --full --startup-skip-git --docker-force

${COLOR_BOLD}WORKFLOW:${COLOR_RESET}
    ${COLOR_CYAN}Interactive Menu:${COLOR_RESET}
        1. Display menu with available options
        2. Execute selected workflow

    ${COLOR_GREEN}Full Setup Mode:${COLOR_RESET}
        1. Execute startup.sh (system preparation)
        2. Create $PROJECT_FOLDER/ and run docker-init.sh
        3. Clone nq-scripts repository and run importer.sh

    ${COLOR_YELLOW}Update Mode:${COLOR_RESET}
        1. Navigate to specified directory
        2. Execute docker-init.sh with update flag
        3. Return to original directory

${COLOR_BOLD}REQUIREMENTS:${COLOR_RESET}
    - curl
    - bash
    - git

${COLOR_BOLD}NOTE:${COLOR_RESET}
    Running without arguments shows an interactive menu.
    Use --full flag for automation/scripts to skip the menu.

For more information, visit: https://github.com/natiq-foundation/quran-api
EOF
}

#==============================================================================
# MAIN ENTRY POINT
#==============================================================================

main() {
    log_info "NatiqQuran API Setup (v$SCRIPT_VERSION)"
    echo
    
    check_dependencies
    echo
    
    if [[ $EUID -ne 0 ]]; then
        log_warning "Some steps may require root privileges. If a step fails, try: sudo $SCRIPT_NAME ..."
        echo
    fi
    
    # If no arguments provided, show interactive menu
    if [[ $# -eq 0 ]]; then
        show_interactive_menu
    else
        # Parse command line arguments
        parse_command_line_arguments "$@"
    fi
    
    # Execute appropriate workflow
    if [[ "$EXECUTION_MODE" == "update" ]]; then
        run_update_workflow
    else
        run_full_setup_workflow
    fi
    
    echo
    log_success "All operations completed successfully!"
}

# Execute main function with all arguments
main "$@"