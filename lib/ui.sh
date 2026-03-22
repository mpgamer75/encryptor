#!/usr/bin/env bash
# ==============================================================================
# lib/ui.sh — UI Utilities: colors, headers, prompts, spinner, file selector
# ==============================================================================

# --- Colors (with tput fallback) ---
if command -v tput >/dev/null 2>&1 && [[ -t 1 ]]; then
    BOLD=$(tput bold)
    UNDERLINE=$(tput smul)
    RESET=$(tput sgr0)
    GREEN=$(tput setaf 2)
    BLUE=$(tput setaf 4)
    RED=$(tput setaf 1)
    YELLOW=$(tput setaf 3)
    CYAN=$(tput setaf 6)
    MAGENTA=$(tput setaf 5)
    WHITE=$(tput setaf 7)
    ORANGE=$(tput setaf 208 2>/dev/null || tput setaf 3)
    PURPLE=$(tput setaf 135 2>/dev/null || tput setaf 5)
    LIME=$(tput setaf 118 2>/dev/null || tput setaf 2)
    PINK=$(tput setaf 205 2>/dev/null || tput setaf 5)
    DIM=$(tput dim 2>/dev/null || true)
else
    BOLD="\e[1m"
    UNDERLINE="\e[4m"
    RESET="\e[0m"
    GREEN="\e[32m"
    BLUE="\e[34m"
    RED="\e[31m"
    YELLOW="\e[33m"
    CYAN="\e[36m"
    MAGENTA="\e[35m"
    WHITE="\e[97m"
    ORANGE="\e[38;5;208m"
    PURPLE="\e[38;5;135m"
    LIME="\e[38;5;118m"
    PINK="\e[38;5;205m"
    DIM="\e[2m"
fi
export BOLD UNDERLINE RESET GREEN BLUE RED YELLOW CYAN MAGENTA WHITE ORANGE PURPLE LIME PINK DIM

# --- Logging ---
log_operation() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    printf '[%s] [%s] %s\n' "$timestamp" "$level" "$message" >> "$LOG_FILE"
}

# --- Print main header ---
print_header() {
    clear

    # Gather status line data
    local openssl_ver cert_count last_op
    openssl_ver=$(openssl version 2>/dev/null | awk '{print $1,$2}')
    cert_count=$(find "$CERT_DIR" -maxdepth 1 \( -name '*.pem' -o -name '*.key' \) 2>/dev/null | wc -l | tr -d ' ')
    last_op=$(tail -1 "$LOG_FILE" 2>/dev/null | sed 's/\[.*\] \[/[/' || true)

    echo -e "${GREEN}${BOLD}"
    cat << 'EOF'
    ______                             __
   / ____/___  ____________  ______  / /_____  _____
  / __/ / __ \/ ___/ ___/ / / / __ \/ __/ __ \/ ___/
 / /___/ / / / /__/ /  / /_/ / /_/ / /_/ /_/ / /
/_____/_/ /_/\___/_/   \__, / .___/\__/\____/_/
                      /____/_/
EOF
    echo -e "${RESET}"
    echo -e "${CYAN}${BOLD}                   Advanced Encryption Tool v${VERSION}${RESET}"
    echo -e "${DIM}                          by mpgamer75${RESET}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${RESET}"

    # Status bar
    echo -e "  ${DIM}OpenSSL: ${WHITE}${openssl_ver}${RESET}  ${DIM}│  Certs/Keys: ${WHITE}${cert_count}${RESET}  ${DIM}│  Config: ${WHITE}${CONFIG_DIR}${RESET}"
    [[ -n "$last_op" ]] && echo -e "  ${DIM}Last op : ${last_op}${RESET}"
    echo -e "${GREEN}───────────────────────────────────────────────────────────────────${RESET}"
}

# --- Print section header ---
print_section_header() {
    local title="$1"
    echo -e "\n${CYAN}${BOLD}:: ${title} ::${RESET}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────────${RESET}"
}

# --- Pause for user ---
press_enter_to_continue() {
    echo -e "\n${DIM}Press [Enter] to continue...${RESET}"
    read -r
}

# --- ASCII spinner for long operations ---
# Usage: start_spinner "message"; <do work>; stop_spinner $?
_SPINNER_PID=""
start_spinner() {
    local msg="${1:-Working...}"
    local chars='⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏'
    (
        i=0
        while true; do
            c="${chars:$((i % ${#chars})):1}"
            printf "\r  ${CYAN}${c}${RESET}  ${DIM}%s${RESET}" "$msg" >&2
            sleep 0.1
            ((i++))
        done
    ) &
    _SPINNER_PID=$!
    disown "$_SPINNER_PID" 2>/dev/null || true
}

stop_spinner() {
    local exit_code="${1:-0}"
    if [[ -n "$_SPINNER_PID" ]]; then
        kill "$_SPINNER_PID" 2>/dev/null || true
        wait "$_SPINNER_PID" 2>/dev/null || true
        _SPINNER_PID=""
        printf "\r%-70s\r" "" >&2   # clear the spinner line
    fi
    return "$exit_code"
}

# --- Show human-readable file size ---
human_size() {
    local bytes="$1"
    if command -v numfmt &>/dev/null; then
        numfmt --to=iec --suffix=B "$bytes" 2>/dev/null || echo "${bytes}B"
    elif [[ $bytes -ge 1073741824 ]]; then
        echo "$(( bytes / 1073741824 ))GB"
    elif [[ $bytes -ge 1048576 ]]; then
        echo "$(( bytes / 1048576 ))MB"
    elif [[ $bytes -ge 1024 ]]; then
        echo "$(( bytes / 1024 ))KB"
    else
        echo "${bytes}B"
    fi
}

# --- File size helper ---
get_file_size() {
    local f="$1"
    stat -c%s "$f" 2>/dev/null || stat -f%z "$f" 2>/dev/null || echo "0"
}

# --- Simple File Lister ---
list_files_simple() {
    print_section_header "File Explorer"
    echo -e "${DIM}Current directory: $(pwd)${RESET}\n"

    local dirs=() files=()
    for item in *; do
        [[ -d "$item" ]] && dirs+=("$item")
        [[ -f "$item" ]] && files+=("$item")
    done

    echo -e "${BLUE}${BOLD}Directories:${RESET}"
    if [[ ${#dirs[@]} -eq 0 ]]; then
        echo -e "${DIM}  (no directories)${RESET}"
    else
        for dir in "${dirs[@]}"; do
            echo -e "  ${BLUE}📁 ${dir}/${RESET}"
        done
    fi

    echo -e "\n${GREEN}${BOLD}Files:${RESET}"
    if [[ ${#files[@]} -eq 0 ]]; then
        echo -e "${DIM}  (no files)${RESET}"
    else
        local max_len=0
        for file in "${files[@]}"; do
            [[ ${#file} -gt $max_len ]] && max_len=${#file}
        done

        for file in "${files[@]}"; do
            local icon="📄"
            case "${file##*.}" in
                enc|gpg|pgp) icon="🔒" ;;
                key|pem|crt) icon="🔑" ;;
                zip|tar|gz|bz2|xz) icon="📦" ;;
                txt|md|rst) icon="📝" ;;
                png|jpg|jpeg|gif|svg) icon="🖼️ " ;;
                mp4|mkv|avi|mov) icon="🎬" ;;
                mp3|flac|wav|ogg) icon="🎵" ;;
                sh|bash|py|js|ts) icon="💻" ;;
                sha256) icon="🔐" ;;
            esac

            local sz
            sz=$(get_file_size "$file")
            local size_str=""
            [[ "$sz" != "0" ]] && size_str="($(human_size "$sz"))"

            printf "  ${GREEN}%s %-${max_len}s${RESET}  ${DIM}%s${RESET}\n" "$icon" "$file" "$size_str"
        done
    fi

    press_enter_to_continue
}

# --- Interactive file selector ---
select_file_interactive() {
    local prompt_text="$1"
    local files=()
    local i=1

    print_section_header "File Selector" >&2

    for item in *; do
        [[ -f "$item" ]] && files+=("$item")
    done

    if [[ ${#files[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No files found in this directory.${RESET}" >&2
        return 1
    fi

    for file in "${files[@]}"; do
        local icon="📄"
        case "${file##*.}" in
            enc|gpg|pgp) icon="🔒" ;;
            key|pem|crt) icon="🔑" ;;
            zip|tar|gz) icon="📦" ;;
            txt|md) icon="📝" ;;
            sha256) icon="🔐" ;;
        esac
        echo -e "  ${YELLOW}${BOLD}[$i]${RESET} $icon $file" >&2
        ((i++))
    done

    echo -e "\n${DIM}Type a number, a file name, or 'q' to cancel.${RESET}" >&2

    while true; do
        echo -en "\n${MAGENTA}${BOLD}${prompt_text}${RESET}" >&2
        read -r choice
        choice=$(echo "$choice" | xargs 2>/dev/null || echo "$choice")

        if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
            return 1
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#files[@]} ]]; then
            echo "${files[$((choice-1))]}"
            return 0
        elif [[ -f "$choice" ]]; then
            echo "$choice"
            return 0
        else
            echo -e "${RED}Invalid choice or file not found. Try again.${RESET}" >&2
        fi
    done
}

# --- Inline help screen ---
show_help() {
    print_section_header "Encryptor Help"
    cat << EOF

${BOLD}USAGE${RESET}
  encryptor                    Launch interactive menu
  encryptor --help             Show this help
  encryptor --version          Show version
  encryptor --encrypt FILE     Encrypt a file (non-interactive, see below)
  encryptor --decrypt FILE     Decrypt a file (non-interactive, see below)

${BOLD}NON-INTERACTIVE MODE${RESET}
  encryptor --encrypt FILE --algo aes-256-cbc --pass-file PASSFILE
  encryptor --decrypt FILE --algo aes-256-cbc --pass-file PASSFILE
  encryptor --encrypt FILE --algo smime --cert CERT.pem

  Algorithms: aes-256-cbc (default), aes-256-ctr, chacha20,
              camellia-256-cbc, aria-256-cbc, smime

${BOLD}ENCRYPTION ALGORITHMS${RESET}
  aes-256-cbc       Recommended for symmetric encryption. NIST FIPS 197.
                    CBC mode with SHA-256 integrity sidecar (.sha256 file).
  aes-256-ctr       AES Counter Mode. Parallelizable. SHA-256 sidecar.
  chacha20          Modern stream cipher. Constant-time. SHA-256 sidecar.
  camellia-256-cbc  Japanese standard (NTT/KDDI). ISO/IEC 18033-3.
  aria-256-cbc      Korean standard (NSRI/KISA). ISO/IEC 18033-3.
  smime             Asymmetric (certificate-based). TRUE AEAD via
                    AES-256-GCM key wrap. No shared password needed.

  Note: openssl enc does not support AEAD/GCM for symmetric encryption.
  For true authenticated encryption, use S/MIME with a certificate.
  All symmetric modes use a SHA-256 sidecar file for integrity.

${BOLD}KEY DERIVATION${RESET}
  All password-based modes use PBKDF2-HMAC-SHA256 with 600,000 iterations
  and a random 8-byte salt (OpenSSL default). This exceeds NIST SP 800-132
  and OWASP 2024 recommendations.

${BOLD}INTEGRITY VERIFICATION${RESET}
  A SHA-256 hash file (FILE.enc.sha256) is created alongside every encrypted
  file. Encryptor verifies this hash before decrypting. Delete the .sha256
  file only if you are sure the encrypted file has not been tampered with.

${BOLD}FILES${RESET}
  ~/.config/encryptor/          Configuration and certificate directory
  ~/.config/encryptor/certs/    X.509 certificates and private keys
  ~/.config/encryptor/tools/    External tools (e.g., testssl.sh)
  ~/.config/encryptor/encryptor.log  Operation log

${BOLD}SECURITY NOTES${RESET}
  • Passwords are NEVER passed on the command line (uses file descriptors)
  • Private keys are stored with 400 permissions
  • Temporary files are auto-deleted on exit via trap
  • Use AES-256-GCM or S/MIME for authenticated encryption

${BOLD}MORE INFORMATION${RESET}
  man encryptor                Full manual (requires .deb install)
  https://github.com/mpgamer75/encryptor

EOF
    press_enter_to_continue
}
