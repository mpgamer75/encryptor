#!/bin/bash

# Encryptor Installation Script - Simplified and Fixed Version
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
VERSION="1.1.0"
SCRIPT_NAME="encryptor.sh"
BINARY_NAME="encryptor"
GITHUB_URL="https://raw.githubusercontent.com/mpgamer75/encryptor/main"

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
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════════${RESET}"
    echo
}

check_requirements() {
    echo -e "${BLUE}Checking system requirements...${RESET}"
    
    # Check Bash version
    if ! command -v bash >/dev/null 2>&1; then
        echo -e "${RED}Error: Bash not found${RESET}"
        exit 1
    fi
    
    bash_version=$(bash --version | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1)
    echo -e "${GREEN}✅ Bash $bash_version detected${RESET}"
    
    # Check OpenSSL
    if ! command -v openssl >/dev/null 2>&1; then
        echo -e "${RED}Error: OpenSSL not found${RESET}"
        echo -e "${YELLOW}Please install OpenSSL:${RESET}"
        echo -e "  Ubuntu/Debian: ${BOLD}sudo apt install openssl${RESET}"
        echo -e "  CentOS/RHEL:   ${BOLD}sudo yum install openssl${RESET}"
        echo -e "  macOS:         ${BOLD}brew install openssl${RESET}"
        exit 1
    fi
    
    ssl_version=$(openssl version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
    echo -e "${GREEN}✅ OpenSSL $ssl_version detected${RESET}"
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
                config_file="$HOME/.bashrc"
            fi
            ;;
        "fish")
            config_file="$HOME/.config/fish/config.fish"
            ;;
        *)
            config_file="$HOME/.profile"
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
        # Try system directory first
        if [[ -w "/usr/local/bin" ]]; then
            install_dir="/usr/local/bin"
            echo -e "${GREEN}Installing system-wide in $install_dir${RESET}"
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
        exit 1
    fi
    
    # Configure PATH if needed
    if [[ "$needs_path_config" == true ]]; then
        configure_path "$install_dir"
    fi
}

configure_path() {
    install_dir="$1"
    
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
    path_exists=false
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
        echo -e "${YELLOW}PATH already configured in $config_file${RESET}"
    fi
    
    # Update current session PATH
    export PATH="$install_dir:$PATH"
    echo -e "${GREEN}✅ PATH updated for current session${RESET}"
}

test_installation() {
    echo -e "${BLUE}Testing installation...${RESET}"
    
    # Test if command is available
    if command -v "$BINARY_NAME" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Command '$BINARY_NAME' is available${RESET}"
        
        # Test version with timeout to avoid hanging
        if timeout 10s "$BINARY_NAME" --version 2>/dev/null >/dev/null; then
            echo -e "${GREEN}✅ Encryptor launches successfully${RESET}"
        else
            echo -e "${YELLOW}Command available but may need terminal restart${RESET}"
        fi
    else
        echo -e "${YELLOW}Command '$BINARY_NAME' not immediately available${RESET}"
        
        # Try direct path
        if [[ -f "$HOME/.local/bin/$BINARY_NAME" ]]; then
            echo -e "${BLUE}Testing direct path...${RESET}"
            if timeout 10s "$HOME/.local/bin/$BINARY_NAME" --version 2>/dev/null >/dev/null; then
                echo -e "${GREEN}✅ Direct path works${RESET}"
                echo -e "${YELLOW}You may need to restart your terminal or run: source $config_file${RESET}"
            else
                echo -e "${YELLOW}Direct path test inconclusive${RESET}"
            fi
        fi
    fi
}

cleanup() {
    if [[ -f "$SCRIPT_NAME" ]] && [[ "$1" == "downloaded" ]]; then
        rm -f "$SCRIPT_NAME"
        echo -e "${BLUE}Cleaned up temporary files${RESET}"
    fi
}

print_success() {
    echo
    echo -e "${GREEN}${BOLD}🎉 Installation Complete! 🎉${RESET}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo
    
    # Test final availability
    if command -v "$BINARY_NAME" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Encryptor is ready to use!${RESET}"
        echo -e "${BOLD}  encryptor${RESET}          # Launch interactive menu"
        echo -e "${BOLD}  encryptor --help${RESET}   # Show help information"
    else
        echo -e "${YELLOW}Manual step required:${RESET}"
        echo -e "${BOLD}Restart your terminal${RESET} or run:"
        
        case "$user_shell" in
            "zsh")
                echo -e "${BOLD}  source ~/.zshrc${RESET}"
                ;;
            "bash")
                echo -e "${BOLD}  source ~/.bashrc${RESET}"
                ;;
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
    echo -e "${BLUE}Features:${RESET}"
    echo -e "  • Multiple encryption algorithms (AES-256, RSA, Hybrid)"
    echo -e "  • User-friendly interface"
    echo -e "  • Built-in help and documentation"
    echo -e "  • Secure key management"
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
        echo "  2. Detect your shell configuration"
        echo "  3. Download Encryptor (if not present locally)"
        echo "  4. Install to appropriate directory"
        echo "  5. Configure PATH for your shell"
        echo "  6. Test the installation"
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