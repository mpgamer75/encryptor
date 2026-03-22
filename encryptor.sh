#!/usr/bin/env bash
# ==============================================================================
# ENCRYPTOR v2.1.0
# Advanced CLI Encryption Tool — Industry-Grade Security
#
# License: MIT  |  https://github.com/mpgamer75/encryptor
# ==============================================================================

set -uo pipefail

VERSION="2.1.0"

# --- Paths ---
CONFIG_DIR="${ENCRYPTOR_CONFIG_DIR:-$HOME/.config/encryptor}"
CERT_DIR="$CONFIG_DIR/certs"
TOOLS_DIR="$CONFIG_DIR/tools"
export TESTSSL_PATH="$TOOLS_DIR/testssl.sh/testssl.sh"
TEMP_DIR="/tmp/encryptor_$$"
LOG_FILE="$CONFIG_DIR/encryptor.log"

# --- LIB_DIR: resolve the directory containing this script ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="$SCRIPT_DIR/lib"

# --- Bootstrap: create directories before sourcing modules ---
mkdir -p "$CONFIG_DIR" "$CERT_DIR" "$TOOLS_DIR" "$TEMP_DIR"
chmod 700 "$CONFIG_DIR" "$CERT_DIR" 2>/dev/null || true

# --- Cleanup on exit ---
trap 'rm -rf "$TEMP_DIR" 2>/dev/null || true' EXIT

# --- Require OpenSSL ---
if ! command -v openssl >/dev/null 2>&1; then
    printf '\e[31mFatal:\e[0m OpenSSL is not installed.\n' >&2
    printf 'Install it with: sudo apt install openssl\n' >&2
    exit 1
fi

# --- Source modules ---
for _mod in ui crypto certs audit; do
    _mod_path="${LIB_DIR}/${_mod}.sh"
    if [[ ! -f "$_mod_path" ]]; then
        printf '\e[31mFatal:\e[0m Module not found: %s\n' "$_mod_path" >&2
        printf 'Re-install encryptor or check %s\n' "$LIB_DIR" >&2
        exit 1
    fi
    # shellcheck source=lib/ui.sh
    source "$_mod_path"
done
unset _mod _mod_path

# --- Non-interactive / batch mode ---
_batch_mode() {
    local action="" file="" algo="aes-256-cbc" pass_file="" cert_file="" output_json=0
    local output_file=""

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --encrypt)   action="encrypt"; file="$2"; shift 2 ;;
            --decrypt)   action="decrypt"; file="$2"; shift 2 ;;
            --algo)      algo="$2";       shift 2 ;;
            --pass-file) pass_file="$2";  shift 2 ;;
            --cert)      cert_file="$2";  shift 2 ;;
            --output)    output_file="$2"; shift 2 ;;
            --json)      output_json=1;   shift   ;;
            *) printf 'Unknown option: %s\n' "$1" >&2; exit 1 ;;
        esac
    done

    if [[ -z "$action" ]]; then
        printf 'Batch mode requires --encrypt or --decrypt\n' >&2; exit 1
    fi
    if [[ -z "$file" ]] || [[ ! -f "$file" ]]; then
        printf 'File not found: %s\n' "${file:-<none>}" >&2; exit 1
    fi

    local start_time; start_time=$(date +%s%N)

    if [[ "$action" == "encrypt" ]]; then
        [[ -z "$output_file" ]] && output_file="${file}.enc"

        if [[ "$algo" == "smime" ]]; then
            [[ -z "$cert_file" ]] && { printf '--cert required for smime\n' >&2; exit 1; }
            openssl smime -encrypt -aes256-gcm \
                -in "$file" -out "$output_file" -outform PEM "$cert_file" 2>/dev/null
        else
            [[ -z "$pass_file" ]] && { printf '--pass-file required\n' >&2; exit 1; }
            [[ ! -f "$pass_file" ]] && { printf 'Pass file not found: %s\n' "$pass_file" >&2; exit 1; }
            openssl enc "-${algo}" -salt -pbkdf2 -iter "${PBKDF2_ITER}" \
                -in "$file" -out "$output_file" -pass "file:${pass_file}" 2>/dev/null
        fi

        local rc=$?
        local end_time; end_time=$(date +%s%N)
        local ms=$(( (end_time - start_time) / 1000000 ))

        if [[ $rc -eq 0 ]]; then
            # Write integrity sidecar
            sha256sum "$output_file" > "${output_file}.sha256" 2>/dev/null || \
                shasum -a 256 "$output_file" > "${output_file}.sha256" 2>/dev/null || true
            log_operation "SUCCESS" "Batch encrypt: $file → $output_file (${algo})"
            if [[ $output_json -eq 1 ]]; then
                printf '{"status":"success","input":"%s","output":"%s","algo":"%s","ms":%d}\n' \
                    "$file" "$output_file" "$algo" "$ms"
            else
                printf 'Encrypted: %s → %s (%s, %dms)\n' "$file" "$output_file" "$algo" "$ms"
            fi
            exit 0
        else
            log_operation "ERROR" "Batch encrypt failed: $file"
            [[ $output_json -eq 1 ]] && \
                printf '{"status":"error","input":"%s","algo":"%s"}\n' "$file" "$algo" || \
                printf 'Encryption failed\n' >&2
            exit 1
        fi

    elif [[ "$action" == "decrypt" ]]; then
        [[ -z "$output_file" ]] && output_file="${file%.enc}.dec"

        if [[ "$algo" == "smime" ]]; then
            [[ -z "$cert_file" ]] && { printf '--cert required for smime\n' >&2; exit 1; }
            [[ -z "$pass_file" ]] && { printf '--pass-file (key path) required for smime\n' >&2; exit 1; }
            openssl smime -decrypt -in "$file" -out "$output_file" \
                -inform PEM -recip "$cert_file" -inkey "$pass_file" 2>/dev/null
        else
            [[ -z "$pass_file" ]] && { printf '--pass-file required\n' >&2; exit 1; }
            openssl enc -d "-${algo}" -pbkdf2 -iter "${PBKDF2_ITER}" \
                -in "$file" -out "$output_file" -pass "file:${pass_file}" 2>/dev/null
        fi

        local rc=$?
        local end_time; end_time=$(date +%s%N)
        local ms=$(( (end_time - start_time) / 1000000 ))

        if [[ $rc -eq 0 ]]; then
            log_operation "SUCCESS" "Batch decrypt: $file → $output_file (${algo})"
            if [[ $output_json -eq 1 ]]; then
                printf '{"status":"success","input":"%s","output":"%s","algo":"%s","ms":%d}\n' \
                    "$file" "$output_file" "$algo" "$ms"
            else
                printf 'Decrypted: %s → %s (%s, %dms)\n' "$file" "$output_file" "$algo" "$ms"
            fi
            exit 0
        else
            rm -f "$output_file" 2>/dev/null
            log_operation "ERROR" "Batch decrypt failed: $file"
            [[ $output_json -eq 1 ]] && \
                printf '{"status":"error","input":"%s","algo":"%s"}\n' "$file" "$algo" || \
                printf 'Decryption failed\n' >&2
            exit 1
        fi
    fi
}

# --- Main interactive menu ---
main_menu() {
    while true; do
        print_header

        echo -e "  ${YELLOW}${BOLD}[1]${RESET}  ${WHITE}List Files${RESET}"
        echo -e "  ${YELLOW}${BOLD}[2]${RESET}  ${GREEN}${BOLD}Encrypt a File${RESET}"
        echo -e "  ${YELLOW}${BOLD}[3]${RESET}  ${RED}${BOLD}Decrypt a File${RESET}"
        echo -e "\n  ${BLUE}${BOLD}[4]${RESET}  ${WHITE}Certificate Manager${RESET}  ${DIM}(X.509 / PKI / S/MIME)${RESET}"
        echo -e "  ${BLUE}${BOLD}[5]${RESET}  ${WHITE}Security Audit${RESET}        ${DIM}(local checks + remote scan)${RESET}"
        echo -e "\n  ${CYAN}${BOLD}[h]${RESET}  ${WHITE}Help${RESET}"
        echo -e "  ${CYAN}${BOLD}[l]${RESET}  ${WHITE}View Logs${RESET}"
        echo -e "  ${CYAN}${BOLD}[q]${RESET}  ${WHITE}Quit${RESET}"
        echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${RESET}"

        echo -en "\n${MAGENTA}${BOLD}Your choice: ${RESET}"
        read -r choice
        choice=$(echo "$choice" | tr -d '[:space:]')

        case "$choice" in
            1) list_files_simple ;;
            2) process_encryption ;;
            3) process_decryption ;;
            4) manage_certificates ;;
            5) security_audit_menu ;;
            h|H) show_help ;;
            l|L)
                print_section_header "Operation Log"
                if [[ -f "$LOG_FILE" ]]; then
                    less "$LOG_FILE"
                else
                    echo -e "${DIM}No log entries yet.${RESET}"
                    press_enter_to_continue
                fi
                ;;
            q|Q)
                echo -e "${GREEN}Goodbye. Cleaning up...${RESET}"
                log_operation "INFO" "Session ended."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice.${RESET}"
                sleep 1
                ;;
        esac
    done
}

# ==============================================================================
# Entry Point
# ==============================================================================

log_operation "INFO" "Encryptor v${VERSION} started (uid=$UID)"

# CLI argument dispatch
case "${1:-}" in
    --help|-h)
        show_help
        exit 0
        ;;
    --version|-v)
        echo "Encryptor v${VERSION}"
        exit 0
        ;;
    --encrypt|--decrypt)
        _batch_mode "$@"
        ;;
    "")
        main_menu
        ;;
    *)
        printf 'Unknown option: %s\n' "$1" >&2
        printf 'Run: encryptor --help\n' >&2
        exit 1
        ;;
esac
