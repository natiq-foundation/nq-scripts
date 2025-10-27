# NatiqQuran API - Bash Scripts Documentation

<div align="center">

[![License](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Shell](https://img.shields.io/badge/shell-Bash-4EAA25.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/platform-Linux-lightgrey.svg)](https://www.linux.org/)

</div>

---

> **Complete automated deployment system for NatiqQuran API**  
> A production-ready orchestration suite providing end-to-end setup from bare server to running API with imported data.

---

## 📑 Table of Contents

- [Overview](#-overview)
- [Architecture](#-architecture)
- [Quick Start](#-quick-start)
- [Detailed Documentation](#-detailed-documentation)
  - [Setup Script (setup.sh)](#1-setup-script-setupsh)
  - [Startup Script (startup.sh)](#2-startup-script-startupsh)
  - [Docker Init Script (docker_init.sh)](#3-docker-init-script-docker_initsh)
  - [Importer Script (importer.sh)](#4-importer-script-importersh)
- [Workflow](#-workflow)
- [Advanced Usage](#-advanced-usage)
- [Troubleshooting](#-troubleshooting)
- [Security Considerations](#-security-considerations)

---

## 🎯 Overview

This suite provides **four main scripts** that work together to automate the complete NatiqQuran API deployment:

| Script | Purpose | Status |
|--------|---------|--------|
| `setup.sh` | **Orchestrator** - Coordinates all scripts | ✅ Production Ready |
| `startup.sh` | **Server Setup** - Installs Git, Docker, Firewall | ✅ Production Ready |
| `docker_init.sh` | **Docker Setup** - Initializes Compose & .env | ✅ Production Ready |
| `importer.sh` | **Data Import** - Imports Quran data to API | ✅ Production Ready |

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    COMPLETE DEPLOYMENT FLOW                   │
└─────────────────────────────────────────────────────────────┘

[setup.sh]
    │
    ├─► [startup.sh]
    │       ├─► Install Git
    │       ├─► Install Docker (v20.10+)
    │       └─► Configure UFW Firewall
    │
    ├─► [docker_init.sh]
    │       ├─► Fetch docker-compose.yaml
    │       ├─► Extract environment variables
    │       ├─► Generate .env file
    │       └─► Start Docker Compose
    │
    └─► [importer.sh]
            ├─► Create Python venv
            ├─► Process XML data → JSON
            ├─► Import Mushaf & Translations
            └─► Import Takhtit (Pages, Hizb, Juz)

```

---

## 🚀 Quick Start

### Prerequisites

| Component | Requirement | Check Command |
|-----------|-------------|---------------|
| **OS** | Ubuntu 18.04+ / Debian 9+ | `cat /etc/os-release` |
| **RAM** | 4GB minimum | `free -h` |
| **Storage** | 10GB free | `df -h` |
| **Network** | Internet connection | `curl -I google.com` |
| **Tools** | `curl`, `bash 4.0+`, `sudo` | `which curl bash` |

### One-Command Setup

```bash
# Download and execute the complete setup
curl -fsSL https://raw.githubusercontent.com/natiq-foundation/nq-scripts/main/bash_scripts/setup.sh | bash
```

This single command will:
1. ✅ Install Git, Docker, and configure firewall
2. ✅ Download and setup Docker Compose
3. ✅ Generate environment files
4. ✅ Start the API containers
5. ✅ Process and import Quran data

---

## 📖 Detailed Documentation

### 1. Setup Script (`setup.sh`)

**Role**: Master orchestrator that coordinates all scripts in sequence

#### Features

- ✅ **Full Setup Mode**: Complete deployment from scratch
- ✅ **Update Mode**: Update existing Docker environment
- ✅ **Remote Script Execution**: Downloads and executes scripts from GitHub
- ✅ **Validation**: Basic script validation before execution
- ✅ **Root Warning**: Warns if not running as root
- ✅ **Comprehensive Error Handling**: Graceful failure with cleanup

#### Usage

```bash
# Full setup (runs all three scripts in sequence)
bash setup.sh

# Full setup with custom options
bash setup.sh --startup-skip-firewall --docker-force

# Update existing installation
bash setup.sh -u /path/to/quran-api

# Show help
bash setup.sh -h
```

#### Command Line Options

| Option | Description |
|--------|-------------|
| `-u, --update DIR` | Run in update mode for specified directory |
| `--startup-skip-git` | Skip Git installation in startup.sh |
| `--startup-skip-docker` | Skip Docker installation in startup.sh |
| `--startup-skip-firewall` | Skip firewall setup in startup.sh |
| `--startup-debug` | Enable debug mode |
| `--docker-update` | Force update mode in docker-init |
| `--docker-force` | Non-interactive mode (CI/CD) |
| `-h, --help` | Show help message |
| `-v, --version` | Show version information |

#### Execution Flow

```
┌─────────────────┐
│  setup.sh       │
└────────┬────────┘
         │
         ├─► Check dependencies (curl, bash)
         │
         ├─► [Full Setup Mode]
         │       ├─► Execute startup.sh
         │       │       └─► Install Git, Docker, UFW
         │       │
         │       ├─► Execute docker_init.sh
         │       │       ├─► Fetch compose file
         │       │       ├─► Generate .env
         │       │       └─► Start containers
         │       │
         │       └─► Execute importer.sh
         │               ├─► Setup Python venv
         │               ├─► Process data
         │               └─► Import to API
         │
         └─► [Update Mode]
                 └─► Execute docker_init.sh in update mode
```

#### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 127 | Missing dependency |

---

### 2. Startup Script (`startup.sh`)

**Role**: Server preparation - Installs essential tools

#### Features

- ✅ **Git Installation**: Automatic for Ubuntu/Debian
- ✅ **Docker Installation**: Official Docker installation script
- ✅ **Docker Version Check**: Ensures minimum v20.10.0
- ✅ **Firewall Setup**: UFW configuration (SSH, HTTP, HTTPS)
- ✅ **Root Detection**: Warns if running as root
- ✅ **Skip Options**: Can skip individual components

#### Usage

```bash
# Full setup (Git + Docker + Firewall)
bash startup.sh

# Skip firewall configuration
bash startup.sh --skip-firewall

# Skip everything except Docker
bash startup.sh --skip-git --skip-firewall

# Debug mode
DEBUG=1 bash startup.sh --debug
```

#### Command Line Options

| Option | Description |
|--------|-------------|
| `--skip-git` | Skip Git installation |
| `--skip-docker` | Skip Docker installation |
| `--skip-firewall` | Skip UFW firewall setup |
| `--debug` | Enable debug mode |
| `-h, --help` | Show help |
| `-v, --version` | Show version |

#### Docker Version Requirements

- **Minimum**: Docker 20.10.0
- **Check**: Script verifies version before proceeding
- **Installation**: Uses official `get.docker.com` script

#### Firewall Rules

The script configures UFW with these rules:

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow ssh        # SSH access
ufw allow 80/tcp     # HTTP
ufw allow 443/tcp    # HTTPS
```

**Warning**: Existing UFW rules will be **reset** by this script.

#### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Error |

---

### 3. Docker Init Script (`docker_init.sh`)

**Role**: Docker Compose initialization and .env generation

#### Features

- ✅ **Smart Variable Extraction**: Parses docker-compose.yaml for variables
- ✅ **Secure Download**: HTTPS with TLS 1.2, retry logic
- ✅ **YAML Validation**: Syntax checking with yamllint/Python
- ✅ **Interactive Editor**: Opens .env for editing
- ✅ **Compose Detection**: Supports both v1 and v2
- ✅ **Non-Interactive Mode**: CI/CD compatible
- ✅ **Temp File Management**: Automatic cleanup on exit

#### Usage

```bash
# Basic usage (download compose from URL)
bash docker_init.sh -y https://example.com/docker-compose.yaml

# With nginx config
bash docker_init.sh -y compose.yaml -n nginx.conf

# Force update mode
bash docker_init.sh -u -y compose.yaml

# Non-interactive (CI/CD)
bash docker_init.sh -f -y compose.yaml

# Custom .env filename
bash docker_init.sh -y compose.yaml -e .env.prod
```

#### Command Line Options

| Option | Description | Required |
|--------|-------------|----------|
| `-y <file\|url>` | Docker Compose file/URL | ✅ Yes |
| `-n <file\|url>` | Nginx config (optional) | ❌ No |
| `-e <filename>` | Output .env filename | ❌ No (default: .env) |
| `-u` | Pull latest images | ❌ No |
| `-f` | Force yes (non-interactive) | ❌ No |
| `-l <logfile>` | Write logs to file | ❌ No |
| `-h` | Show help | ❌ No |

#### Variable Extraction

The script intelligently extracts these patterns from docker-compose.yaml:

```yaml
# Examples that get extracted:
environment:
  - POSTGRES_USER=${DB_USER:-admin}        # → DB_USER=admin
  - POSTGRES_PASS=${DB_PASS}                # → # REQUIRED: DB_PASS=
  - API_KEY=${API_KEY:=default123}          # → API_KEY=default123
  - ERROR_MSG=${VAR?Missing variable}      # → # REQUIRED: VAR= # Error message
```

#### Generated .env Format

```bash
# Environment variables for docker-compose
# Generated by docker-compose-init v2.0.0
# Date: 2024-01-15 10:30:00 UTC
# Source: docker-compose.yaml

# Variables with defaults
DB_USER=admin
DB_PASS=secretpass123

# Required variables (must be filled)
# REQUIRED: API_KEY=
# REQUIRED: SECRET_KEY=
```

#### Execution Flow

```
┌──────────────────────┐
│  docker_init.sh      │
└──────────┬───────────┘
           │
           ├─► Parse arguments
           ├─► Check dependencies
           │
           ├─► Retrieve docker-compose.yaml
           │       └─► Validate YAML syntax
           │
           ├─► Retrieve nginx.conf (if provided)
           │
           ├─► Generate .env file
           │       ├─► Extract variables
           │       ├─► Open in editor (optional)
           │       └─► Validate entries
           │
           └─► Start Docker Compose
                   ├─► Detect compose command (v1/v2)
                   ├─► Pull images (if -u flag)
                   └─► Start containers
```

#### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | General error |
| 64 | Invalid input |
| 65 | File not found |
| 69 | Download failed |
| 70 | Docker not available |
| 71 | Validation failed |
| 127 | Missing dependencies |
| 130 | Interrupted by user |

---

### 4. Importer Script (`importer.sh`)

**Role**: Data processing and API import

#### Features

- ✅ **Auto Python Setup**: Installs python3-venv if missing
- ✅ **Virtual Environment**: Automatic venv creation
- ✅ **Data Processing**: Converts XML to JSON
- ✅ **Secure Login**: Password input with `-s` flag
- ✅ **Comprehensive Import**: Mushaf, translations, takhtit
- ✅ **Error Handling**: Step-by-step validation

#### Usage

```bash
# Standard execution
bash importer.sh
```

**Note**: This script requires user interaction for server credentials.

#### Data Sources

The script processes these files:

| File | Source Path | Type |
|------|-------------|------|
| Page data | `parser/data/breakers/ayah_breakers/page.json` | JSON |
| Hizb data | `parser/data/breakers/ayah_breakers/hizb.json` | JSON |
| Juz data | `parser/data/breakers/ayah_breakers/juz.json` | JSON |
| Quran XML | `parser/data/quran/quran-uthmani.xml` | XML |
| Translations | `parser/data/translations/tanzil/` | XML |

#### User Inputs

During execution, the script will prompt for:

```bash
Server IP (e.g. http://localhost:8000): http://localhost:8000
Username: admin
Password: [hidden]
```

#### Execution Flow

```
┌──────────────────┐
│  importer.sh     │
└────────┬─────────┘
         │
         ├─► Check Python 3
         ├─► Install python3-venv (if needed)
         │
         ├─► Create .venv/
         ├─► Activate virtual environment
         ├─► Install requirements.txt
         │
         ├─► cd parser/
         │   ├─► Generate hafs.json (Quran text)
         │   └─► Generate bulk translations
         │
         ├─► cd importer/
         │   ├─► Prompt for server credentials
         │   ├─► Login to API
         │   ├─► Import mushaf
         │   ├─► Import translations
         │   ├─► Create takhtit
         │   ├─► Import pages
         │   ├─► Import hizb
         │   └─► Import juz
         │
         └─► Cleanup
```

#### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Error |

---

## 🔄 Workflow

### Complete Deployment Workflow

```
┌─────────────────────────────────────────────────────────────────┐
│                    PHASE 1: SERVER PREPARATION                    │
└─────────────────────────────────────────────────────────────────┘

User runs: bash setup.sh

┌──────────────────┐
│  startup.sh      │
│                  │
│  ✓ Check system  │
│  ✓ Install Git   │
│  ✓ Install Docker│
│  ✓ Setup UFW     │
└──────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                  PHASE 2: DOCKER ENVIRONMENT                      │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────────┐
│  docker_init.sh      │
│                      │
│  ✓ Fetch compose     │
│  ✓ Extract vars      │
│  ✓ Generate .env     │
│  ✓ Start containers  │
└──────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                      PHASE 3: DATA IMPORT                         │
└─────────────────────────────────────────────────────────────────┘

┌──────────────────┐
│  importer.sh     │
│                  │
│  ✓ Setup Python  │
│  ✓ Process data  │
│  ✓ Import to API │
└──────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                         DEPLOYMENT COMPLETE                       │
└─────────────────────────────────────────────────────────────────┘
```

---

## 🔧 Advanced Usage

### Custom Docker Compose Sources

```bash
# From local file
bash docker_init.sh -y ./docker-compose.yaml

# From URL
bash docker_init.sh -y https://raw.githubusercontent.com/org/repo/main/compose.yaml

# With nginx config
bash docker_init.sh -y compose.yaml -n https://example.com/nginx.conf
```

### CI/CD Integration

```bash
# Non-interactive setup script
bash setup.sh \
  --startup-skip-git \
  --startup-skip-firewall \
  --docker-force

# Non-interactive docker init
bash docker_init.sh -f -y compose.yaml -u
```

### Logging to File

```bash
# Log all output to file
bash docker_init.sh -l /var/log/docker-init.log -y compose.yaml
```

### Update Existing Installation

```bash
# Update Docker environment only
bash setup.sh -u /home/user/quran-api
```

---

## 🐛 Troubleshooting

### Common Issues

#### Issue: "Docker not found"

**Cause**: Docker daemon not running or user not in docker group

**Solution**:
```bash
# Check Docker status
sudo systemctl status docker

# Start Docker
sudo systemctl start docker

# Add user to docker group (then logout/login)
sudo usermod -aG docker $USER
```

#### Issue: "python3-venv not available"

**Cause**: python3-venv package not installed

**Solution**:
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install python3.11-venv python3-venv

# Or let importer.sh install it automatically
```

#### Issue: "Download failed"

**Cause**: Network issues or invalid URL

**Solution**:
```bash
# Check network connectivity
curl -I https://raw.githubusercontent.com/

# Verify URL is accessible
curl -f https://your-compose-url.yaml

# Check firewall
sudo ufw status
```

#### Issue: "YAML validation failed"

**Cause**: Invalid docker-compose.yaml syntax

**Solution**:
```bash
# Validate YAML manually
yamllint docker-compose.yaml

# Or with Python
python3 -c "import yaml; yaml.safe_load(open('docker-compose.yaml'))"
```

#### Issue: "Login failed" (importer.sh)

**Cause**: Wrong credentials or API not accessible

**Solution**:
```bash
# Verify API is running
curl http://localhost:8000/health

# Check credentials
python3 -c "
import requests
r = requests.post('http://localhost:8000/api/auth/login', 
                  json={'username': 'admin', 'password': 'password'})
print(r.status_code)
"
```

### Debug Mode

Enable debug output:

```bash
# For startup.sh
DEBUG=1 bash startup.sh --debug

# For setup.sh (if available)
bash setup.sh --startup-debug
```

### Manual Cleanup

If scripts fail mid-execution:

```bash
# Clean up Docker resources
docker compose down -v

# Remove virtual environment
rm -rf .venv

# Remove generated files
rm -f docker-compose.yaml .env nginx.conf

# Remove temp files
rm -f /tmp/*.sh
```

---

## 🔐 Security Considerations

### File Permissions

The scripts automatically set secure permissions on sensitive files:

```bash
# .env file permissions (600 = owner read/write only)
chmod 600 .env
```

### Password Handling

**Security Warning**: Passwords entered in `importer.sh` are temporarily stored in shell variables.

**Best Practices**:
- Use environment variables when possible
- Clear shell history after use: `history -c`
- Use `unset PASSWORD` after script completion

### Firewall Rules

The `startup.sh` script configures UFW with restrictive rules:

```bash
# Only these ports are open:
- 22/tcp  (SSH)
- 80/tcp  (HTTP)
- 443/tcp (HTTPS)
```

**Custom Ports**: If you need additional ports, configure manually:

```bash
sudo ufw allow 8000/tcp  # Example: Django dev server
```

### HTTPS vs HTTP

The `docker_init.sh` script warns about non-HTTPS URLs:

```bash
# HTTPS is preferred
bash docker_init.sh -y https://secure.example.com/compose.yaml

# HTTP will prompt for confirmation
bash docker_init.sh -y http://example.com/compose.yaml
```

---

## 📝 Additional Resources

- [Docker Compose Documentation](https://docs.docker.com/compose/)
- [UFW Firewall Guide](https://help.ubuntu.com/community/UFW)
- [Python Virtual Environments](https://docs.python.org/3/tutorial/venv.html)

---

## 🤝 Contributing

To contribute to these scripts:

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly on a clean Ubuntu/Debian system
5. Submit a pull request

---

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 👥 Support

For issues, questions, or contributions:

- **GitHub Issues**: [Create an issue](https://github.com/natiq-foundation/nq-scripts/issues)
- **Documentation**: See individual script headers for detailed information

---

<div align="center">

**Built with ❤️ for the NatiqQuran project**

</div>
