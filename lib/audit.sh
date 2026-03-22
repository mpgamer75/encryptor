#!/usr/bin/env bash
# ==============================================================================
# lib/audit.sh — Security Audit (local checks + remote SSL/TLS scan)
# ==============================================================================

security_audit_menu() {
    while true; do
        print_section_header "Security Audit"
        echo -e "  ${PURPLE}${BOLD}[1]${RESET} ${WHITE}Local System Audit${RESET}            ${DIM}(7 security checks + score)${RESET}"
        echo -e "  ${PURPLE}${BOLD}[2]${RESET} ${WHITE}Certificate Security Analysis${RESET}  ${DIM}(local certificate deep-dive)${RESET}"
        echo -e "  ${YELLOW}${BOLD}[3]${RESET} ${WHITE}Remote SSL/TLS Scanner${RESET}         ${DIM}(requires testssl.sh)${RESET}"
        echo -e "  ${YELLOW}${BOLD}[4]${RESET} ${WHITE}Install testssl.sh${RESET}             ${DIM}(for remote scanning)${RESET}"
        echo -e "  ${YELLOW}${BOLD}[q]${RESET} ${WHITE}Return to Main Menu${RESET}"

        echo -en "\n${MAGENTA}${BOLD}Your choice: ${RESET}"
        read -r choice
        choice=$(echo "$choice" | tr -d '[:space:]')

        case "$choice" in
            1) _audit_local ;;
            2) _audit_certificate ;;
            3) _audit_remote ;;
            4) _audit_install_testssl ;;
            q|Q) break ;;
            *)
                echo -e "${RED}Invalid choice.${RESET}"
                sleep 1
                ;;
        esac
    done
}

# --- 1. Local System Audit ---
_audit_local() {
    print_section_header "Local System Audit"
    echo -e "${DIM}Running security checks on your local environment...${RESET}\n"

    local score=0
    local max_score=8

    # ── Check 1: OpenSSL version ──────────────────────────────────────────────
    echo -e "${PURPLE}${BOLD}1. OpenSSL Version & Capabilities${RESET}"
    local openssl_version; openssl_version=$(openssl version 2>/dev/null)
    local ver_num; ver_num=$(echo "$openssl_version" | awk '{print $2}')
    echo -e "  ${WHITE}Installed:${RESET} $openssl_version"

    local major; major=$(echo "$ver_num" | cut -d. -f1)
    local minor; minor=$(echo "$ver_num" | cut -d. -f2)
    local patch; patch=$(echo "$ver_num" | cut -d. -f3 | tr -d 'a-z')

    if [[ "$major" -ge 3 ]] || { [[ "$major" -eq 1 ]] && [[ "$minor" -eq 1 ]] && [[ "${patch:-0}" -ge 1 ]]; }; then
        echo -e "  ${LIME}[OK] Version: $ver_num — modern (1.1.1+ or 3.x)${RESET}"
        ((score++))
    else
        echo -e "  ${ORANGE}[!] Version: $ver_num — outdated. Upgrade to OpenSSL 3.x recommended.${RESET}"
    fi

    # Check AES-GCM support
    if openssl enc -aes-256-gcm -help &>/dev/null; then
        echo -e "  ${LIME}[OK] AES-256-GCM: Supported (true AEAD encryption available)${RESET}"
        ((score++))
    else
        echo -e "  ${ORANGE}[!] AES-256-GCM: Not supported — upgrade OpenSSL for authenticated encryption${RESET}"
    fi

    # ── Check 2: Private key permissions ─────────────────────────────────────
    echo -e "\n${PURPLE}${BOLD}2. Private Key Permissions${RESET}"
    if ! ls "$CERT_DIR"/*.key &>/dev/null 2>&1; then
        echo -e "  ${BLUE}[i] No private keys found in $CERT_DIR — OK${RESET}"
        ((score++))
    else
        local insecure=0 total_keys=0
        for key in "$CERT_DIR"/*.key; do
            [[ -f "$key" ]] || continue
            ((total_keys++))
            local perms; perms=$(stat -c "%a" "$key" 2>/dev/null || stat -f "%Lp" "$key" 2>/dev/null)
            if [[ "$perms" != "400" && "$perms" != "600" ]]; then
                echo -e "  ${RED}[X] Insecure: $(basename "$key") (mode: $perms)${RESET}"
                echo -e "      ${DIM}Fix: chmod 400 $key${RESET}"
                ((insecure++))
            fi
        done
        if [[ $insecure -eq 0 ]]; then
            echo -e "  ${LIME}[OK] All $total_keys key(s) have secure permissions (400/600)${RESET}"
            ((score++))
        else
            echo -e "  ${RED}[X] $insecure/$total_keys key(s) have insecure permissions${RESET}"
        fi
    fi

    # ── Check 3: Certificate expiration ──────────────────────────────────────
    echo -e "\n${PURPLE}${BOLD}3. Certificate Expiration${RESET}"
    if ! ls "$CERT_DIR"/*.pem &>/dev/null 2>&1; then
        echo -e "  ${BLUE}[i] No certificates found — OK${RESET}"
        ((score++))
    else
        local expired=0 expiring=0 total_certs=0
        for cert in "$CERT_DIR"/*.pem; do
            [[ -f "$cert" ]] || continue
            ((total_certs++))
            openssl x509 -in "$cert" -noout -checkend 0 &>/dev/null || { ((expired++)); continue; }
            openssl x509 -in "$cert" -noout -checkend 2592000 &>/dev/null || ((expiring++))
        done
        if [[ $expired -eq 0 && $expiring -eq 0 ]]; then
            echo -e "  ${LIME}[OK] All $total_certs cert(s) valid and not expiring soon${RESET}"
            ((score++))
        elif [[ $expired -eq 0 ]]; then
            echo -e "  ${ORANGE}[!] $expiring/$total_certs cert(s) expiring within 30 days${RESET}"
            ((score++))
        else
            echo -e "  ${RED}[X] $expired expired, $expiring expiring soon (of $total_certs)${RESET}"
        fi
    fi

    # ── Check 4: Config directory permissions ─────────────────────────────────
    echo -e "\n${PURPLE}${BOLD}4. Configuration Directory Security${RESET}"
    if [[ -d "$CONFIG_DIR" ]]; then
        local dir_perms; dir_perms=$(stat -c "%a" "$CONFIG_DIR" 2>/dev/null || stat -f "%Lp" "$CONFIG_DIR")
        if [[ "$dir_perms" == "700" ]] || [[ "$dir_perms" == "755" ]]; then
            echo -e "  ${LIME}[OK] $CONFIG_DIR — permissions: $dir_perms${RESET}"
            ((score++))
        else
            echo -e "  ${ORANGE}[!] Unusual permissions: $dir_perms (recommended: 700)${RESET}"
            echo -e "      ${DIM}Fix: chmod 700 $CONFIG_DIR${RESET}"
        fi
    else
        echo -e "  ${BLUE}[i] Config directory not yet created — OK${RESET}"
        ((score++))
    fi

    # ── Check 5: Temp files ───────────────────────────────────────────────────
    echo -e "\n${PURPLE}${BOLD}5. Stale Temporary Files${RESET}"
    local old_tmps; old_tmps=$(find /tmp -maxdepth 1 -name "encryptor_*" -type d -mtime +1 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$old_tmps" -eq 0 ]]; then
        echo -e "  ${LIME}[OK] No stale encryptor temp directories${RESET}"
        ((score++))
    else
        echo -e "  ${ORANGE}[!] $old_tmps old temp director(ies) found in /tmp${RESET}"
        echo -e "      ${DIM}Run: rm -rf /tmp/encryptor_*${RESET}"
        ((score++))  # Low severity — auto-cleaned on next launch
    fi

    # ── Check 6: Bash version ─────────────────────────────────────────────────
    echo -e "\n${PURPLE}${BOLD}6. Shell Environment${RESET}"
    local bash_ver; bash_ver=$(bash --version 2>/dev/null | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    local bash_major; bash_major=$(echo "$bash_ver" | cut -d. -f1)
    if [[ "${bash_major:-0}" -ge 5 ]]; then
        echo -e "  ${LIME}[OK] Bash $bash_ver — excellent (5.x+)${RESET}"
        ((score++))
    elif [[ "${bash_major:-0}" -ge 4 ]]; then
        echo -e "  ${GREEN}[OK] Bash $bash_ver — supported (4.x)${RESET}"
        ((score++))
    else
        echo -e "  ${ORANGE}[!] Bash $bash_ver — upgrade to 4.0+ recommended${RESET}"
    fi

    # ── Check 7: Integrity sidecar files ─────────────────────────────────────
    echo -e "\n${PURPLE}${BOLD}7. Encrypted File Integrity Sidecars${RESET}"
    local enc_files; enc_files=$(find . -maxdepth 2 -name "*.enc" 2>/dev/null | wc -l | tr -d ' ')
    local sha_files; sha_files=$(find . -maxdepth 2 -name "*.enc.sha256" 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$enc_files" -eq 0 ]]; then
        echo -e "  ${BLUE}[i] No .enc files in current directory${RESET}"
        ((score++))
    elif [[ "$sha_files" -ge "$enc_files" ]]; then
        echo -e "  ${LIME}[OK] All $enc_files .enc file(s) have SHA-256 integrity sidecar${RESET}"
        ((score++))
    else
        local missing=$(( enc_files - sha_files ))
        echo -e "  ${ORANGE}[!] $missing .enc file(s) missing .sha256 sidecar (tamper detection unavailable)${RESET}"
    fi

    # ── Check 8: PBKDF2 iteration sanity ─────────────────────────────────────
    echo -e "\n${PURPLE}${BOLD}8. PBKDF2 Configuration${RESET}"
    if [[ "${PBKDF2_ITER:-0}" -ge 600000 ]]; then
        echo -e "  ${LIME}[OK] PBKDF2 iterations: ${PBKDF2_ITER} — meets NIST SP 800-132 & OWASP 2024${RESET}"
        ((score++))
    else
        echo -e "  ${ORANGE}[!] PBKDF2 iterations: ${PBKDF2_ITER:-unknown} — below OWASP 2024 recommendation (600,000)${RESET}"
    fi

    # ── Summary ───────────────────────────────────────────────────────────────
    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${RESET}"
    local pct=$(( score * 100 / max_score ))
    if [[ $pct -ge 90 ]]; then
        echo -e "${LIME}${BOLD}  Security Score: ${score}/${max_score} (${pct}%) — Excellent 🛡${RESET}"
    elif [[ $pct -ge 75 ]]; then
        echo -e "${GREEN}${BOLD}  Security Score: ${score}/${max_score} (${pct}%) — Good${RESET}"
    elif [[ $pct -ge 50 ]]; then
        echo -e "${YELLOW}${BOLD}  Security Score: ${score}/${max_score} (${pct}%) — Acceptable — review warnings above${RESET}"
    else
        echo -e "${RED}${BOLD}  Security Score: ${score}/${max_score} (${pct}%) — Needs Improvement${RESET}"
    fi
    echo -e "${CYAN}═══════════════════════════════════════════════════════════════${RESET}"

    log_operation "INFO" "Local audit completed: ${score}/${max_score}"
    press_enter_to_continue
}

# --- 2. Certificate Security Analysis ---
_audit_certificate() {
    print_section_header "Certificate Security Analysis"
    echo -e "${DIM}Deep security analysis of a local X.509 certificate.${RESET}\n"

    if ! ls "$CERT_DIR"/*.pem &>/dev/null 2>&1; then
        echo -e "${YELLOW}No certificates in $CERT_DIR.${RESET}"
        echo -e "${DIM}Use Certificate Manager → [1] to create a CA first.${RESET}"
        press_enter_to_continue; return
    fi

    echo -e "${BLUE}Available certificates:${RESET}"
    local cn=1
    local cert_list=()
    for cert in "$CERT_DIR"/*.pem; do
        [[ -f "$cert" ]] || continue
        cert_list+=("$cert")
        echo -e "  ${YELLOW}[$cn]${RESET} $(basename "$cert")"
        ((cn++))
    done

    echo -en "\n${MAGENTA}Certificate (number or path): ${RESET}"
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

    if [[ ! -f "$cert_file" ]]; then
        echo -e "${RED}Certificate not found!${RESET}"
        press_enter_to_continue; return
    fi

    print_section_header "Analysis: $(basename "$cert_file")"

    # 1. Basic info
    echo -e "${CYAN}${BOLD}1. Identity${RESET}"
    local subject; subject=$(openssl x509 -in "$cert_file" -noout -subject 2>/dev/null | sed 's/subject=//')
    local issuer;  issuer=$(openssl x509 -in "$cert_file" -noout -issuer  2>/dev/null | sed 's/issuer=//')
    local serial;  serial=$(openssl x509 -in "$cert_file" -noout -serial  2>/dev/null | cut -d= -f2)
    echo -e "  ${WHITE}Subject:${RESET}  ${DIM}$subject${RESET}"
    echo -e "  ${WHITE}Issuer:${RESET}   ${DIM}$issuer${RESET}"
    echo -e "  ${WHITE}Serial:${RESET}   ${DIM}$serial${RESET}"

    # 2. Validity
    echo -e "\n${CYAN}${BOLD}2. Validity${RESET}"
    local not_before; not_before=$(openssl x509 -in "$cert_file" -noout -startdate 2>/dev/null | cut -d= -f2)
    local not_after;  not_after=$(openssl x509 -in "$cert_file" -noout -enddate   2>/dev/null | cut -d= -f2)
    echo -e "  ${WHITE}From:${RESET}   $not_before"
    echo -e "  ${WHITE}Until:${RESET}  $not_after"

    openssl x509 -in "$cert_file" -noout -checkend 0 &>/dev/null
    if [[ $? -eq 0 ]]; then
        openssl x509 -in "$cert_file" -noout -checkend 2592000 &>/dev/null
        [[ $? -ne 0 ]] && echo -e "  ${ORANGE}[!] Expiring within 30 days${RESET}" || \
                          echo -e "  ${LIME}[OK] Valid${RESET}"
    else
        echo -e "  ${RED}[X] EXPIRED${RESET}"
    fi

    # 3. Key strength
    echo -e "\n${CYAN}${BOLD}3. Key Strength${RESET}"
    local key_algo; key_algo=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep "Public Key Algorithm" | awk '{print $NF}')
    local key_bits; key_bits=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep -oE 'Public-Key: \([0-9]+ bit\)' | grep -oE '[0-9]+')
    echo -e "  ${WHITE}Algorithm:${RESET} $key_algo"
    echo -e "  ${WHITE}Key Size:${RESET}  ${BOLD}${key_bits} bits${RESET}"

    if [[ "$key_algo" == *"rsaEncryption"* ]]; then
        if   [[ "${key_bits:-0}" -ge 4096 ]]; then echo -e "  ${LIME}[OK] Strength: Excellent (4096+ bit RSA)${RESET}"
        elif [[ "${key_bits:-0}" -ge 2048 ]]; then echo -e "  ${GREEN}[OK] Strength: Good (2048+ bit RSA)${RESET}"
        elif [[ "${key_bits:-0}" -ge 1024 ]]; then echo -e "  ${ORANGE}[!] Strength: Weak — upgrade to ≥2048 bit${RESET}"
        else                                        echo -e "  ${RED}[X] Strength: Insecure — DO NOT USE${RESET}"; fi
    elif [[ "$key_algo" == *"id-ecPublicKey"* ]]; then
        if [[ "${key_bits:-0}" -ge 256 ]]; then echo -e "  ${LIME}[OK] ECDSA: Good (≥256 bit)${RESET}"
        else                                     echo -e "  ${ORANGE}[!] ECDSA curve may be weak${RESET}"; fi
    fi

    # 4. Signature algorithm
    echo -e "\n${CYAN}${BOLD}4. Signature Algorithm${RESET}"
    local sig_algo; sig_algo=$(openssl x509 -in "$cert_file" -noout -text 2>/dev/null | grep "Signature Algorithm" | head -1 | awk '{print $3}')
    echo -e "  ${WHITE}Algorithm:${RESET} $sig_algo"
    if   [[ "$sig_algo" == *"sha256"* || "$sig_algo" == *"sha384"* || "$sig_algo" == *"sha512"* ]]; then
        echo -e "  ${LIME}[OK] Modern (SHA-256/384/512)${RESET}"
    elif [[ "$sig_algo" == *"sha1"* ]]; then
        echo -e "  ${RED}[X] SHA-1 is deprecated — do not use for new certificates${RESET}"
    elif [[ "$sig_algo" == *"md5"* ]]; then
        echo -e "  ${RED}[X] MD5 is broken — replace immediately${RESET}"
    fi

    # 5. Self-signed?
    echo -e "\n${CYAN}${BOLD}5. Certificate Type${RESET}"
    [[ "$subject" == "$issuer" ]] && \
        echo -e "  ${BLUE}[i] Self-signed (Root CA or test certificate)${RESET}" || \
        echo -e "  ${GREEN}[OK] CA-signed${RESET}"

    # 6. Fingerprints
    echo -e "\n${CYAN}${BOLD}6. Fingerprints${RESET}"
    local fp256; fp256=$(openssl x509 -in "$cert_file" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)
    local fp1;   fp1=$(openssl x509 -in "$cert_file" -noout -fingerprint -sha1   2>/dev/null | cut -d= -f2)
    echo -e "  ${WHITE}SHA-256:${RESET} ${DIM}$fp256${RESET}"
    echo -e "  ${WHITE}SHA-1:${RESET}   ${DIM}$fp1${RESET}  ${ORANGE}(SHA-1 for reference only)${RESET}"

    echo -e "\n${CYAN}═══════════════════════════════════════════════════════════════${RESET}"
    echo -e "${WHITE}${BOLD}Analysis complete.${RESET}"
    press_enter_to_continue
}

# --- 3. Remote SSL/TLS Scan ---
_audit_remote() {
    if [[ ! -f "$TESTSSL_PATH" ]]; then
        echo -e "\n${YELLOW}testssl.sh is not installed.${RESET}"
        echo -e "${DIM}Use option [4] to install it.${RESET}"
        press_enter_to_continue; return
    fi

    print_section_header "Remote SSL/TLS Scanner"
    echo -e "${DIM}Full SSL/TLS scan of a remote server using testssl.sh.${RESET}\n"

    echo -en "${MAGENTA}${BOLD}Domain or IP to scan (e.g., example.com): ${RESET}"
    read -r domain
    domain=$(echo "$domain" | xargs 2>/dev/null || echo "$domain")

    if [[ -z "$domain" ]]; then
        echo -e "${RED}No target provided.${RESET}"
        press_enter_to_continue; return
    fi

    # Basic input validation — no spaces, semicolons, or backticks
    if [[ "$domain" =~ [[:space:]\;\`\|] ]]; then
        echo -e "${RED}Invalid characters in domain/IP.${RESET}"
        press_enter_to_continue; return
    fi

    echo -e "\n${CYAN}Scanning ${BOLD}${domain}${RESET}${CYAN}...${RESET}"
    echo -e "${DIM}This may take several minutes.${RESET}\n"
    "$TESTSSL_PATH" -p "$domain"
    echo -e "\n${GREEN}Scan complete.${RESET}"
    press_enter_to_continue
}

# --- 4. Install testssl.sh ---
_audit_install_testssl() {
    print_section_header "Install testssl.sh"

    if ! command -v git >/dev/null 2>&1; then
        echo -e "${RED}git is required to install testssl.sh.${RESET}"
        echo -e "${YELLOW}Install git: sudo apt install git${RESET}"
        press_enter_to_continue; return
    fi

    echo -e "${BLUE}Cloning testssl.sh into $TOOLS_DIR/testssl.sh ...${RESET}"
    rm -rf "$TOOLS_DIR/testssl.sh" 2>/dev/null

    if git clone --depth 1 https://github.com/drwetter/testssl.sh.git "$TOOLS_DIR/testssl.sh"; then
        echo -e "${LIME}${BOLD}✓ testssl.sh installed successfully.${RESET}"
        log_operation "INFO" "testssl.sh installed to $TOOLS_DIR/testssl.sh"
    else
        echo -e "${RED}Clone failed. Check your internet connection.${RESET}"
    fi
    press_enter_to_continue
}
