#!/bin/bash

# Encryptor Installation Script
# Installs Encryptor system-wide or locally with automatic PATH configuration

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
GITHUB_URL="https://raw.githubusercontent.com/mpgamer75/encryptor/main"

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

detect_shell() {
    local user_shell=$(basename "${SHELL:-}")
    local detected_shell=""
    local config_file=""
    
    echo -e "${BLUE}🐚 Detecting shell configuration...${RESET}"
    
    # Detect shell and corresponding config file
    case "$user_shell" in
        "zsh")
            detected_shell="Zsh"
            config_file="$HOME/.zshrc"
            ;;
        "bash")
            detected_shell="Bash"
            if [[ -f "$HOME/.bashrc" ]]; then
                config_file="$HOME/.bashrc"
            elif [[ -f "$HOME/.bash_profile" ]]; then
                config_file="$HOME/.bash_profile"
            else
                config_file="$HOME/.bashrc"
            fi
            ;;
        "fish")
            detected_shell="Fish"
            config_file="$HOME/.config/fish/config.fish"
            ;;
        *)
            detected_shell="Unknown ($user_shell)"
            config_file="$HOME/.profile"
            ;;
    esac
    
    echo -e "${GREEN}✅ Shell: ${BOLD}$detected_shell${RESET}"
    echo -e "${BLUE}📝 Config file: ${BOLD}$config_file${RESET}"
    echo
    
    # Return values via global variables
    DETECTED_SHELL="$user_shell"
    CONFIG_FILE="$config_file"
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
    
    if [[ $? -eq 0 ]] && [[ -s "$SCRIPT_NAME" ]]; then
        echo -e "${GREEN}✅ Download completed${RESET}"
    else
        echo -e "${RED}❌ Download failed or file is empty${RESET}"
        exit 1
    fi
    echo
}

install_encryptor() {
    local install_dir
    local needs_path_config=false
    
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
            needs_path_config=true
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
    
    # Configure PATH if needed
    if [[ "$needs_path_config" == true ]]; then
        configure_path "$install_dir"
    fi
}

configure_path() {
    local install_dir="$1"
    
    echo -e "${BLUE}⚙️  Configuring PATH...${RESET}"
    
    # Check if PATH already configured
    if [[ ":$PATH:" == *":$install_dir:"* ]]; then
        echo -e "${GREEN}✅ PATH already configured correctly${RESET}"
        return 0
    fi
    
    # Create config file if it doesn't exist
    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo -e "${YELLOW}📁 Creating config file: $CONFIG_FILE${RESET}"
        
        # Create directory for fish config if needed
        if [[ "$DETECTED_SHELL" == "fish" ]]; then
            mkdir -p "$(dirname "$CONFIG_FILE")"
        fi
        
        touch "$CONFIG_FILE"
    fi
    
    # Check if PATH export already exists
    local path_exists=false
    case "$DETECTED_SHELL" in
        "fish")
            if grep -q "set -gx PATH.*\.local/bin" "$CONFIG_FILE" 2>/dev/null; then
                path_exists=true
            fi
            ;;
        *)
            if grep -q 'export PATH.*\.local/bin' "$CONFIG_FILE" 2>/dev/null; then
                path_exists=true
            fi
            ;;
    esac
    
    # Add PATH configuration if not exists
    if [[ "$path_exists" == false ]]; then
        echo "" >> "$CONFIG_FILE"
        echo "# Added by Encryptor installer" >> "$CONFIG_FILE"
        
        case "$DETECTED_SHELL" in
            "fish")
                echo "set -gx PATH \$HOME/.local/bin \$PATH" >> "$CONFIG_FILE"
                ;;
            *)
                echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$CONFIG_FILE"
                ;;
        esac
        
        echo -e "${GREEN}✅ PATH configured in $CONFIG_FILE${RESET}"
    else
        echo -e "${YELLOW}⚠️  PATH already configured in $CONFIG_FILE${RESET}"
    fi
    
    # Update current session PATH
    export PATH="$install_dir:$PATH"
    echo -e "${GREEN}✅ PATH updated for current session${RESET}"
}

test_installation() {
    echo -e "${BLUE}🧪 Testing installation...${RESET}"
    
    # Test if command is available
    if command -v "$BINARY_NAME" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Command '$BINARY_NAME' is available${RESET}"
        
        # Test version with timeout to avoid hanging
        local version_output
        if version_output=$(timeout 10s "$BINARY_NAME" --version 2>/dev/null); then
            echo -e "${GREEN}✅ Encryptor launches successfully${RESET}"
            echo -e "${BLUE}   $version_output${RESET}"
        else
            echo -e "${YELLOW}⚠️  Command available but version check timed out${RESET}"
        fi
    else
        echo -e "${YELLOW}⚠️  Command '$BINARY_NAME' not immediately available${RESET}"
        
        # Try direct path
        if [[ -f "$HOME/.local/bin/$BINARY_NAME" ]]; then
            echo -e "${BLUE}🔄 Testing direct path...${RESET}"
            if version_output=$(timeout 10s "$HOME/.local/bin/$BINARY_NAME" --version 2>/dev/null); then
                echo -e "${GREEN}✅ Direct path works: $version_output${RESET}"
                
                # For GitHub Actions: export PATH in GITHUB_PATH
                if [[ -n "${GITHUB_ACTIONS:-}" ]]; then
                    echo "$HOME/.local/bin" >> "$GITHUB_PATH"
                    echo -e "${BLUE}🔧 Updated GITHUB_PATH for CI${RESET}"
                else
                    echo -e "${YELLOW}💡 You may need to restart your terminal${RESET}"
                fi
            else
                echo -e "${YELLOW}⚠️  Direct path test timed out${RESET}"
            fi
        fi
    fi
}

reload_shell_config() {
    echo -e "${BLUE}🔄 Attempting to reload shell configuration...${RESET}"
    
    # Try to source the config file (but don't hang on it)
    if [[ -f "$CONFIG_FILE" ]]; then
        case "$DETECTED_SHELL" in
            "fish")
                # Fish shell doesn't support sourcing in the same way
                echo -e "${YELLOW}💡 Fish shell detected - config will be loaded on next shell start${RESET}"
                ;;
            *)
                # Try to source but with timeout to avoid hanging
                if timeout 5s bash -c "source '$CONFIG_FILE'" 2>/dev/null; then
                    echo -e "${GREEN}✅ Shell configuration reloaded${RESET}"
                else
                    echo -e "${YELLOW}⚠️  Could not reload configuration automatically${RESET}"
                fi
                ;;
        esac
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
    
    # Test final availability
    if command -v "$BINARY_NAME" >/dev/null 2>&1; then
        echo -e "${GREEN}✅ Encryptor is ready to use!${RESET}"
        echo -e "${BOLD}  encryptor${RESET}          # Launch interactive menu"
        echo -e "${BOLD}  encryptor --help${RESET}   # Show help information"
    else
        echo -e "${YELLOW}⚠️  Manual step required:${RESET}"
        echo -e "${BOLD}Restart your terminal${RESET} or run one of these commands:"
        
        case "$DETECTED_SHELL" in
            "zsh")
                echo -e "${BOLD}  exec zsh${RESET}              # Restart Zsh"
                echo -e "${BOLD}  source ~/.zshrc${RESET}       # Reload config"
                ;;
            "bash")
                echo -e "${BOLD}  exec bash${RESET}             # Restart Bash"
                echo -e "${BOLD}  source ~/.bashrc${RESET}      # Reload config"
                ;;
            "fish")
                echo -e "${BOLD}  exec fish${RESET}             # Restart Fish"
                ;;
            *)
                echo -e "${BOLD}  exec \$SHELL${RESET}          # Restart shell"
                echo -e "${BOLD}  source $CONFIG_FILE${RESET}"
                ;;
        esac
        
        echo
        echo -e "${BLUE}Or use the full path temporarily:${RESET}"
        echo -e "${BOLD}  ~/.local/bin/encryptor${RESET}"
    fi
    
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
    detect_shell
    
    local downloaded=false
    if [[ ! -f "$SCRIPT_NAME" ]]; then
        download_script
        downloaded=true
    fi
    
    install_encryptor
    test_installation
    reload_shell_config
    
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
        echo "  2. Detect your shell (Zsh, Bash, Fish, etc.)"
        echo "  3. Download Encryptor (if not present locally)"
        echo "  4. Install to appropriate directory"
        echo "  5. Automatically configure PATH for your shell"
        echo "  6. Test the installation"
        echo
        echo "Supported shells: Zsh, Bash, Fish, and others"
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