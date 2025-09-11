#!/bin/bash

# A script to set up and run the NatiqQuran API project.
# It handles Python environment setup, dependency installation, and initial data processing.

set -e

# --- Configuration ---
# Colors for logging
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# --- Logging Functions ---
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- Cleanup ---
# Clean exit on error
cleanup() {
    log_warn "Cleaning up and deactivating virtualenv if active..."
    deactivate 2>/dev/null || true
}
trap cleanup EXIT

# Navigate to the parent directory
cd ..

# --- Prerequisite Checks ---
# Check if python3 is installed
if ! command -v python3 &> /dev/null; then
    log_error "python3 not found. Please install Python 3."
    exit 1
fi

# Function to install python3-venv
install_python_venv() {
    if [ -f /etc/debian_version ]; then
        log_warn "python3-venv not found. Installing for Debian/Ubuntu..."
        sudo apt-get update
        
        # Detect Python version and install the appropriate venv package
        PY_VER=$(python3 -c 'import sys; print(f"python{sys.version_info.major}.{sys.version_info.minor}-venv")')
        sudo apt-get install -y $PY_VER python3-venv
    else
        log_error "python3-venv not found and automatic install is only supported on Debian/Ubuntu. Please install python3-venv manually."
        exit 1
    fi
}

# Check if python3-venv is installed
if ! python3 -m venv --help &> /dev/null; then
    install_python_venv
fi

# --- Virtual Environment Setup ---
# Create virtual environment if it doesn't exist
if [ ! -d ".venv" ]; then
    log_info "Creating virtual environment..."
    
    # Create virtual environment, capturing errors (stderr and stdout)
    venv_output=$(python3 -m venv .venv 2>&1) || {
        # Check if the error is related to ensurepip
        if echo "$venv_output" | grep -q 'ensurepip is not available\|python.*-venv'; then
            log_warn "ensurepip/python3-venv is missing. Installing required packages..."
            install_python_venv
            
            # Remove incomplete .venv and try creating again
            rm -rf .venv
            log_info "Retrying virtual environment creation..."
            if ! python3 -m venv .venv; then
                log_error "Virtual environment creation failed again!"
                exit 1
            fi
        else
            log_error "Virtual environment creation failed!"
            echo "$venv_output"
            exit 1
        fi
    }
else
    log_info "Virtual environment already exists."
fi

# Check if the activate script exists before sourcing
if [ ! -f ".venv/bin/activate" ]; then
    log_error "Virtual environment activation script not found! Recreating..."
    rm -rf .venv
    log_info "Creating virtual environment..."
    
    # Capture stderr to detect ensurepip error
    venv_output=$(python3 -m venv .venv 2>&1) || {
        if echo "$venv_output" | grep -q 'ensurepip is not available\|python.*-venv'; then
            log_warn "ensurepip/python3-venv is missing. Installing required packages..."
            install_python_venv
            
            log_info "Retrying virtual environment creation..."
            if ! python3 -m venv .venv; then
                log_error "Virtual environment creation failed again!"
                exit 1
            fi
        else
            log_error "Failed to create virtual environment!"
            echo "$venv_output"
            exit 1
        fi
    }
fi

# Activate virtual environment
log_info "Activating virtual environment..."
source .venv/bin/activate

# --- Project Setup ---
# Install dependencies
log_info "Installing requirements..."
pip install -r requirements.txt

# --- Data Processing ---
cd parser

# Run parser for mushaf
log_info "Generating mushaf JSON (hafs.json)..."
python3 script.py quran data/quran/quran-uthmani.xml hafs "Hafs an Asem" tanzil --pretty
MUSHAF_GEN_STATUS=$?
if [ $MUSHAF_GEN_STATUS -ne 0 ]; then
    log_error "Mushaf JSON generation failed!"
    exit 1
fi

# Run bulk translation
log_info "Generating bulk translations..."
python3 script.py translation-bulk data/translations/tanzil/ ./translations hafs
TRANS_GEN_STATUS=$?
if [ $TRANS_GEN_STATUS -ne 0 ]; then
    log_error "Bulk translation generation failed!"
    exit 1
fi

cd ../importer

# --- Data Import ---
# Get server information from the user
read -p "Server IP (e.g. http://localhost:8000): " SERVER_IP
read -p "Username: " USERNAME
read -s -p "Password: " PASSWORD
echo

# Login
LOGIN_STATUS=0
log_info "Logging in to server..."
python3 script.py login "$SERVER_IP" "$USERNAME" "$PASSWORD" --non-interactive || LOGIN_STATUS=$?
if [ $LOGIN_STATUS -ne 0 ]; then
    log_error "Login failed!"
    exit 1
fi

# Import mushaf
log_info "Importing mushaf..."
python3 script.py import-mushaf ../parser/hafs.json "$SERVER_IP"
MUSHAF_STATUS=$?
if [ $MUSHAF_STATUS -ne 0 ]; then
    log_error "Importing mushaf failed!"
    exit 1
fi

# Import translations
log_info "Importing translations..."
python3 script.py import-translations ../parser/translations "$SERVER_IP"
TRANS_STATUS=$?
if [ $TRANS_STATUS -ne 0 ]; then
    log_error "Importing translations failed!"
    exit 1
fi

# Create takhtit
read -p "Account UUID (of the Takhtit creator, not the superuser): " ACCOUNT_UUID
log_info "Creating takhtit..."
CREATE_TAKHTIT_STATUS=0
python3 script.py create-takhtit "$ACCOUNT_UUID" "$SERVER_IP" || CREATE_TAKHTIT_STATUS=$?
if [ $CREATE_TAKHTIT_STATUS -ne 0 ]; then
    log_error "Creating takhtit failed!"
    exit 1
fi

# Import page
read -p "Takhtit UUID: " TAKHTIT_UUID
log_info "Importing pages..."
python3 script.py import-takhtit ../parser/data/breakers/ayah_breakers/page.json "page" "$TAKHTIT_UUID" "$SERVER_IP"
PAGES_STATUS=$?
if [ $PAGES_STATUS -ne 0 ]; then
    log_error "Importing pages failed!"
    exit 1
fi

# Import hizb
log_info "Importing hizb..."
python3 script.py import-takhtit ../parser/data/breakers/ayah_breakers/hizb.json "hizb" "$TAKHTIT_UUID" "$SERVER_IP"
HIZB_STATUS=$?
if [ $HIZB_STATUS -ne 0 ]; then
    log_error "Importing hizb failed!"
    exit 1
fi

# Import juz
log_info "Importing juz..."
python3 script.py import-takhtit ../parser/data/breakers/ayah_breakers/juz.json "juz" "$TAKHTIT_UUID" "$SERVER_IP"
JUZ_STATUS=$?
if [ $JUZ_STATUS -ne 0 ]; then
    log_error "Importing juz failed!"
    exit 1
fi

log_success "All operations completed successfully!"

