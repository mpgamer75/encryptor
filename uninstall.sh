#!/usr/bin/env bash
# ==============================================================================
# Encryptor — Uninstall Script
# ==============================================================================
set -uo pipefail

BOLD="\e[1m"; RED="\e[31m"; YELLOW="\e[33m"; GREEN="\e[32m"; CYAN="\e[36m"; RESET="\e[0m"
CONFIG_DIR="${HOME}/.config/encryptor"

echo -e "${CYAN}${BOLD}Encryptor Uninstaller${RESET}\n"

# Remove the binary
removed_binary=0
for location in /usr/local/bin/encryptor "${HOME}/.local/bin/encryptor"; do
    if [[ -f "$location" ]]; then
        sudo rm -f "$location" 2>/dev/null || rm -f "$location" 2>/dev/null || true
        echo -e "${GREEN}✓ Removed binary: $location${RESET}"
        removed_binary=1
    fi
done

# Remove lib directory alongside the binary location if installed
if [[ -d /usr/local/lib/encryptor ]]; then
    sudo rm -rf /usr/local/lib/encryptor 2>/dev/null || true
    echo -e "${GREEN}✓ Removed /usr/local/lib/encryptor${RESET}"
fi

[[ $removed_binary -eq 0 ]] && echo -e "${YELLOW}No encryptor binary found in standard locations.${RESET}"

# Remove man page
for man_path in /usr/local/man/man1/encryptor.1.gz /usr/share/man/man1/encryptor.1.gz; do
    if [[ -f "$man_path" ]]; then
        sudo rm -f "$man_path" 2>/dev/null || true
        echo -e "${GREEN}✓ Removed man page: $man_path${RESET}"
    fi
done
sudo mandb -q 2>/dev/null || true

# User config / data directory
if [[ -d "$CONFIG_DIR" ]]; then
    echo -e "\n${YELLOW}${BOLD}User data found at: ${CONFIG_DIR}${RESET}"
    echo -e "${YELLOW}This contains:${RESET}"
    echo -e "  • Certificates and private keys  (${CYAN}${CONFIG_DIR}/certs/${RESET})"
    echo -e "  • Operation logs                  (${CYAN}${CONFIG_DIR}/encryptor.log${RESET})"
    echo -e "  • Downloaded tools                (${CYAN}${CONFIG_DIR}/tools/${RESET})"
    echo -e "\n${RED}${BOLD}Warning: Deleting this directory PERMANENTLY destroys all managed${RESET}"
    echo -e "${RED}${BOLD}certificates and private keys. There is NO recovery.${RESET}\n"

    echo -en "${YELLOW}${BOLD}Delete all user data? [y/N]: ${RESET}"
    read -r answer
    if [[ "${answer,,}" == "y" ]]; then
        rm -rf "$CONFIG_DIR"
        echo -e "${GREEN}✓ User data removed: $CONFIG_DIR${RESET}"
    else
        echo -e "${CYAN}User data kept. You may remove it manually later:${RESET}"
        echo -e "  rm -rf ${CONFIG_DIR}"
    fi
fi

# Clean leftover temp directories
find /tmp -maxdepth 1 -name "encryptor_*" -type d -exec rm -rf {} + 2>/dev/null || true

echo -e "\n${GREEN}${BOLD}Encryptor has been uninstalled.${RESET}"
