#!/usr/bin/env bash

# Launch Script
# Description: Handles Git, Docker installation and firewall setup for server
# Version: 0.1
# Author: Natiq dev Team
# Usage: bash startup.sh [OPTIONS]

set -euo pipefail
IFS=$'\n\t'

readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_VERSION="0.1"
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Configuration ---
readonly MIN_DOCKER_VERSION="20.10.0"

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly CYAN='\033[0;36m'
readonly PURPLE='\033[0;35m'
readonly NC='\033[0m'

log_info() { echo -e "${CYAN}ℹ️  $*${NC}" >&2; }
log_success() { echo -e "${GREEN}✅ $*${NC}" >&2; }
log_warning() { echo -e "${YELLOW}⚠️  $*${NC}" >&2; }
log_error() { echo -e "${RED}❌ $*${NC}" >&2; }
log_debug() { [[ "${DEBUG:-0}" == "1" ]] && echo -e "${PURPLE}🐛 $*${NC}" >&2 || true; }

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

check_system() {
    log_info "Checking system requirements..."
    
    [[ -f /etc/os-release ]] || { log_error "Unsupported OS"; return 1; }
    
    [[ $EUID -eq 0 ]] && log_warning "Running as root"
    
    log_success "System requirements OK"
}

check_docker_version() {
    local version
    version=$(docker --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    
    if [[ -z "$version" ]]; then
        return 1
    fi
    
    # Compare versions
    local min_version="$MIN_DOCKER_VERSION"
    local current_version="$version"
    
    # Convert to comparable format (remove dots and compare as integers)
    local min_num=$(echo "$min_version" | tr -d '.')
    local current_num=$(echo "$current_version" | tr -d '.')
    
    [[ $current_num -ge $min_num ]]
}

# Install Git
install_git() {
    log_info "Installing Git..."
    
    if command_exists git; then
        log_success "Git is already installed"
        return 0
    fi
    
    if command_exists apt-get; then
        sudo apt-get update -qq && sudo apt-get install -y git
        log_success "Git installed successfully"
    else
        log_error "Git installation is only supported on Ubuntu/Debian systems"
        return 1
    fi
}

setup_git() {
    local skip_install="$1"
    
    if [[ "$skip_install" == "true" ]]; then
        log_info "Skipping Git installation as requested"
        command_exists git || { log_error "Git not found and --skip-git specified"; return 1; }
    else
        install_git || return 1
    fi
}

# Install Docker using the official script
install_docker() {
    log_info "Installing Docker..."
    command_exists curl || { log_error "curl is required but not found"; return 1; }
    
    local script="/tmp/docker-install.sh"
    curl -fsSL https://get.docker.com -o "$script"
    
    if bash "$script"; then
        rm -f "$script"
        # Add current user to docker group
        if ! groups | grep -q docker; then
            sudo usermod -aG docker "$USER"
            log_warning "User added to docker group. You may need to log out and back in."
        fi
        log_success "Docker installed successfully"
    else
        rm -f "$script"; log_error "Docker installation failed"; return 1
    fi
}

setup_docker() {
    local skip_install="$1"
    
    if [[ "$skip_install" == "true" ]]; then
        log_info "Skipping Docker installation as requested"
        command_exists docker || { log_error "Docker not found and --no-install specified"; return 1; }
    else
        if command_exists docker && check_docker_version; then
            log_success "Docker is already installed and up to date"
        else
            install_docker || return 1
        fi
    fi
}

setup_firewall() {
    log_info "Setting up UFW firewall..."
    
    if ! command_exists ufw; then
        if command_exists apt-get; then
            sudo apt-get update -qq && sudo apt-get install -y ufw
        else
            log_warning "Cannot auto-install UFW. Please install it manually."
            return 1
        fi
    fi

    {
        sudo ufw --force reset
        sudo ufw default deny incoming
        sudo ufw default allow outgoing
        sudo ufw allow ssh
        sudo ufw allow 80/tcp
        sudo ufw allow 443/tcp
        sudo ufw --force enable
    } >/dev/null 2>&1
    
    log_success "UFW configured (SSH, HTTP, HTTPS allowed)"
}

show_help() {
    cat << EOF
Launch Script v${SCRIPT_VERSION}

DESCRIPTION:
    Handles Git, Docker installation and firewall setup for server

USAGE:
    bash ${SCRIPT_NAME} [OPTIONS]

OPTIONS:
    --skip-git          Skip Git installation
    --skip-docker       Skip Docker installation
    --skip-firewall     Skip firewall setup
    --debug             Enable debug mode
    --help, -h          Show this help message
    --version, -v       Show version information

EXAMPLES:
    bash ${SCRIPT_NAME}
    bash ${SCRIPT_NAME} --skip-git
    bash ${SCRIPT_NAME} --skip-firewall
    bash ${SCRIPT_NAME} --skip-docker --skip-firewall
    DEBUG=1 bash ${SCRIPT_NAME} --debug
EOF
}

show_version() {
    echo "Launch Script v${SCRIPT_VERSION}"
}

main() {
    local skip_git="false"
    local skip_docker="false"
    local skip_firewall="false"
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-git) skip_git="true"; shift ;;
            --skip-docker) skip_docker="true"; shift ;;
            --skip-firewall) skip_firewall="true"; shift ;;
            --debug) export DEBUG=1; shift ;;
            --help|-h) show_help; exit 0 ;;
            --version|-v) show_version; exit 0 ;;
            *) log_error "Unknown option: $1"; show_help; exit 1 ;;
        esac
    done
    
    log_info "Starting Launch Script v${SCRIPT_VERSION}"
    
    check_system || return 1
    
    if command_exists apt-get; then 
        sudo apt-get update -qq
    fi
    
    setup_git "$skip_git" || return 1
    setup_docker "$skip_docker" || return 1
    [[ "$skip_firewall" == "false" ]] && { setup_firewall || log_warning "Firewall setup failed"; }
    
    log_success "Launch setup completed successfully!"
    log_info "You can now run the main installer: bash install_quran_api.sh"
}

main "$@"