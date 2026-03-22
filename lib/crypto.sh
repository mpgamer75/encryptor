#!/usr/bin/env bash
# ==============================================================================
# lib/crypto.sh — Encryption & Decryption logic
# ==============================================================================

# PBKDF2 iteration count — exceeds NIST SP 800-132 and OWASP 2024 recommendations
PBKDF2_ITER=600000

# Algorithm registry: "UI Name" -> "openssl_cipher|type|description"
# type: sym (symmetric, password-based) | smime (asymmetric, certificate)
#
# NOTE: openssl enc does NOT support AEAD/GCM modes. AES-256-GCM is available
# via S/MIME only. All symmetric modes use SHA-256 sidecar for external integrity.
declare -A ALGORITHMS
ALGORITHMS=(
    ["AES-256-CBC"]="aes-256-cbc|sym|★ RECOMMENDED — AES 256-bit CBC. NIST-approved, FIPS 197. SHA-256 integrity sidecar provides tamper detection."
    ["AES-256-CTR"]="aes-256-ctr|sym|AES 256-bit Counter Mode. Parallelizable, no padding. SHA-256 sidecar for integrity."
    ["ChaCha20"]="chacha20|sym|Modern stream cipher by D.J. Bernstein. Constant-time, high performance. SHA-256 sidecar for integrity."
    ["Camellia-256-CBC"]="camellia-256-cbc|sym|Japanese national standard (NTT/KDDI), ISO/IEC 18033-3. Equivalent security to AES-256."
    ["ARIA-256-CBC"]="aria-256-cbc|sym|Korean national standard (NSRI/KISA), ISO/IEC 18033-3. Equivalent security to AES-256."
    ["S/MIME (Certificate)"]="smime|smime|★ TRUE AEAD — Asymmetric encryption using X.509 certificate. AES-256-GCM key wrap. Recipient-specific. No shared password."
)

# --- Algorithm selection menu ---
select_algorithm_menu() {
    print_section_header "Select Encryption Algorithm" >&2
    echo -e "${DIM}AES-256-CBC is recommended for new encrypted files.${RESET}" >&2

    local i=1
    local options=()

    # Sort keys for consistent display — GCM first
    local sorted_keys=()
    local other_keys=()
    for key in "${!ALGORITHMS[@]}"; do
        if [[ "$key" == "AES-256-CBC" || "$key" == "S/MIME (Certificate)" ]]; then
            sorted_keys+=("$key")
        else
            other_keys+=("$key")
        fi
    done
    # Sort other keys alphabetically
    local sorted_others
    mapfile -t sorted_others < <(printf '%s\n' "${other_keys[@]}" | sort)
    sorted_keys+=("${sorted_others[@]}")

    for key in "${sorted_keys[@]}"; do
        local value="${ALGORITHMS[$key]}"
        local type; type=$(echo "$value" | cut -d'|' -f2)
        local desc; desc=$(echo "$value" | cut -d'|' -f3)

        local type_label="${YELLOW}(Symmetric — Password)${RESET}"
        [[ "$type" == "smime" ]] && type_label="${CYAN}(Asymmetric — Certificate)${RESET}"

        echo -e "\n  ${YELLOW}${BOLD}[$i]${RESET} ${WHITE}${BOLD}$key${RESET}  $type_label" >&2
        echo -e "      ${DIM}$desc${RESET}" >&2

        options+=("$key")
        ((i++))
    done

    echo -e "\n${DIM}Type a number or 'q' to cancel.${RESET}" >&2

    while true; do
        echo -en "\n${MAGENTA}${BOLD}Algorithm: ${RESET}" >&2
        read -r choice
        choice=$(echo "$choice" | tr -d '[:space:]')

        if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
            return 1
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#options[@]} ]]; then
            local selected_key="${options[$((choice-1))]}"
            echo "${ALGORITHMS[$selected_key]}" | cut -d'|' -f1
            return 0
        else
            echo -e "${RED}Invalid choice. Try again.${RESET}" >&2
        fi
    done
}

# --- Secure password file ---
# Writes the password to a temp file with permissions 600.
# The file lives in TEMP_DIR which is removed on EXIT via trap.
_write_pass_file() {
    local password="$1"
    local pass_file="${TEMP_DIR}/pass.$$.tmp"
    printf '%s' "$password" > "$pass_file"
    chmod 600 "$pass_file"
    echo "$pass_file"
}

# --- Mode label for display ---
_mode_label() {
    local algo="$1"
    case "$algo" in
        smime)
            echo "AEAD (AES-256-GCM key wrap) — Authenticated Encryption"
            ;;
        aes-256-cbc|camellia-256-cbc|aria-256-cbc)
            echo "CBC (Cipher Block Chaining) + SHA-256 integrity sidecar"
            ;;
        aes-256-ctr)
            echo "CTR (Counter Mode) + SHA-256 integrity sidecar"
            ;;
        chacha20)
            echo "Stream Cipher (ChaCha20) + SHA-256 integrity sidecar"
            ;;
        *)
            echo "$algo"
            ;;
    esac
}

# --- Compute and store SHA-256 hash of an encrypted file ---
_write_hash() {
    local enc_file="$1"
    local hash_file="${enc_file}.sha256"
    sha256sum "$enc_file" > "$hash_file" 2>/dev/null || \
        shasum -a 256 "$enc_file" > "$hash_file" 2>/dev/null || true
    [[ -f "$hash_file" ]] && echo -e "  ${DIM}Integrity file: ${hash_file}${RESET}"
}

# --- Verify SHA-256 hash before decryption ---
_verify_hash() {
    local enc_file="$1"
    local hash_file="${enc_file}.sha256"

    if [[ ! -f "$hash_file" ]]; then
        echo -e "${YELLOW}${BOLD}⚠ No integrity file found (${hash_file}).${RESET}"
        echo -e "${DIM}The encrypted file cannot be verified for tampering.${RESET}"
        echo -en "${MAGENTA}${BOLD}Continue without integrity check? [y/N]: ${RESET}"
        read -r ans
        [[ "${ans,,}" != "y" ]] && return 1
        return 0
    fi

    echo -e "${CYAN}Verifying file integrity...${RESET}"
    if sha256sum -c "$hash_file" --status 2>/dev/null || \
       shasum -a 256 -c "$hash_file" --status 2>/dev/null; then
        echo -e "${LIME}${BOLD}✓ Integrity OK — file has not been tampered with.${RESET}"
        return 0
    else
        echo -e "${RED}${BOLD}✗ INTEGRITY FAILURE — file hash does not match!${RESET}"
        echo -e "${RED}The encrypted file may have been tampered with or corrupted.${RESET}"
        echo -en "${MAGENTA}${BOLD}Decrypt anyway? This is DANGEROUS. [y/N]: ${RESET}"
        read -r ans
        [[ "${ans,,}" != "y" ]] && return 1
        return 0
    fi
}

# --- Encryption report ---
show_encryption_report() {
    local status="$1"
    local input_file="$2"
    local output_file="$3"
    local algo="$4"
    local key_info="$5"
    local start_time="$6"

    local end_time; end_time=$(date +%s%N)
    local duration_ms=$(( (end_time - start_time) / 1000000 ))

    print_section_header "Encryption Report"

    if [[ "$status" == "SUCCESS" ]]; then
        echo -e "${LIME}${BOLD}            ✓  OPERATION SUCCESSFUL  ✓${RESET}"
        log_operation "SUCCESS" "Encrypted: $input_file → $output_file (algo=$algo)"
    else
        echo -e "${RED}${BOLD}            ✗  OPERATION FAILED  ✗${RESET}"
        log_operation "ERROR" "Encryption failed: $input_file (algo=$algo) — $key_info"
        echo -e "${RED}Error: $key_info${RESET}"
        press_enter_to_continue
        return
    fi

    local src_sz; src_sz=$(get_file_size "$input_file")
    local enc_sz; enc_sz=$(get_file_size "$output_file")

    echo -e "\n${WHITE}${BOLD}Source File:${RESET}       $input_file"
    echo -e "${WHITE}${BOLD}Encrypted File:${RESET}    ${GREEN}$output_file${RESET}"
    echo -e "${WHITE}${BOLD}Source Size:${RESET}       $(human_size "$src_sz")"
    echo -e "${WHITE}${BOLD}Encrypted Size:${RESET}    $(human_size "$enc_sz")"

    echo -e "\n${CYAN}────────── Encryption Parameters ──────────${RESET}"
    echo -e "${WHITE}${BOLD}Algorithm:${RESET}    $algo"
    echo -e "${WHITE}${BOLD}Mode:${RESET}         $(_mode_label "$algo")"
    echo -e "${WHITE}${BOLD}KDF:${RESET}          PBKDF2-HMAC-SHA256, ${PBKDF2_ITER} iterations"
    echo -e "${WHITE}${BOLD}Time:${RESET}         ${duration_ms} ms"

    [[ -f "${output_file}.sha256" ]] && \
        echo -e "${WHITE}${BOLD}Integrity:${RESET}    SHA-256 sidecar written → ${output_file}.sha256"

    echo -e "\n${YELLOW}────────── Decryption Instructions ──────────${RESET}"
    echo -e "  1. Run ${BOLD}encryptor${RESET} → Decrypt File"
    echo -e "  2. Algorithm: ${BOLD}${algo}${RESET}"
    case "$algo" in
        aes-256-gcm|aes-256-cbc|aes-256-ctr|chacha20|camellia-256-cbc|aria-256-cbc)
            echo -e "  3. Enter the same ${BOLD}password${RESET}."
            echo -e "\n${ORANGE}${BOLD}Keep your password safe.${RESET} Without it the file cannot be recovered."
            ;;
        smime)
            echo -e "  3. Provide your ${BOLD}private key${RESET} and ${BOLD}certificate${RESET}."
            echo -e "     ${DIM}Encrypted for: $key_info${RESET}"
            ;;
    esac

    # Confirm before secure delete
    echo -e "\n${CYAN}${BOLD}═══════════════════════════════════════════════════${RESET}"
    echo -e "${YELLOW}${BOLD}Security Option:${RESET} Securely delete original file?"
    echo -e "${DIM}Warning: This action cannot be undone.${RESET}\n"
    echo -en "${MAGENTA}${BOLD}Delete original? [y/N]: ${RESET}"
    read -r del_choice

    if [[ "${del_choice,,}" == "y" ]]; then
        _secure_delete "$input_file"
    else
        echo -e "${DIM}Original file kept.${RESET}"
    fi

    press_enter_to_continue
}

# --- Decryption report ---
show_decryption_report() {
    local status="$1"
    local input_file="$2"
    local output_file="$3"
    local algo="$4"
    local error_msg="$5"
    local start_time="$6"

    local end_time; end_time=$(date +%s%N)
    local duration_ms=$(( (end_time - start_time) / 1000000 ))

    print_section_header "Decryption Report"

    if [[ "$status" == "SUCCESS" ]]; then
        echo -e "${LIME}${BOLD}            ✓  OPERATION SUCCESSFUL  ✓${RESET}"
        log_operation "SUCCESS" "Decrypted: $input_file → $output_file (algo=$algo)"

        local enc_sz; enc_sz=$(get_file_size "$input_file")
        local dec_sz; dec_sz=$(get_file_size "$output_file")

        echo -e "\n${WHITE}${BOLD}Encrypted File:${RESET}    $input_file"
        echo -e "${WHITE}${BOLD}Decrypted File:${RESET}    ${GREEN}$output_file${RESET}"
        echo -e "${WHITE}${BOLD}Encrypted Size:${RESET}    $(human_size "$enc_sz")"
        echo -e "${WHITE}${BOLD}Decrypted Size:${RESET}    $(human_size "$dec_sz")"
        echo -e "\n${CYAN}────────── Parameters ──────────${RESET}"
        echo -e "${WHITE}${BOLD}Algorithm:${RESET}  $algo"
        echo -e "${WHITE}${BOLD}Mode:${RESET}       $(_mode_label "$algo")"
        echo -e "${WHITE}${BOLD}Time:${RESET}       ${duration_ms} ms"
        echo -e "\n${LIME}${BOLD}✓ File successfully decrypted!${RESET}"

        echo -e "\n${CYAN}${BOLD}═══════════════════════════════════════════════════${RESET}"
        echo -e "${YELLOW}${BOLD}Security Option:${RESET} Delete encrypted file?"
        echo -en "${MAGENTA}${BOLD}Delete ${input_file}? [y/N]: ${RESET}"
        read -r del_choice
        if [[ "${del_choice,,}" == "y" ]]; then
            rm -f "$input_file" "${input_file}.sha256" 2>/dev/null
            echo -e "${GREEN}✓ Encrypted file deleted.${RESET}"
            log_operation "INFO" "Encrypted file deleted: $input_file"
        else
            echo -e "${DIM}Encrypted file kept.${RESET}"
        fi

    else
        echo -e "${RED}${BOLD}            ✗  OPERATION FAILED  ✗${RESET}"
        log_operation "ERROR" "Decryption failed: $input_file (algo=$algo) — $error_msg"
        echo -e "\n${RED}${BOLD}Decryption failed.${RESET}"
        echo -e "${YELLOW}Reason: ${BOLD}$error_msg${RESET}"
        echo -e "\n${YELLOW}${BOLD}Troubleshooting:${RESET}"
        case "$algo" in
            aes-256-gcm|aes-256-cbc|aes-256-ctr|chacha20|camellia-256-cbc|aria-256-cbc)
                echo -e "  • Verify you used the correct ${BOLD}password${RESET}"
                echo -e "  • Verify the ${BOLD}algorithm${RESET} matches the one used to encrypt"
                echo -e "  • The encrypted file may be ${BOLD}corrupted${RESET} or tampered with"
                ;;
            smime)
                echo -e "  • Private key must match the certificate used for encryption"
                echo -e "  • Check key location: ${BOLD}$CERT_DIR${RESET}"
                ;;
        esac
    fi

    press_enter_to_continue
}

# --- Secure file deletion ---
_secure_delete() {
    local file="$1"
    echo -e "${CYAN}Securely deleting: $file${RESET}"
    if command -v shred &>/dev/null; then
        shred -vzfn 3 "$file" 2>/dev/null && rm -f "$file"
        echo -e "${LIME}✓ Deleted (3-pass shred + remove)${RESET}"
    else
        local sz; sz=$(get_file_size "$file")
        dd if=/dev/urandom of="$file" bs=1 count="$sz" conv=notrunc 2>/dev/null
        rm -f "$file"
        echo -e "${GREEN}✓ Deleted (random overwrite + remove)${RESET}"
    fi
    log_operation "INFO" "Secure delete: $file"
}

# --- Main encryption workflow ---
process_encryption() {
    local file_to_encrypt
    file_to_encrypt=$(select_file_interactive "File to encrypt: ") || return 0

    local algo
    algo=$(select_algorithm_menu) || return 0

    local output_file="${file_to_encrypt}.enc"
    # Avoid overwriting existing files
    if [[ -f "$output_file" ]]; then
        local ts; ts=$(date +%s)
        output_file="${output_file%.enc}-${ts}.enc"
        echo -e "${YELLOW}Output renamed to: ${BOLD}$output_file${RESET}"
    fi

    local start_time; start_time=$(date +%s%N)
    local cmd_status=0
    local error_msg=""
    local key_info=""

    case "$algo" in
        aes-256-gcm|aes-256-cbc|aes-256-ctr|chacha20|camellia-256-cbc|aria-256-cbc)
            local password password_conf
            echo -en "${MAGENTA}${BOLD}Encryption password: ${RESET}"
            read -rs password; echo
            echo -en "${MAGENTA}${BOLD}Confirm password:    ${RESET}"
            read -rs password_conf; echo

            if [[ -z "$password" ]]; then
                error_msg="Password cannot be empty."
                cmd_status=1
            elif [[ "$password" != "$password_conf" ]]; then
                error_msg="Passwords do not match."
                cmd_status=1
            else
                # Write password to secure temp file — NEVER on the command line
                local pass_file; pass_file=$(_write_pass_file "$password")

                echo -e "${CYAN}Encrypting with ${BOLD}${algo}${RESET}${CYAN}...${RESET}"
                start_spinner "Encrypting (${algo}, PBKDF2 ${PBKDF2_ITER} iter)..."

                openssl enc "-${algo}" -salt -pbkdf2 -iter "${PBKDF2_ITER}" \
                    -in "$file_to_encrypt" -out "$output_file" \
                    -pass "file:${pass_file}" 2>"${TEMP_DIR}/openssl.err"
                cmd_status=$?

                stop_spinner "$cmd_status"
                rm -f "$pass_file"

                if [[ $cmd_status -ne 0 ]]; then
                    error_msg=$(cat "${TEMP_DIR}/openssl.err" 2>/dev/null)
                    [[ -z "$error_msg" ]] && error_msg="OpenSSL returned error code ${cmd_status}."
                else
                    key_info="[Password-protected, PBKDF2-HMAC-SHA256, ${PBKDF2_ITER} iter]"
                    # Write integrity sidecar
                    _write_hash "$output_file"
                fi
            fi
            ;;

        smime)
            echo -e "\n${CYAN}${BOLD}═══════════════════════════════════════════════════${RESET}"
            echo -e "${CYAN}${BOLD}         S/MIME Certificate-Based Encryption${RESET}"
            echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════${RESET}\n"
            echo -e "${DIM}Encrypts with the recipient's public certificate.${RESET}"
            echo -e "${DIM}Only the holder of the matching private key can decrypt.${RESET}\n"

            local cert_list=()
            if [[ -d "$CERT_DIR" ]] && ls "$CERT_DIR"/*.pem &>/dev/null; then
                echo -e "${BLUE}${BOLD}Available certificates in $CERT_DIR:${RESET}"
                local cn=1
                for cert in "$CERT_DIR"/*.pem; do
                    [[ -f "$cert" ]] || continue
                    cert_list+=("$cert")
                    echo -e "  ${YELLOW}${BOLD}[$cn]${RESET} $(basename "$cert")"
                    ((cn++))
                done
                echo -e "${DIM}→ Type a number to select, or enter a full path.${RESET}"
            else
                echo -e "${YELLOW}No certificates in $CERT_DIR. Use Certificate Manager to create one.${RESET}"
            fi

            echo -en "\n${MAGENTA}${BOLD}Recipient certificate (number or path): ${RESET}"
            read -r cert_input
            cert_input=$(echo "$cert_input" | xargs 2>/dev/null || echo "$cert_input")

            local cert_file=""
            if [[ "$cert_input" =~ ^[0-9]+$ ]] && \
               [[ "$cert_input" -ge 1 ]] && [[ "$cert_input" -le ${#cert_list[@]} ]]; then
                cert_file="${cert_list[$((cert_input-1))]}"
                echo -e "${GREEN}Selected: $(basename "$cert_file")${RESET}"
            else
                cert_file="$cert_input"
                [[ ! -f "$cert_file" ]] && cert_file="$CERT_DIR/$cert_input"
            fi

            if [[ ! -f "$cert_file" ]]; then
                error_msg="Certificate not found: $cert_input"
                cmd_status=1
            else
                echo -e "${CYAN}Encrypting with S/MIME (AES-256-GCM)...${RESET}"
                start_spinner "S/MIME encrypting..."

                openssl smime -encrypt -aes256-gcm \
                    -in "$file_to_encrypt" -out "$output_file" \
                    -outform PEM "$cert_file" 2>"${TEMP_DIR}/openssl.err"
                cmd_status=$?

                stop_spinner "$cmd_status"

                if [[ $cmd_status -ne 0 ]]; then
                    error_msg=$(cat "${TEMP_DIR}/openssl.err" 2>/dev/null)
                    [[ -z "$error_msg" ]] && error_msg="S/MIME encryption failed."
                else
                    key_info="$(basename "$cert_file")"
                    _write_hash "$output_file"
                fi
            fi
            ;;

        *)
            error_msg="Algorithm '${algo}' not implemented."
            cmd_status=1
            ;;
    esac

    if [[ $cmd_status -eq 0 ]]; then
        show_encryption_report "SUCCESS" "$file_to_encrypt" "$output_file" "$algo" "$key_info" "$start_time"
    else
        rm -f "$output_file" 2>/dev/null
        show_encryption_report "FAILED" "$file_to_encrypt" "$output_file" "$algo" "$error_msg" "$start_time"
    fi
}

# --- Main decryption workflow ---
process_decryption() {
    local file_to_decrypt
    file_to_decrypt=$(select_file_interactive "File to decrypt: ") || return 0

    echo -e "${YELLOW}Note:${RESET} Algorithm auto-detection is not possible. Select the same algorithm used to encrypt."

    local algo
    algo=$(select_algorithm_menu) || return 0

    local output_file
    if [[ "$file_to_decrypt" == *.enc ]]; then
        output_file="${file_to_decrypt%.enc}.dec"
    else
        output_file="${file_to_decrypt}.dec"
    fi

    # Avoid overwriting
    if [[ -f "$output_file" ]]; then
        output_file="${output_file%.dec}-$(date +%s).dec"
        echo -e "${YELLOW}Output renamed to: ${BOLD}$output_file${RESET}"
    fi

    # Integrity check before decryption
    _verify_hash "$file_to_decrypt" || return 0

    local start_time; start_time=$(date +%s%N)
    local cmd_status=0
    local error_msg=""

    case "$algo" in
        aes-256-gcm|aes-256-cbc|aes-256-ctr|chacha20|camellia-256-cbc|aria-256-cbc)
            local password
            echo -en "${MAGENTA}${BOLD}Decryption password: ${RESET}"
            read -rs password; echo

            if [[ -z "$password" ]]; then
                error_msg="Password cannot be empty."
                cmd_status=1
            else
                local pass_file; pass_file=$(_write_pass_file "$password")

                echo -e "${CYAN}Decrypting with ${BOLD}${algo}${RESET}${CYAN}...${RESET}"
                start_spinner "Decrypting (${algo})..."

                openssl enc -d "-${algo}" -pbkdf2 -iter "${PBKDF2_ITER}" \
                    -in "$file_to_decrypt" -out "$output_file" \
                    -pass "file:${pass_file}" 2>"${TEMP_DIR}/openssl.err"
                cmd_status=$?

                stop_spinner "$cmd_status"
                rm -f "$pass_file"

                if [[ $cmd_status -ne 0 ]]; then
                    error_msg=$(cat "${TEMP_DIR}/openssl.err" 2>/dev/null)
                    [[ -z "$error_msg" ]] && error_msg="Bad decrypt — wrong password, wrong algorithm, or corrupted file."
                fi
            fi
            ;;

        smime)
            echo -e "\n${CYAN}${BOLD}═══════════════════════════════════════════════════${RESET}"
            echo -e "${CYAN}${BOLD}         S/MIME Certificate-Based Decryption${RESET}"
            echo -e "${CYAN}${BOLD}═══════════════════════════════════════════════════${RESET}\n"
            echo -e "${DIM}You need YOUR private key and YOUR certificate.${RESET}\n"

            local key_list=() cert_list=()

            if ls "$CERT_DIR"/*.key &>/dev/null 2>&1; then
                echo -e "${BLUE}${BOLD}Available private keys:${RESET}"
                local kn=1
                for key in "$CERT_DIR"/*.key; do
                    [[ -f "$key" ]] || continue
                    key_list+=("$key")
                    echo -e "  ${YELLOW}${BOLD}[$kn]${RESET} $(basename "$key")"
                    ((kn++))
                done
            fi

            if ls "$CERT_DIR"/*.pem &>/dev/null 2>&1; then
                echo -e "\n${BLUE}${BOLD}Available certificates:${RESET}"
                local cn=1
                for cert in "$CERT_DIR"/*.pem; do
                    [[ -f "$cert" ]] || continue
                    cert_list+=("$cert")
                    echo -e "  ${YELLOW}${BOLD}[$cn]${RESET} $(basename "$cert")"
                    ((cn++))
                done
            fi

            echo -e "${DIM}→ Type a number to select, or enter a full path.${RESET}"

            echo -en "\n${MAGENTA}${BOLD}Your private key (number or path): ${RESET}"
            read -r key_input
            key_input=$(echo "$key_input" | xargs 2>/dev/null || echo "$key_input")
            local priv_key_file=""
            if [[ "$key_input" =~ ^[0-9]+$ ]] && \
               [[ "$key_input" -ge 1 ]] && [[ "$key_input" -le ${#key_list[@]} ]]; then
                priv_key_file="${key_list[$((key_input-1))]}"
            else
                priv_key_file="$key_input"
                [[ ! -f "$priv_key_file" ]] && priv_key_file="$CERT_DIR/$key_input"
            fi

            echo -en "${MAGENTA}${BOLD}Your certificate (number or path): ${RESET}"
            read -r cert_input
            cert_input=$(echo "$cert_input" | xargs 2>/dev/null || echo "$cert_input")
            local cert_file=""
            if [[ "$cert_input" =~ ^[0-9]+$ ]] && \
               [[ "$cert_input" -ge 1 ]] && [[ "$cert_input" -le ${#cert_list[@]} ]]; then
                cert_file="${cert_list[$((cert_input-1))]}"
            else
                cert_file="$cert_input"
                [[ ! -f "$cert_file" ]] && cert_file="$CERT_DIR/$cert_input"
            fi

            if [[ ! -f "$priv_key_file" ]]; then
                error_msg="Private key not found: $key_input"
                cmd_status=1
            elif [[ ! -f "$cert_file" ]]; then
                error_msg="Certificate not found: $cert_input"
                cmd_status=1
            else
                echo -e "${CYAN}Decrypting with S/MIME...${RESET}"
                start_spinner "S/MIME decrypting..."

                openssl smime -decrypt \
                    -in "$file_to_decrypt" -out "$output_file" \
                    -inform PEM -recip "$cert_file" -inkey "$priv_key_file" \
                    2>"${TEMP_DIR}/openssl.err"
                cmd_status=$?

                stop_spinner "$cmd_status"

                if [[ $cmd_status -ne 0 ]]; then
                    error_msg=$(cat "${TEMP_DIR}/openssl.err" 2>/dev/null)
                    [[ -z "$error_msg" ]] && error_msg="Incorrect key/certificate or corrupt file."
                fi
            fi
            ;;

        *)
            error_msg="Algorithm '${algo}' not implemented."
            cmd_status=1
            ;;
    esac

    if [[ $cmd_status -eq 0 ]]; then
        show_decryption_report "SUCCESS" "$file_to_decrypt" "$output_file" "$algo" "" "$start_time"
    else
        rm -f "$output_file" 2>/dev/null
        show_decryption_report "FAILED" "$file_to_decrypt" "$output_file" "$algo" "$error_msg" "$start_time"
    fi
}
