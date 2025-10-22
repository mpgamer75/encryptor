#!/bin/bash

# Encryptor Installation Script - v2.0.0
set -e

# Colors
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

# Constants
VERSION="2.0.0"
SCRIPT_NAME="encryptor.sh"
BINARY_NAME="encryptor"
GITHUB_URL="https://raw.githubusercontent.com/mpgamer75/encryptor/main"

print_header() {
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
    ______                             __            
   / ____/___  ____________  ______  / /_____  _____
  / __/ / __ \/ ___/ ___/ / / / __ \/ __/ __ \/ ___/
 / /___/ / / / /__/ /  / /_/ / /_/ / /_/ /_/ / /    
/_____/_/ /_/\___/_/   \__, / .___/\__/\____/_/     
                      /____/_/                       
EOF
    echo -e "${RESET}"
    echo -e "${GREEN}${BOLD}                   Encryptor Installer v$VERSION${RESET}"
    echo -e "${BLUE}                      Advanced File Encryption${RESET}"
    echo
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${RESET}"
    echo
}

detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        OS_NAME="$ID"
        OS_VERSION="$VERSION_ID"
    elif [[ "$OSTYPE" == "darwin"* ]]; then
        OS_NAME="macos"
        OS_VERSION=$(sw_vers -productVersion 2>/dev/null || echo "unknown")
    else
        OS_NAME="unknown"
        OS_VERSION="unknown"
    fi
}

check_openssl_capabilities() {
    local ssl_version="$1"
    local has_cms=0
    local has_aead=0
    
    # Test CMS support
    if openssl cms -help 2>&1 | grep -q "encrypt" 2>/dev/null; then
        has_cms=1
    fi
    
    # Test AEAD support (check if ciphers command lists AEAD ciphers)
    if openssl enc -ciphers 2>/dev/null | grep -q "aes-256-gcm\|chacha20-poly1305" 2>/dev/null; then
        has_aead=1
    fi
    
    echo "$has_cms:$has_aead"
}

suggest_openssl_upgrade() {
    local ssl_version="$1"
    
    echo
    echo -e "${YELLOW}${BOLD}⚠️  OpenSSL Upgrade Recommended${RESET}"
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo
    echo -e "${BLUE}Current version:${RESET} OpenSSL $ssl_version"
    echo -e "${BLUE}Recommended:${RESET}     OpenSSL 1.1.1+ or 3.x"
    echo
    echo -e "${CYAN}${BOLD}Why upgrade?${RESET}"
    echo -e "  ${GREEN}✓${RESET} Modern AEAD ciphers (AES-256-GCM, ChaCha20-Poly1305)"
    echo -e "  ${GREEN}✓${RESET} Enhanced security features"
    echo -e "  ${GREEN}✓${RESET} Better performance with hardware acceleration"
    echo -e "  ${GREEN}✓${RESET} Full CMS (Cryptographic Message Syntax) support"
    echo
    echo -e "${CYAN}${BOLD}Without upgrade:${RESET}"
    echo -e "  ${YELLOW}→${RESET} Encryptor will use AES-256-CBC (still very secure)"
    echo -e "  ${YELLOW}→${RESET} Some modern encryption modes unavailable"
    echo
    
    case "$OS_NAME" in
        ubuntu|debian)
            local version_major="${OS_VERSION%%.*}"
            echo -e "${CYAN}${BOLD}Upgrade instructions for Ubuntu/Debian:${RESET}"
            
            if [[ "$OS_NAME" == "ubuntu" ]] && [[ "$version_major" -ge 20 ]] || [[ "$OS_NAME" == "debian" ]] && [[ "$version_major" -ge 11 ]]; then
                echo -e "${BOLD}sudo apt update${RESET}"
                echo -e "${BOLD}sudo apt install --upgrade openssl libssl-dev${RESET}"
            else
                echo -e "${YELLOW}Your OS version may have older OpenSSL in repositories.${RESET}"
                echo -e "${BOLD}sudo apt update${RESET}"
                echo -e "${BOLD}sudo apt install --upgrade openssl${RESET}"
                echo
                echo -e "${DIM}Or compile from source:${RESET}"
                echo -e "${BOLD}wget https://www.openssl.org/source/openssl-3.0.12.tar.gz${RESET}"
                echo -e "${BOLD}tar -xzf openssl-3.0.12.tar.gz${RESET}"
                echo -e "${BOLD}cd openssl-3.0.12${RESET}"
                echo -e "${BOLD}./config --prefix=/usr/local/ssl --openssldir=/usr/local/ssl shared zlib${RESET}"
                echo -e "${BOLD}make -j\$(nproc)${RESET}"
                echo -e "${BOLD}sudo make install${RESET}"
            fi
            ;;
        
        centos|rhel|fedora|rocky|almalinux)
            echo -e "${CYAN}${BOLD}Upgrade instructions for CentOS/RHEL/Fedora:${RESET}"
            if [[ "$OS_NAME" == "fedora" ]]; then
                echo -e "${BOLD}sudo dnf update openssl openssl-libs${RESET}"
            else
                local version_major="${OS_VERSION%%.*}"
                if [[ "$version_major" -ge 8 ]]; then
                    echo -e "${BOLD}sudo dnf update openssl openssl-libs${RESET}"
                else
                    echo -e "${BOLD}sudo yum update openssl openssl-libs${RESET}"
                    echo
                    echo -e "${YELLOW}Note: RHEL/CentOS 7 has OpenSSL 1.0.2 by default.${RESET}"
                    echo -e "${YELLOW}Consider upgrading to RHEL/CentOS 8+ for modern OpenSSL.${RESET}"
                fi
            fi
            ;;
        
        arch|manjaro)
            echo -e "${CYAN}${BOLD}Upgrade instructions for Arch Linux:${RESET}"
            echo -e "${BOLD}sudo pacman -Syu openssl${RESET}"
            ;;
        
        opensuse*|sles)
            echo -e "${CYAN}${BOLD}Upgrade instructions for openSUSE/SLES:${RESET}"
            echo -e "${BOLD}sudo zypper update openssl libopenssl${RESET}"
            ;;
        
        macos)
            echo -e "${CYAN}${BOLD}Upgrade instructions for macOS:${RESET}"
            if command -v brew >/dev/null 2>&1; then
                echo -e "${BOLD}brew update${RESET}"
                echo -e "${BOLD}brew install openssl@3${RESET}"
                echo -e "${BOLD}brew link --force openssl@3${RESET}"
                echo
                echo -e "${YELLOW}Note: You may need to update your PATH:${RESET}"
                echo -e "${BOLD}echo 'export PATH=\"/usr/local/opt/openssl@3/bin:\$PATH\"' >> ~/.zshrc${RESET}"
                echo -e "${BOLD}source ~/.zshrc${RESET}"
            else
                echo -e "${YELLOW}Homebrew not found. Install it first:${RESET}"
                echo -e "${BOLD}/bin/bash -c \"\$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"${RESET}"
            fi
            ;;
        
        *)
            echo -e "${CYAN}${BOLD}Generic upgrade instructions:${RESET}"
            echo -e "${YELLOW}Use your distribution's package manager to upgrade OpenSSL${RESET}"
            echo
            echo -e "${DIM}Or compile from source:${RESET}"
            echo -e "${BOLD}wget https://www.openssl.org/source/openssl-3.0.12.tar.gz${RESET}"
            echo -e "${BOLD}tar -xzf openssl-3.0.12.tar.gz && cd openssl-3.0.12${RESET}"
            echo -e "${BOLD}./config && make -j\$(nproc) && sudo make install${RESET}"
            ;;
    esac
    
    echo
    echo -e "${CYAN}${BOLD}Continue installation anyway?${RESET}"
    echo -e "${YELLOW}Encryptor will work with fallback to AES-256-CBC${RESET}"
    echo -en "${BOLD}[Y/n]: ${RESET}"
    read -r response
    
    if [[ "$response" =~ ^[Nn]$ ]]; then
        echo -e "${BLUE}Installation cancelled. Upgrade OpenSSL and run installer again.${RESET}"
        exit 0
    fi
    
    echo -e "${GREEN}Continuing installation...${RESET}"
    echo
}

check_requirements() {
    echo -e "${BLUE}Checking system requirements...${RESET}"
    local missing_pkg=0
    
    # Detect distribution
    detect_distro
    echo -e "${DIM}Detected OS: $OS_NAME $OS_VERSION${RESET}"
    
    # Check Bash
    if ! command -v bash >/dev/null 2>&1; then
        echo -e "${RED}Error: Bash not found${RESET}"
        missing_pkg=1
    else
        bash_version=$(bash --version | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1)
        echo -e "${GREEN}✅ Bash $bash_version detected${RESET}"
    fi
    
    # Check OpenSSL with detailed capabilities
    if ! command -v openssl >/dev/null 2>&1; then
        echo -e "${RED}❌ Error: OpenSSL not found${RESET}"
        missing_pkg=1
    else
        ssl_version=$(openssl version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
        local major=$(echo "$ssl_version" | cut -d. -f1)
        local minor=$(echo "$ssl_version" | cut -d. -f2)
        
        # Check capabilities
        local capabilities=$(check_openssl_capabilities "$ssl_version")
        local has_cms=$(echo "$capabilities" | cut -d: -f1)
        local has_aead=$(echo "$capabilities" | cut -d: -f2)
        
        echo -e "${GREEN}✅ OpenSSL $ssl_version detected${RESET}"
        
        # Display capabilities
        if [[ "$has_cms" -eq 1 ]]; then
            echo -e "   ${GREEN}✓${RESET} ${DIM}CMS (Cryptographic Message Syntax) supported${RESET}"
        else
            echo -e "   ${YELLOW}○${RESET} ${DIM}CMS not available${RESET}"
        fi
        
        # Check version and suggest upgrade
        local needs_upgrade=0
        if [[ "$major" -lt 1 ]] || [[ "$major" -eq 1 && "$minor" -eq 0 ]]; then
            needs_upgrade=1
            echo -e "   ${YELLOW}⚠${RESET}  ${DIM}Modern AEAD ciphers not fully supported${RESET}"
        elif [[ "$major" -eq 1 && "$minor" -eq 1 ]]; then
            echo -e "   ${GREEN}✓${RESET} ${DIM}AEAD ciphers supported (OpenSSL 1.1.x)${RESET}"
        else
            echo -e "   ${GREEN}✓${RESET} ${DIM}Full modern cryptography support (OpenSSL $major.x)${RESET}"
        fi
        
        # Suggest upgrade if old version
        if [[ "$needs_upgrade" -eq 1 ]]; then
            suggest_openssl_upgrade "$ssl_version"
        fi
    fi
    
    # Check Git (for testssl.sh)
    if ! command -v git >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  'git' not found (required for audit tools)${RESET}"
        echo -e "${DIM}   Security audit features will be unavailable${RESET}"
    else
        echo -e "${GREEN}✅ 'git' detected${RESET}"
    fi
    
    # Check numfmt (coreutils)
    if ! command -v numfmt >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  'numfmt' not found (part of coreutils)${RESET}"
        echo -e "${DIM}   File size formatting will be basic${RESET}"
    else
        echo -e "${GREEN}✅ 'numfmt' detected${RESET}"
    fi
    
    # Check less
    if ! command -v less >/dev/null 2>&1; then
        echo -e "${YELLOW}⚠️  'less' not found (for viewing logs)${RESET}"
        echo -e "${DIM}   Log viewing with 'cat' fallback${RESET}"
    else
        echo -e "${GREEN}✅ 'less' detected${RESET}"
    fi
    
    if [[ $missing_pkg -ne 0 ]]; then
        echo
        echo -e "${RED}${BOLD}Critical packages missing!${RESET}"
        echo -e "${YELLOW}Please install required packages:${RESET}"
        echo
        case "$OS_NAME" in
            ubuntu|debian)
                echo -e "  ${BOLD}sudo apt update${RESET}"
                echo -e "  ${BOLD}sudo apt install bash openssl git coreutils less${RESET}"
                ;;
            centos|rhel|fedora|rocky|almalinux)
                if [[ "$OS_NAME" == "fedora" ]] || [[ "${OS_VERSION%%.*}" -ge 8 ]]; then
                    echo -e "  ${BOLD}sudo dnf install bash openssl git coreutils less${RESET}"
                else
                    echo -e "  ${BOLD}sudo yum install bash openssl git coreutils less${RESET}"
                fi
                ;;
            arch|manjaro)
                echo -e "  ${BOLD}sudo pacman -S bash openssl git coreutils less${RESET}"
                ;;
            opensuse*|sles)
                echo -e "  ${BOLD}sudo zypper install bash openssl git coreutils less${RESET}"
                ;;
            macos)
                echo -e "  ${BOLD}brew install bash openssl git coreutils less${RESET}"
                ;;
            *)
                echo -e "  ${BOLD}Use your package manager to install: bash openssl git coreutils less${RESET}"
                ;;
        esac
        exit 1
    fi
    echo
}

detect_shell() {
    user_shell=$(basename "${SHELL:-bash}")
    config_file=""
    
    echo -e "${BLUE}Detecting shell configuration...${RESET}"
    
    case "$user_shell" in
        "zsh")
            config_file="$HOME/.zshrc"
            ;;
        "bash")
            if [[ -f "$HOME/.bashrc" ]]; then
                config_file="$HOME/.bashrc"
            elif [[ -f "$HOME/.bash_profile" ]]; then
                config_file="$HOME/.bash_profile"
            else
                config_file="$HOME/.bashrc" # Default
            fi
            ;;
        "fish")
            config_file="$HOME/.config/fish/config.fish"
            ;;
        *)
            config_file="$HOME/.profile" # Fallback
            ;;
    esac
    
    echo -e "${GREEN}✅ Shell: ${BOLD}$user_shell${RESET}"
    echo -e "${BLUE}Config file: ${BOLD}$config_file${RESET}"
    echo
}

download_script() {
    echo -e "${BLUE}Downloading Encryptor...${RESET}"
    
    if [[ -f "$SCRIPT_NAME" ]]; then
        echo -e "${GREEN}✅ Found local $SCRIPT_NAME${RESET}"
        return 0
    fi
    
    if command -v curl >/dev/null 2>&1; then
        if curl -fsSL "$GITHUB_URL/$SCRIPT_NAME" -o "$SCRIPT_NAME"; then
            echo -e "${GREEN}✅ Download completed with curl${RESET}"
        else
            echo -e "${RED}Download failed with curl${RESET}"
            exit 1
        fi
    elif command -v wget >/dev/null 2>&1; then
        if wget -q "$GITHUB_URL/$SCRIPT_NAME" -O "$SCRIPT_NAME"; then
            echo -e "${GREEN}✅ Download completed with wget${RESET}"
        else
            echo -e "${RED}Download failed with wget${RESET}"
            exit 1
        fi
    else
        echo -e "${RED}Error: Neither curl nor wget found${RESET}"
        echo -e "${YELLOW}Please install curl or wget, or download manually${RESET}"
        exit 1
    fi
    
    if [[ ! -s "$SCRIPT_NAME" ]]; then
        echo -e "${RED}Downloaded file is empty${RESET}"
        exit 1
    fi
    echo
}

install_encryptor() {
    install_dir=""
    needs_path_config=false
    
    # Determine installation directory
    if [[ $EUID -eq 0 ]]; then
        install_dir="/usr/local/bin"
        echo -e "${GREEN}Installing system-wide in $install_dir${RESET}"
    else
        # Try system directory first if writable
        if [[ -w "/usr/local/bin" ]]; then
            install_dir="/usr/local/bin"
            echo -e "${GREEN}Installing system-wide in $install_dir (writable)${RESET}"
        else
            # Fall back to user directory
            install_dir="$HOME/.local/bin"
            needs_path_config=true
            echo -e "${GREEN}Installing for current user in $install_dir${RESET}"
            
            # Create user bin directory if it doesn't exist
            if [[ ! -d "$install_dir" ]]; then
                mkdir -p "$install_dir"
                echo -e "${YELLOW}Created directory: $install_dir${RESET}"
            fi
        fi
    fi
    
    # Copy and make executable
    if cp "$SCRIPT_NAME" "$install_dir/$BINARY_NAME"; then
        chmod +x "$install_dir/$BINARY_NAME"
        echo -e "${GREEN}✅ Installation successful!${RESET}"
    else
        echo -e "${RED}Installation failed${RESET}"
        echo -e "${YELLOW}If installing to $HOME/.local/bin, no sudo is needed.${RESET}"
        echo -e "${YELLOW}If installing to /usr/local/bin, you may need to re-run with 'sudo'${RESET}"
        exit 1
    fi
    
    # Configure PATH if needed
    if [[ "$needs_path_config" == true ]]; then
        configure_path "$install_dir"
    fi
}

configure_path() {
    local install_dir="$1"
    
    echo -e "${BLUE}Configuring PATH...${RESET}"
    
    # Check if PATH already configured
    if [[ ":$PATH:" == *":$install_dir:"* ]]; then
        echo -e "${GREEN}✅ PATH already configured correctly${RESET}"
        return 0
    fi
    
    # Create config file if it doesn't exist
    if [[ ! -f "$config_file" ]]; then
        echo -e "${YELLOW}Creating config file: $config_file${RESET}"
        # Create directory for fish config if needed
        if [[ "$user_shell" == "fish" ]]; then
            mkdir -p "$(dirname "$config_file")"
        fi
        touch "$config_file"
    fi
    
    # Check if PATH export already exists
    local path_exists=false
    case "$user_shell" in
        "fish")
            if grep -q "set -gx PATH.*\.local/bin" "$config_file" 2>/dev/null; then
                path_exists=true
            fi
            ;;
        *)
            if grep -q 'export PATH.*\.local/bin' "$config_file" 2>/dev/null; then
                path_exists=true
            fi
            ;;
    esac
    
    # Add PATH configuration if not exists
    if [[ "$path_exists" == false ]]; then
        echo "" >> "$config_file"
        echo "# Added by Encryptor installer" >> "$config_file"
        
        case "$user_shell" in
            "fish")
                echo "set -gx PATH \$HOME/.local/bin \$PATH" >> "$config_file"
                ;;
            *)
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$config_file"
                ;;
        esac
        
        echo -e "${GREEN}✅ PATH configured in $config_file${RESET}"
    else
        echo -e "${YELLOW}PATH configuration already exists in $config_file${RESET}"
    fi
    
    # Update current session PATH
    export PATH="$install_dir:$PATH"
    echo -e "${GREEN}✅ PATH updated for current session${RESET}"
}

print_success() {
    echo
    echo -e "${GREEN}${BOLD}Installation Complete!${RESET}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo
    
    if command -v "$BINARY_NAME" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Encryptor is ready to use!${RESET}"
        echo -e "${BOLD}  encryptor${RESET}          # Launch interactive menu"
        echo -e "${BOLD}  encryptor --help${RESET}   # Show help information"
    else
        echo -e "${YELLOW}Manual step required:${RESET}"
        echo -e "${BOLD}Restart your terminal${RESET} or run:"
        
        case "$user_shell" in
            "fish")
                echo -e "${BOLD}  exec fish${RESET}"
                ;;
            *)
                echo -e "${BOLD}  source $config_file${RESET}"
                ;;
        esac
        
        echo
        echo -e "${BLUE}Or use the full path:${RESET}"
        echo -e "${BOLD}  ~/.local/bin/encryptor${RESET}"
    fi
    
    echo
    echo -e "${GREEN}Thank you for installing Encryptor!${RESET}"
    echo
}

# Main installation flow
main() {
    print_header
    check_requirements
    detect_shell
    
    downloaded=false
    if [[ ! -f "$SCRIPT_NAME" ]]; then
        download_script
        downloaded=true
    else
        echo -e "${GREEN}Using local $SCRIPT_NAME for installation...${RESET}"
    fi
    
    install_encryptor
    
    if [[ "$downloaded" == true ]]; then
        rm -f "$SCRIPT_NAME"
        echo -e "${BLUE}Cleaned up temporary files${RESET}"
    fi
    
    print_success
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Encryptor Installation Script"
        echo "Usage: $0 [options]"
        echo
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --version, -v  Show version information"
        exit 0
        ;;
    --version|-v)
        echo "Encryptor Installer v$VERSION"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac