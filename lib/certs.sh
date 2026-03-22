#!/usr/bin/env bash
# ==============================================================================
# lib/certs.sh — X.509 / PKI Certificate Management
# ==============================================================================

manage_certificates() {
    while true; do
        print_section_header "Certificate Manager (X.509 / PKI)"
        echo -e "  ${YELLOW}${BOLD}[1]${RESET} ${WHITE}Create Root Certificate Authority (CA)${RESET}"
        echo -e "  ${YELLOW}${BOLD}[2]${RESET} ${WHITE}Generate Private Key and CSR${RESET}"
        echo -e "  ${YELLOW}${BOLD}[3]${RESET} ${WHITE}Sign Certificate Signing Request (CSR)${RESET}"
        echo -e "  ${YELLOW}${BOLD}[4]${RESET} ${WHITE}Inspect a Certificate or CSR${RESET}"
        echo -e "  ${YELLOW}${BOLD}[5]${RESET} ${WHITE}List managed certificates and keys${RESET}"
        echo -e "  ${PURPLE}${BOLD}[6]${RESET} ${WHITE}Export to PKCS#12 (Windows / browsers / email)${RESET}"
        echo -e "  ${PURPLE}${BOLD}[7]${RESET} ${WHITE}Validate Certificate / Key Pair${RESET}"
        echo -e "  ${PURPLE}${BOLD}[8]${RESET} ${WHITE}Check Certificate Expiration${RESET}"
        echo -e "  ${YELLOW}${BOLD}[q]${RESET} ${WHITE}Return to Main Menu${RESET}"

        echo -en "\n${MAGENTA}${BOLD}Your choice: ${RESET}"
        read -r choice
        choice=$(echo "$choice" | tr -d '[:space:]')

        case "$choice" in
            1) _cert_create_ca ;;
            2) _cert_generate_key_csr ;;
            3) _cert_sign_csr ;;
            4) _cert_inspect ;;
            5) _cert_list ;;
            6) _cert_export_pkcs12 ;;
            7) _cert_validate_pair ;;
            8) _cert_check_expiry ;;
            q|Q) break ;;
            *)
                echo -e "${RED}Invalid choice.${RESET}"
                sleep 1
                ;;
        esac
    done
}

# --- 1. Create Root CA ---
_cert_create_ca() {
    print_section_header "Create Root Certificate Authority (CA)"
    echo -e "${DIM}Creates a self-signed root certificate for your own PKI.${RESET}\n"
    echo -e "${YELLOW}Files created:${RESET}"
    echo -e "  → CA private key (.key) — ${RED}Keep secret${RESET}"
    echo -e "  → CA certificate (.pem) — Distribute publicly\n"

    echo -en "${MAGENTA}${BOLD}CA name [MyRootCA]: ${RESET}"
    read -r ca_name
    ca_name=$(echo "$ca_name" | xargs 2>/dev/null || echo "${ca_name:-MyRootCA}")
    [[ -z "$ca_name" ]] && ca_name="MyRootCA"

    local ca_key="$CERT_DIR/${ca_name}.key"
    local ca_cert="$CERT_DIR/${ca_name}.pem"

    if [[ -f "$ca_key" ]] || [[ -f "$ca_cert" ]]; then
        echo -e "\n${RED}${BOLD}Error:${RESET} Files for CA '$ca_name' already exist."
        [[ -f "$ca_key" ]]  && echo -e "  → $ca_key"
        [[ -f "$ca_cert" ]] && echo -e "  → $ca_cert"
        echo -e "${DIM}Choose a different name or delete the existing files first.${RESET}"
        press_enter_to_continue; return
    fi

    echo -e "\n${PURPLE}${BOLD}Certificate Subject Information${RESET}"
    echo -e "${DIM}Press Enter to accept defaults in [brackets].${RESET}\n"

    echo -en "${MAGENTA}Organization Name [Encryptor]: ${RESET}"; read -r org_name
    org_name=$(echo "$org_name" | xargs 2>/dev/null || echo ""); [[ -z "$org_name" ]] && org_name="Encryptor"

    echo -en "${MAGENTA}Department/Unit [Certificate Authority]: ${RESET}"; read -r ou_name
    ou_name=$(echo "$ou_name" | xargs 2>/dev/null || echo ""); [[ -z "$ou_name" ]] && ou_name="Certificate Authority"

    echo -en "${MAGENTA}Country Code (2 letters) [US]: ${RESET}"; read -r country
    country=$(echo "$country" | xargs 2>/dev/null | tr '[:lower:]' '[:upper:]' || echo "")
    [[ -z "$country" ]] && country="US"

    echo -en "${MAGENTA}State/Province [California]: ${RESET}"; read -r state
    state=$(echo "$state" | xargs 2>/dev/null || echo ""); [[ -z "$state" ]] && state="California"

    echo -en "${MAGENTA}City [San Francisco]: ${RESET}"; read -r city
    city=$(echo "$city" | xargs 2>/dev/null || echo ""); [[ -z "$city" ]] && city="San Francisco"

    echo -en "${MAGENTA}Email (optional): ${RESET}"; read -r email
    email=$(echo "$email" | xargs 2>/dev/null || echo "")

    local subject="/C=${country}/ST=${state}/L=${city}/O=${org_name}/OU=${ou_name}/CN=${ca_name}"
    [[ -n "$email" ]] && subject="${subject}/emailAddress=${email}"

    echo -e "\n${CYAN}${BOLD}Certificate Preview:${RESET}"
    echo -e "  ${DIM}Subject:  $subject${RESET}"
    echo -e "  ${DIM}Validity: 10 years${RESET}"
    echo -e "  ${DIM}Key:      RSA 4096-bit${RESET}\n"

    echo -e "${CYAN}Generating CA — this may take a moment...${RESET}"
    start_spinner "Generating 4096-bit RSA key pair..."

    openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 \
        -nodes -keyout "$ca_key" -out "$ca_cert" \
        -subj "$subject" 2>/dev/null

    local rc=$?
    stop_spinner $rc

    if [[ $rc -ne 0 ]]; then
        echo -e "${RED}CA generation failed!${RESET}"
        press_enter_to_continue; return
    fi

    chmod 400 "$ca_key"

    local not_before; not_before=$(openssl x509 -in "$ca_cert" -noout -startdate 2>/dev/null | cut -d= -f2)
    local not_after;  not_after=$(openssl x509 -in "$ca_cert" -noout -enddate   2>/dev/null | cut -d= -f2)
    local serial;     serial=$(openssl x509 -in "$ca_cert" -noout -serial      2>/dev/null | cut -d= -f2)
    local fingerprint; fingerprint=$(openssl x509 -in "$ca_cert" -noout -fingerprint -sha256 2>/dev/null | cut -d= -f2)

    echo -e "\n${LIME}${BOLD}✓ Root CA created successfully!${RESET}\n"
    echo -e "${WHITE}${BOLD}Certificate Details:${RESET}"
    echo -e "  ${YELLOW}Subject:${RESET}      $subject"
    echo -e "  ${YELLOW}Valid From:${RESET}   $not_before"
    echo -e "  ${YELLOW}Valid Until:${RESET}  $not_after ${GREEN}(10 years)${RESET}"
    echo -e "  ${YELLOW}Serial:${RESET}       $serial"
    echo -e "  ${YELLOW}Key:${RESET}          RSA 4096-bit"
    echo -e "  ${YELLOW}Signature:${RESET}    SHA-256 with RSA\n"
    echo -e "${WHITE}${BOLD}Files Created:${RESET}"
    echo -e "  ${RED}[KEY]${RESET}  $ca_key  ${PINK}(mode: 400 — KEEP SECRET!)${RESET}"
    echo -e "  ${GREEN}[CERT]${RESET} $ca_cert\n"
    echo -e "${YELLOW}${BOLD}SHA-256 Fingerprint:${RESET}"
    echo -e "  ${DIM}$fingerprint${RESET}\n"
    echo -e "${PURPLE}${BOLD}Next Steps:${RESET}"
    echo -e "  → Use option [3] to sign CSRs with this CA"
    echo -e "  → Distribute $ca_cert to users who need to trust your certificates"
    echo -e "  → ${PINK}NEVER${RESET} share the .key file"

    log_operation "SUCCESS" "Root CA created: $ca_cert"
    press_enter_to_continue
}

# --- 2. Generate Private Key + CSR ---
_cert_generate_key_csr() {
    print_section_header "Generate Private Key and Certificate Signing Request"
    echo -e "${DIM}Creates a private key and CSR. Send the CSR to a CA for signing.${RESET}\n"

    echo -en "${MAGENTA}${BOLD}Name for this key [my_key]: ${RESET}"
    read -r key_name
    key_name=$(echo "$key_name" | xargs 2>/dev/null || echo ""); [[ -z "$key_name" ]] && key_name="my_key"

    local priv_key="$CERT_DIR/${key_name}.key"
    local csr_file="$CERT_DIR/${key_name}.csr"

    if [[ -f "$priv_key" ]]; then
        echo -e "\n${RED}Error:${RESET} Key '$key_name.key' already exists: $priv_key"
        press_enter_to_continue; return
    fi

    echo -e "${CYAN}Generating 2048-bit RSA key + CSR...${RESET}"
    start_spinner "Generating key pair..."

    openssl req -new -newkey rsa:2048 -sha256 \
        -nodes -keyout "$priv_key" -out "$csr_file" \
        -subj "/C=US/ST=California/L=Local/O=Encryptor/OU=User/CN=${key_name}" 2>/dev/null

    local rc=$?
    stop_spinner $rc

    if [[ $rc -ne 0 ]]; then
        echo -e "${RED}Key generation failed!${RESET}"
        press_enter_to_continue; return
    fi

    chmod 400 "$priv_key"

    echo -e "\n${GREEN}${BOLD}✓ Key and CSR created!${RESET}"
    echo -e "  ${YELLOW}Private Key:${RESET}  $priv_key ${RED}(mode: 400)${RESET}"
    echo -e "  ${YELLOW}CSR:${RESET}          $csr_file\n"
    echo -e "${CYAN}Next:${RESET} Use option [3] to sign with your CA, or send .csr to an external CA."

    log_operation "SUCCESS" "Key+CSR generated: $priv_key / $csr_file"
    press_enter_to_continue
}

# --- 3. Sign CSR with CA ---
_cert_sign_csr() {
    print_section_header "Sign Certificate Signing Request with CA"
    echo -e "${DIM}Signs a CSR using your CA to produce a valid certificate.${RESET}\n"

    echo -e "${BLUE}CSRs in $CERT_DIR:${RESET}"
    local found=0
    for csr in "$CERT_DIR"/*.csr; do
        [[ -f "$csr" ]] && echo -e "  → $(basename "$csr")" && found=1
    done
    [[ $found -eq 0 ]] && echo -e "  ${DIM}(none)${RESET}"

    echo -en "\n${MAGENTA}CSR file path: ${RESET}"; read -r csr_file
    csr_file=$(echo "$csr_file" | xargs 2>/dev/null || echo "$csr_file")
    [[ ! -f "$csr_file" ]] && [[ -f "$CERT_DIR/$csr_file" ]] && csr_file="$CERT_DIR/$csr_file"

    echo -e "\n${BLUE}CA certificates in $CERT_DIR:${RESET}"
    found=0
    for ca in "$CERT_DIR"/*.pem; do
        [[ -f "$ca" ]] && echo -e "  → $(basename "$ca")" && found=1
    done
    [[ $found -eq 0 ]] && echo -e "  ${DIM}(none — create a CA first!)${RESET}"

    echo -en "\n${MAGENTA}CA certificate path (.pem): ${RESET}"; read -r ca_cert
    ca_cert=$(echo "$ca_cert" | xargs 2>/dev/null || echo "$ca_cert")
    [[ ! -f "$ca_cert" ]] && [[ -f "$CERT_DIR/$ca_cert" ]] && ca_cert="$CERT_DIR/$ca_cert"

    echo -en "${MAGENTA}CA private key path (.key): ${RESET}"; read -r ca_key
    ca_key=$(echo "$ca_key" | xargs 2>/dev/null || echo "$ca_key")
    [[ ! -f "$ca_key" ]] && [[ -f "$CERT_DIR/$ca_key" ]] && ca_key="$CERT_DIR/$ca_key"

    if [[ ! -f "$csr_file" ]] || [[ ! -f "$ca_cert" ]] || [[ ! -f "$ca_key" ]]; then
        echo -e "\n${RED}Required files not found:${RESET}"
        [[ ! -f "$csr_file" ]] && echo -e "  CSR: $csr_file"
        [[ ! -f "$ca_cert" ]] && echo -e "  CA cert: $ca_cert"
        [[ ! -f "$ca_key" ]]  && echo -e "  CA key: $ca_key"
        press_enter_to_continue; return
    fi

    local cert_out="$CERT_DIR/$(basename "${csr_file%.csr}").pem"
    echo -e "\n${CYAN}Signing (valid 1 year)...${RESET}"
    start_spinner "Signing certificate..."

    openssl x509 -req -in "$csr_file" -CA "$ca_cert" -CAkey "$ca_key" \
        -CAcreateserial -out "$cert_out" -days 365 -sha256 2>/dev/null

    local rc=$?
    stop_spinner $rc

    if [[ $rc -ne 0 ]]; then
        echo -e "${RED}Signing failed!${RESET}"
    else
        echo -e "\n${GREEN}${BOLD}✓ Certificate signed!${RESET}"
        echo -e "  ${YELLOW}Output:${RESET} $cert_out ${GREEN}(valid 1 year)${RESET}"
        log_operation "SUCCESS" "Signed CSR: $csr_file → $cert_out"
    fi
    press_enter_to_continue
}

# --- 4. Inspect Certificate or CSR ---
_cert_inspect() {
    print_section_header "Inspect Certificate or CSR"

    echo -e "${BLUE}Certificates (.pem) in $CERT_DIR:${RESET}"
    for cert in "$CERT_DIR"/*.pem; do [[ -f "$cert" ]] && echo -e "  → $(basename "$cert")"; done

    echo -e "\n${BLUE}CSRs (.csr) in $CERT_DIR:${RESET}"
    for csr in "$CERT_DIR"/*.csr; do [[ -f "$csr" ]] && echo -e "  → $(basename "$csr")"; done

    echo -en "\n${MAGENTA}File to inspect (name or path): ${RESET}"
    read -r file_to_inspect
    file_to_inspect=$(echo "$file_to_inspect" | xargs 2>/dev/null || echo "$file_to_inspect")
    [[ ! -f "$file_to_inspect" ]] && [[ -f "$CERT_DIR/$file_to_inspect" ]] && \
        file_to_inspect="$CERT_DIR/$file_to_inspect"

    if [[ ! -f "$file_to_inspect" ]]; then
        echo -e "${RED}File not found: $file_to_inspect${RESET}"
    elif [[ "$file_to_inspect" == *.csr ]]; then
        openssl req -in "$file_to_inspect" -noout -text 2>/dev/null | less
    else
        openssl x509 -in "$file_to_inspect" -noout -text 2>/dev/null | less
    fi
    # no press_enter here — less handles it
}

# --- 5. List managed files ---
_cert_list() {
    print_section_header "Managed Certificates & Keys"
    echo -e "${DIM}Location: $CERT_DIR${RESET}\n"

    if [[ ! -d "$CERT_DIR" ]] || [[ -z "$(ls -A "$CERT_DIR" 2>/dev/null)" ]]; then
        echo -e "${YELLOW}No files yet. Use options [1] or [2] to create certificates.${RESET}"
        press_enter_to_continue; return
    fi

    echo -e "${GREEN}${BOLD}Certificates (.pem):${RESET}"
    local found=0
    for cert in "$CERT_DIR"/*.pem; do
        [[ -f "$cert" ]] || continue
        local sz; sz=$(get_file_size "$cert")
        echo -e "  ${YELLOW}→${RESET} $(basename "$cert")  ${DIM}($(human_size "$sz"))${RESET}"
        found=1
    done
    [[ $found -eq 0 ]] && echo -e "  ${DIM}(none)${RESET}"

    echo -e "\n${RED}${BOLD}Private Keys (.key):${RESET} ${DIM}← Keep these secret!${RESET}"
    found=0
    for key in "$CERT_DIR"/*.key; do
        [[ -f "$key" ]] || continue
        local perms; perms=$(stat -c "%a" "$key" 2>/dev/null || stat -f "%Lp" "$key" 2>/dev/null)
        local perm_icon="${GREEN}✓${RESET}"
        [[ "$perms" != "400" && "$perms" != "600" ]] && perm_icon="${RED}⚠ INSECURE${RESET}"
        echo -e "  ${YELLOW}→${RESET} $(basename "$key")  ${DIM}(mode: $perms)${RESET}  $perm_icon"
        found=1
    done
    [[ $found -eq 0 ]] && echo -e "  ${DIM}(none)${RESET}"

    echo -e "\n${BLUE}${BOLD}Certificate Requests (.csr):${RESET}"
    found=0
    for csr in "$CERT_DIR"/*.csr; do
        [[ -f "$csr" ]] || continue
        echo -e "  ${YELLOW}→${RESET} $(basename "$csr")"
        found=1
    done
    [[ $found -eq 0 ]] && echo -e "  ${DIM}(none)${RESET}"

    echo -e "\n${CYAN}${BOLD}PKCS#12 Bundles (.p12):${RESET}"
    found=0
    for p12 in "$CERT_DIR"/*.p12; do
        [[ -f "$p12" ]] || continue
        local sz; sz=$(get_file_size "$p12")
        echo -e "  ${YELLOW}→${RESET} $(basename "$p12")  ${DIM}($(human_size "$sz"))${RESET}"
        found=1
    done
    [[ $found -eq 0 ]] && echo -e "  ${DIM}(none)${RESET}"

    local total; total=$(ls -1 "$CERT_DIR" 2>/dev/null | wc -l | tr -d ' ')
    echo -e "\n${WHITE}${BOLD}Total files: $total${RESET}"
    press_enter_to_continue
}

# --- 6. Export to PKCS#12 ---
_cert_export_pkcs12() {
    print_section_header "Export to PKCS#12 Format"
    echo -e "${DIM}Bundles certificate + key into a single .p12 file.${RESET}"
    echo -e "${DIM}Supported by Windows, macOS, browsers, and email clients.${RESET}\n"

    if ls "$CERT_DIR"/*.pem &>/dev/null 2>&1; then
        echo -e "${BLUE}Available certificates:${RESET}"
        for cert in "$CERT_DIR"/*.pem; do [[ -f "$cert" ]] && echo -e "  → $(basename "$cert")"; done
    fi

    echo -en "\n${MAGENTA}Certificate (.pem): ${RESET}"; read -r cert_file
    cert_file=$(echo "$cert_file" | xargs 2>/dev/null || echo "$cert_file")
    [[ ! -f "$cert_file" ]] && [[ -f "$CERT_DIR/$cert_file" ]] && cert_file="$CERT_DIR/$cert_file"

    if [[ ! -f "$cert_file" ]]; then
        echo -e "${RED}Certificate not found!${RESET}"
        press_enter_to_continue; return
    fi

    if ls "$CERT_DIR"/*.key &>/dev/null 2>&1; then
        echo -e "${BLUE}Available keys:${RESET}"
        for key in "$CERT_DIR"/*.key; do [[ -f "$key" ]] && echo -e "  → $(basename "$key")"; done
    fi

    echo -en "${MAGENTA}Private key (.key): ${RESET}"; read -r key_file
    key_file=$(echo "$key_file" | xargs 2>/dev/null || echo "$key_file")
    [[ ! -f "$key_file" ]] && [[ -f "$CERT_DIR/$key_file" ]] && key_file="$CERT_DIR/$key_file"

    if [[ ! -f "$key_file" ]]; then
        echo -e "${RED}Private key not found!${RESET}"
        press_enter_to_continue; return
    fi

    local base_name; base_name=$(basename "$cert_file" .pem)
    local p12_file="$CERT_DIR/${base_name}.p12"

    echo -en "\n${MAGENTA}${BOLD}Export password: ${RESET}"; read -rs p12_pass; echo
    echo -en "${MAGENTA}${BOLD}Confirm password: ${RESET}"; read -rs p12_pass_conf; echo

    if [[ "$p12_pass" != "$p12_pass_conf" ]]; then
        echo -e "${RED}Passwords do not match!${RESET}"
        press_enter_to_continue; return
    fi

    # Use pass file — never on command line
    local pass_file; pass_file=$(_write_pass_file "$p12_pass")

    echo -e "${CYAN}Creating PKCS#12 bundle...${RESET}"
    start_spinner "Packaging..."

    openssl pkcs12 -export \
        -in "$cert_file" \
        -inkey "$key_file" \
        -out "$p12_file" \
        -name "$base_name" \
        -passout "file:${pass_file}" 2>/dev/null

    local rc=$?
    stop_spinner $rc
    rm -f "$pass_file"

    if [[ $rc -eq 0 ]]; then
        local sz; sz=$(get_file_size "$p12_file")
        echo -e "\n${LIME}${BOLD}✓ PKCS#12 export successful!${RESET}"
        echo -e "  ${GREEN}📦${RESET} $p12_file  ${DIM}($(human_size "$sz"))${RESET}\n"
        echo -e "${PURPLE}Usage:${RESET}"
        echo -e "  → Windows: double-click to import into Certificate Store"
        echo -e "  → Browser: Settings → Security → Certificates → Import"
        echo -e "  → Email: import in your email client for S/MIME"
        echo -e "  → ${PINK}Password required${RESET} when importing"
        log_operation "SUCCESS" "PKCS#12 export: $p12_file"
    else
        echo -e "${RED}Export failed! Verify certificate and key match.${RESET}"
    fi
    press_enter_to_continue
}

# --- 7. Validate cert/key pair ---
_cert_validate_pair() {
    print_section_header "Validate Certificate / Key Pair"
    echo -e "${DIM}Checks that a certificate and private key belong together.${RESET}\n"

    if ls "$CERT_DIR"/*.pem &>/dev/null 2>&1; then
        echo -e "${BLUE}Available certificates:${RESET}"
        for cert in "$CERT_DIR"/*.pem; do [[ -f "$cert" ]] && echo -e "  → $(basename "$cert")"; done
    fi

    echo -en "\n${MAGENTA}Certificate (.pem): ${RESET}"; read -r cert_file
    cert_file=$(echo "$cert_file" | xargs 2>/dev/null || echo "$cert_file")
    [[ ! -f "$cert_file" ]] && [[ -f "$CERT_DIR/$cert_file" ]] && cert_file="$CERT_DIR/$cert_file"

    if [[ ! -f "$cert_file" ]]; then
        echo -e "${RED}Certificate not found!${RESET}"
        press_enter_to_continue; return
    fi

    if ls "$CERT_DIR"/*.key &>/dev/null 2>&1; then
        echo -e "${BLUE}Available keys:${RESET}"
        for key in "$CERT_DIR"/*.key; do [[ -f "$key" ]] && echo -e "  → $(basename "$key")"; done
    fi

    echo -en "${MAGENTA}Private key (.key): ${RESET}"; read -r key_file
    key_file=$(echo "$key_file" | xargs 2>/dev/null || echo "$key_file")
    [[ ! -f "$key_file" ]] && [[ -f "$CERT_DIR/$key_file" ]] && key_file="$CERT_DIR/$key_file"

    if [[ ! -f "$key_file" ]]; then
        echo -e "${RED}Key not found!${RESET}"
        press_enter_to_continue; return
    fi

    echo -e "${CYAN}Validating pair...${RESET}"
    local cert_md5; cert_md5=$(openssl x509 -noout -modulus -in "$cert_file" 2>/dev/null | openssl md5 2>/dev/null)
    local key_md5;  key_md5=$(openssl rsa  -noout -modulus -in "$key_file"   2>/dev/null | openssl md5 2>/dev/null)

    if [[ -z "$cert_md5" ]] || [[ -z "$key_md5" ]]; then
        echo -e "${RED}Could not read certificate or key — files may be corrupt.${RESET}"
    elif [[ "$cert_md5" == "$key_md5" ]]; then
        echo -e "\n${LIME}${BOLD}✓ Certificate and key MATCH${RESET}"
        echo -e "  ${YELLOW}Certificate:${RESET} $(basename "$cert_file")"
        echo -e "  ${YELLOW}Private Key:${RESET} $(basename "$key_file")"
        echo -e "  ${YELLOW}Modulus MD5:${RESET} ${DIM}$cert_md5${RESET}"
    else
        echo -e "\n${RED}${BOLD}✗ Certificate and key DO NOT MATCH${RESET}"
        echo -e "  ${YELLOW}Cert MD5:${RESET} ${DIM}$cert_md5${RESET}"
        echo -e "  ${YELLOW}Key MD5:${RESET}  ${DIM}$key_md5${RESET}"
        echo -e "${ORANGE}These files cannot be used together.${RESET}"
    fi
    press_enter_to_continue
}

# --- 8. Check certificate expiration ---
_cert_check_expiry() {
    print_section_header "Check Certificate Expiration"

    if ls "$CERT_DIR"/*.pem &>/dev/null 2>&1; then
        echo -e "${BLUE}Certificates in $CERT_DIR:${RESET}"
        for cert in "$CERT_DIR"/*.pem; do [[ -f "$cert" ]] && echo -e "  → $(basename "$cert")"; done
    fi

    echo -en "\n${MAGENTA}Certificate to check (.pem): ${RESET}"; read -r cert_file
    cert_file=$(echo "$cert_file" | xargs 2>/dev/null || echo "$cert_file")
    [[ ! -f "$cert_file" ]] && [[ -f "$CERT_DIR/$cert_file" ]] && cert_file="$CERT_DIR/$cert_file"

    if [[ ! -f "$cert_file" ]]; then
        echo -e "${RED}Certificate not found!${RESET}"
        press_enter_to_continue; return
    fi

    local not_before; not_before=$(openssl x509 -in "$cert_file" -noout -startdate 2>/dev/null | cut -d= -f2)
    local not_after;  not_after=$(openssl x509 -in "$cert_file" -noout -enddate   2>/dev/null | cut -d= -f2)
    local subject;    subject=$(openssl x509 -in "$cert_file" -noout -subject     2>/dev/null | cut -d= -f2-)

    if [[ -z "$not_after" ]]; then
        echo -e "${RED}Could not read certificate!${RESET}"
        press_enter_to_continue; return
    fi

    echo -e "\n${WHITE}${BOLD}Certificate:${RESET}"
    echo -e "  ${YELLOW}File:${RESET}       $(basename "$cert_file")"
    echo -e "  ${YELLOW}Subject:${RESET}    ${DIM}$subject${RESET}"
    echo -e "  ${YELLOW}Valid From:${RESET} $not_before"
    echo -e "  ${YELLOW}Valid Until:${RESET} $not_after\n"

    openssl x509 -in "$cert_file" -noout -checkend 0 &>/dev/null
    local is_valid=$?
    openssl x509 -in "$cert_file" -noout -checkend 2592000 &>/dev/null
    local expiring_soon=$?

    if [[ $is_valid -eq 0 ]]; then
        if [[ $expiring_soon -ne 0 ]]; then
            echo -e "${ORANGE}${BOLD}⚠ Certificate expiring within 30 days!${RESET}"
        else
            echo -e "${LIME}${BOLD}✓ Certificate is VALID${RESET}"
        fi
    else
        echo -e "${RED}${BOLD}✗ Certificate is EXPIRED${RESET}"
    fi

    # Calculate days remaining
    local end_epoch
    end_epoch=$(date -d "$not_after" +%s 2>/dev/null || date -j -f "%b %d %T %Y %Z" "$not_after" +%s 2>/dev/null || echo "")
    if [[ -n "$end_epoch" ]]; then
        local now; now=$(date +%s)
        local days_left=$(( (end_epoch - now) / 86400 ))
        if [[ $days_left -gt 0 ]]; then
            echo -e "  ${CYAN}Days remaining:${RESET} $days_left"
        else
            echo -e "  ${RED}Expired:${RESET} $((-days_left)) days ago"
        fi
    fi

    press_enter_to_continue
}
