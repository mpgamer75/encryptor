#!/bin/bash

# Encryptor Installation Script
# Installs Encryptor system-wide or locally

set -e

# Colors
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

# Constants
VERSION="1.0.0"
SCRIPT_NAME="encryptor.sh"
BINARY_NAME="encryptor"
GITHUB_URL="https://raw.githubusercontent.com/yourusername/encryptor/main"

# Functions
print_header() {
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
 ███████╗███╗   ██╗ ██████╗██████╗ ██╗   ██╗██████╗ ████████╗ ██████╗ ██████╗ 
 ██╔════╝████╗  ██║██╔════╝██╔══██╗╚██╗ ██╔╝██╔══██╗╚══██╔══╝██╔═══██╗██╔══██╗
 █████╗  ██╔██╗ ██║██║     ██████╔╝ ╚████╔╝ ██████╔╝   ██║   ██║   ██║██████╔╝
 ██╔══╝  ██║╚██╗██║██║     ██╔══██╗  ╚██╔╝  ██╔═══╝    ██║   ██║   ██║██╔══██╗
 ███████╗██║ ╚████║╚██████╗██║  ██║   ██║   ██║        ██║   ╚██████╔╝██║  ██║
 ╚══════╝╚═╝  ╚═══╝ ╚═════╝╚═╝  ╚═╝   ╚═╝   ╚═╝        ╚═╝    ╚═════╝ ╚═╝  ╚═╝
EOF
    echo -e "${RESET}"
    echo -e "${GREEN}${BOLD}                    Encryptor Installer v$VERSION${RESET}"
    echo -e "${BLUE}                      Advanced File Encryption${RESET}"
    echo
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════════${RESET}"
    echo
}

check_requirements() {
    echo -e "${BLUE}🔍 Checking system requirements...${RESET}"
    
    # Check Bash version
    if ! command -v bash >/dev/null 2>&1; then
        echo -e "${RED}❌ Error: Bash not found${RESET}"
        exit 1
    fi
    
    local bash_version=$(bash --version | head -n1 | grep -oE '[0-9]+\.[0-9]+')
    echo -e "${GREEN}✅ Bash $bash_version detected${RESET}"
    
    # Check OpenSSL
    if ! command -v openssl >/dev/null 2>&1; then
        echo -e "${RED}❌ Error: OpenSSL not found${RESET}"
        echo -e "${YELLOW}Please install OpenSSL:${RESET}"
        echo -e "  Ubuntu/Debian: ${BOLD}sudo apt install openssl${RESET}"
        echo -e "  CentOS/RHEL:   ${BOLD}sudo yum install openssl${RESET}"
        echo -e "  macOS:         ${BOLD}brew install openssl${RESET}"
        exit 1
    fi
    
    local ssl_version=$(openssl version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    echo -e "${GREEN}✅ OpenSSL $ssl_version detected${RESET}"
    
    echo
}

download_script() {
    echo -e "${BLUE}📥 Downloading Encryptor...${RESET}"
    
    if [[ -f "$SCRIPT_NAME" ]]; then
        echo -e "${GREEN}✅ Found local $SCRIPT_NAME${RESET}"
        return 0
    fi
    
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL "$GITHUB_URL/$SCRIPT_NAME" -o "$SCRIPT_NAME"
    elif command -v wget >/dev/null 2>&1; then
        wget -q "$GITHUB_URL/$SCRIPT_NAME" -O "$SCRIPT_NAME"
    else
        echo -e "${RED}❌ Error: Neither curl nor wget found${RESET}"
        echo -e "${YELLOW}Please install curl or wget, or download manually${RESET}"
        exit 1
    fi
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✅ Download completed${RESET}"
    else
        echo -e "${RED}❌ Download failed${RESET}"
        exit 1
    fi
    echo
}

install_encryptor() {
    local install_dir
    local needs_sudo=false
    
    # Determine installation directory
    if [[ $EUID -eq 0 ]]; then
        install_dir="/usr/local/bin"
        echo -e "${GREEN}🔧 Installing system-wide in $install_dir${RESET}"
    else
        # Try system directory first
        if [[ -w "/usr/local/bin" ]]; then
            install_dir="/usr/local/bin"
            echo -e "${GREEN}🔧 Installing system-wide in $install_dir${RESET}"
        else
            # Fall back to user directory
            install_dir="$HOME/.local/bin"
            echo -e "${GREEN}🔧 Installing for current user in $install_dir${RESET}"
            
            # Create user bin directory if it doesn't exist
            if [[ ! -d "$install_dir" ]]; then
                mkdir -p "$install_dir"
                echo -e "${YELLOW}📁 Created directory: $install_dir${RESET}"
            fi
        fi
    fi
    
    # Copy and make executable
    cp "$SCRIPT_NAME" "$install_dir/$BINARY_NAME"
    chmod +x "$install_dir/$BINARY_NAME"
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}✅ Installation successful!${RESET}"
    else
        echo -e "${RED}❌ Installation failed${RESET}"
        exit 1
    fi
    
    # Check PATH
    if [[ ":$PATH:" != *":$install_dir:"* ]] && [[ "$install_dir" == "$HOME/.local/bin" ]]; then
        echo -e "${YELLOW}⚠️  Warning: $install_dir is not in your PATH${RESET}"
        echo -e "${YELLOW}Add this line to your shell configuration:${RESET}"
        echo -e "${BOLD}export PATH=\"\$HOME/.local/bin:\$PATH\"${RESET}"
        echo
        echo -e "${YELLOW}Shell configuration files:${RESET}"
        echo -e "  Bash: ~/.bashrc or ~/.bash_profile"
        echo -e "  Zsh:  ~/.zshrc"
        echo -e "  Fish: ~/.config/fish/config.fish"
        echo
        echo -e "${YELLOW}Then reload with: ${BOLD}source ~/.bashrc${RESET} (or your shell config)"
        echo
    fi
}

test_installation() {
    echo -e "${BLUE}🧪 Testing installation...${RESET}"
    
    if command -v "$BINARY_NAME" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Command '$BINARY_NAME' is available${RESET}"
        
        # Test if script runs without errors
        if timeout 2s "$BINARY_NAME" --version >/dev/null 2>&1 || [[ $? -eq 124 ]]; then
            echo -e "${GREEN}✅ Encryptor launches successfully${RESET}"
        fi
    else
        echo -e "${YELLOW}⚠️  Command '$BINARY_NAME' not immediately available${RESET}"
        echo -e "${YELLOW}You may need to reload your shell or restart your terminal${RESET}"
    fi
}

cleanup() {
    if [[ -f "$SCRIPT_NAME" ]] && [[ "$1" == "downloaded" ]]; then
        rm -f "$SCRIPT_NAME"
        echo -e "${BLUE}🧹 Cleaned up temporary files${RESET}"
    fi
}

print_success() {
    echo
    echo -e "${GREEN}${BOLD}🎉 Installation Complete! 🎉${RESET}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo
    echo -e "${GREEN}You can now use Encryptor by running:${RESET}"
    echo -e "${BOLD}  encryptor${RESET}"
    echo
    echo -e "${BLUE}Quick start:${RESET}"
    echo -e "  ${YELLOW}encryptor${RESET}          # Launch interactive menu"
    echo -e "  ${YELLOW}encryptor --help${RESET}   # Show help information"
    echo
    echo -e "${BLUE}Features:${RESET}"
    echo -e "  • Multiple encryption algorithms (AES-256, RSA, Hybrid)"
    echo -e "  • User-friendly colorful interface"
    echo -e "  • Built-in help and documentation"
    echo -e "  • Secure key management"
    echo
    echo -e "${MAGENTA}Thank you for installing Encryptor! 🔐${RESET}"
    echo
}

# Main installation flow
main() {
    print_header
    check_requirements
    
    local downloaded=false
    if [[ ! -f "$SCRIPT_NAME" ]]; then
        download_script
        downloaded=true
    fi
    
    install_encryptor
    test_installation
    
    if [[ "$downloaded" == true ]]; then
        cleanup "downloaded"
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
        echo
        echo "This script will:"
        echo "  1. Check system requirements (Bash, OpenSSL)"
        echo "  2. Download Encryptor (if not present locally)"
        echo "  3. Install to appropriate directory"
        echo "  4. Set up PATH if needed"
        echo "  5. Test the installation"
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