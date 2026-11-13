#!/usr/bin/env bash
# ==============================================================================
# lib/audit.sh — Security audit: engine (audit_run), text / JSON reports,
#                interactive menu, and the optional remote TLS scan (testssl.sh).
# ==============================================================================

readonly TESTSSL_REPO="https://github.com/testssl/testssl.sh.git"
readonly TESTSSL_TAG="v3.2.5"        # pinned release — never an unpinned branch

declare -a AUDIT_ID=() AUDIT_STATUS=() AUDIT_TITLE=() AUDIT_DETAIL=() AUDIT_FIX=()
AUDIT_SCORE=0; AUDIT_MAX=0; AUDIT_FAILS=0; AUDIT_WARNS=0

_audit_add() {
    AUDIT_ID+=("$1"); AUDIT_STATUS+=("$2"); AUDIT_TITLE+=("$3"); AUDIT_DETAIL+=("${4:-}"); AUDIT_FIX+=("${5:-}")
    case "$2" in
        pass) AUDIT_SCORE=$(( AUDIT_SCORE + 2 )); AUDIT_MAX=$(( AUDIT_MAX + 2 )) ;;
        warn) AUDIT_SCORE=$(( AUDIT_SCORE + 1 )); AUDIT_MAX=$(( AUDIT_MAX + 2 )); (( AUDIT_WARNS++ )) ;;
        fail) AUDIT_MAX=$(( AUDIT_MAX + 2 )); (( AUDIT_FAILS++ )) ;;
    esac
    return 0
}

# audit_run [DIR] — DIR is scanned (non-recursively) for legacy encrypted files.
audit_run() {
    local scan_dir="${1:-.}"
    AUDIT_ID=(); AUDIT_STATUS=(); AUDIT_TITLE=(); AUDIT_DETAIL=(); AUDIT_FIX=()
    AUDIT_SCORE=0; AUDIT_MAX=0; AUDIT_FAILS=0; AUDIT_WARNS=0
    core_init_state
    core_probe_openssl

    # 1. Crypto library
    case "$OPENSSL_FLAVOR" in
        openssl)
            if   (( OPENSSL_MAJOR >= 3 )); then _audit_add openssl pass "OpenSSL version" "$OPENSSL_VERSION_TEXT — supported release line. Keep it patched through your OS updates."
            elif [[ "$OPENSSL_VERSION_TEXT" == *" 1.1.1"* ]]; then _audit_add openssl warn "OpenSSL version" "$OPENSSL_VERSION_TEXT — the 1.1.1 line reached end of life in September 2023." "Upgrade to OpenSSL 3.x"
            else _audit_add openssl fail "OpenSSL version" "$OPENSSL_VERSION_TEXT — too old (PBKDF2 support requires 1.1.1+)." "Upgrade to OpenSSL 3.x"; fi ;;
        libressl) _audit_add openssl pass "Crypto library" "$OPENSSL_VERSION_TEXT" ;;
        *)        _audit_add openssl warn "Crypto library" "Unrecognised: ${OPENSSL_VERSION_TEXT:-unknown}" ;;
    esac

    # 2. Shell
    if (( BASH_VERSINFO[0] >= 5 )); then _audit_add bash pass "Bash version" "$BASH_VERSION"
    else _audit_add bash warn "Bash version" "$BASH_VERSION — supported, but 5.x is recommended." "Upgrade bash"; fi

    # 3. Engine self-test (known-answer tests + round trip + tamper detection)
    if crypto_selftest; then
        _audit_add selftest pass "Cryptographic self-test" "HMAC-SHA256 and PBKDF2 known-answer tests, round trip and tamper detection all passed."
    else
        _audit_add selftest fail "Cryptographic self-test" "$ENC_ERR" "Do not use this installation until this is resolved"
    fi

    # 4. Cipher availability
    local c missing=""
    for c in "${ENC_CIPHER_IDS[@]}"; do crypto_cipher_available "$c" || missing+="$c "; done
    if [[ -z "$missing" ]]; then _audit_add ciphers pass "Cipher support" "All ${#ENC_CIPHER_IDS[@]} ciphers are available."
    elif crypto_cipher_available "$ENC_DEFAULT_CIPHER"; then _audit_add ciphers info "Cipher support" "Not provided by this OpenSSL build: ${missing% }"
    else _audit_add ciphers fail "Cipher support" "The default cipher $ENC_DEFAULT_CIPHER is not available."; fi

    # 5. KDF work factor
    if (( ENC_DEFAULT_ITER >= 600000 )); then _audit_add kdf pass "Password KDF work factor" "PBKDF2-HMAC-SHA256, ${ENC_DEFAULT_ITER} iterations (OWASP minimum: 600,000)."
    else _audit_add kdf warn "Password KDF work factor" "PBKDF2 iterations lowered to ${ENC_DEFAULT_ITER} via ENCRYPTOR_PBKDF2_ITER." "Unset ENCRYPTOR_PBKDF2_ITER or use >= 600000"; fi

    # 6. State directory permissions
    local mode; mode=$(get_file_mode "$CONFIG_DIR")
    if [[ "$mode" == "700" ]]; then _audit_add config-perms pass "Configuration directory" "$CONFIG_DIR is private (mode 700)."
    else _audit_add config-perms fail "Configuration directory" "$CONFIG_DIR has mode ${mode:-?}; other users may read keys or logs." "chmod 700 '$CONFIG_DIR'"; fi
    mode=$(get_file_mode "$CERT_DIR")
    if [[ "$mode" != "700" ]]; then _audit_add cert-dir-perms fail "Key store directory" "$CERT_DIR has mode ${mode:-?}." "chmod 700 '$CERT_DIR'"; fi

    # 7. Private keys: permissions and passphrase protection
    local k total=0 loose="" unprotected=0
    for k in "$CERT_DIR"/*.key; do
        [[ -f "$k" ]] || continue
        (( total++ ))
        mode=$(get_file_mode "$k")
        [[ "$mode" == "400" || "$mode" == "600" ]] || loose+="$(basename "$k")($mode) "
        crypto_key_is_encrypted "$k" || (( unprotected++ ))
    done
    if (( total == 0 )); then _audit_add key-perms info "Private key permissions" "No private keys in the store."
    elif [[ -z "$loose" ]]; then _audit_add key-perms pass "Private key permissions" "All $total key(s) are owner-only (400/600)."
    else _audit_add key-perms fail "Private key permissions" "Readable by others: ${loose% }" "chmod 400 '$CERT_DIR'/*.key"; fi
    if (( total > 0 )); then
        if (( unprotected == 0 )); then _audit_add key-encryption pass "Private key protection" "All $total key(s) are passphrase-protected."
        else _audit_add key-encryption warn "Private key protection" "$unprotected of $total key(s) are stored without a passphrase." "openssl pkey -in KEY -aes-256-cbc -out KEY.new"; fi
    fi

    # 8. Certificates: expiry and strength
    local f expired="" expiring="" weak="" ncert=0 level msg
    for f in "$CERT_DIR"/*.pem; do
        [[ -f "$f" ]] || continue
        pki_cert_info "$f" || continue
        (( ncert++ ))
        case "${PKI_INFO[status]}" in
            expired)  expired+="$(basename "$f") " ;;
            expiring) expiring+="$(basename "$f")(${PKI_INFO[days_left]}d) " ;;
        esac
        while IFS='|' read -r level msg; do
            [[ "$level" == "fail" && "$msg" != *EXPIRED* ]] && weak+="$(basename "$f"): $msg "
        done < <(pki_cert_findings)
    done
    if (( ncert == 0 )); then _audit_add cert-expiry info "Certificate expiry" "No certificates in the store."
    elif [[ -n "$expired" ]]; then _audit_add cert-expiry fail "Certificate expiry" "Expired: ${expired% }${expiring:+ — expiring soon: ${expiring% }}" "Re-issue the certificate(s)"
    elif [[ -n "$expiring" ]]; then _audit_add cert-expiry warn "Certificate expiry" "Expiring within ${PKI_EXPIRY_WARN_DAYS} days: ${expiring% }" "Plan renewal"
    else _audit_add cert-expiry pass "Certificate expiry" "All $ncert certificate(s) are valid for more than ${PKI_EXPIRY_WARN_DAYS} days."; fi
    if (( ncert > 0 )); then
        if [[ -z "$weak" ]]; then _audit_add cert-strength pass "Certificate strength" "No weak keys or deprecated signature algorithms."
        else _audit_add cert-strength fail "Certificate strength" "${weak% }" "Replace the affected certificate(s)"; fi
    fi

    # 9. Operation log
    if [[ -f "$LOG_FILE" ]]; then
        mode=$(get_file_mode "$LOG_FILE")
        if [[ "$mode" == "600" || "$mode" == "400" ]]; then _audit_add log-perms pass "Operation log" "$LOG_FILE is private (mode $mode)."
        else _audit_add log-perms fail "Operation log" "$LOG_FILE has mode ${mode:-?}; it reveals file names to other users." "chmod 600 '$LOG_FILE'"; fi
    fi

    # 10. Stale temporary directories (left behind by a crash / SIGKILL)
    local stale
    stale=$(find "${TMPDIR:-/tmp}" -maxdepth 1 -type d \( -name 'encryptor.*' -o -name 'encryptor_*' \) -mmin +60 2>/dev/null | grep -vxF "${TEMP_DIR:-/nonexistent}" | wc -l | tr -d ' ')
    if [[ "${stale:-0}" -eq 0 ]]; then _audit_add temp pass "Temporary files" "No stale temporary directories."
    else _audit_add temp warn "Temporary files" "$stale stale temporary director(ies) in ${TMPDIR:-/tmp}." "rm -rf '${TMPDIR:-/tmp}'/encryptor.* '${TMPDIR:-/tmp}'/encryptor_*"; fi

    # 11. Legacy, unauthenticated files in the scanned directory
    local legacy=0 n=0
    for f in "$scan_dir"/*.enc; do
        [[ -f "$f" ]] || continue
        (( n++ )); (( n > 500 )) && break
        [[ "$(file_magic_hex "$f" 8)" == "53616c7465645f5f" ]] && (( legacy++ ))
    done
    if (( legacy > 0 )); then
        _audit_add legacy warn "Legacy encrypted files" "$legacy file(s) in $(ui_pathfit "$(cd "$scan_dir" 2>/dev/null && pwd)") use the unauthenticated 2.x format." "Decrypt and re-encrypt them to upgrade to ENCRYPTOR/3"
    else
        _audit_add legacy pass "Legacy encrypted files" "No unauthenticated 2.x files in the current directory."
    fi

    # 12. Process hygiene
    local cores; cores=$(ulimit -c 2>/dev/null)
    if [[ "$cores" == "0" ]]; then _audit_add coredump pass "Core dumps" "Disabled for this session (ulimit -c 0)."
    else _audit_add coredump info "Core dumps" "Enabled (ulimit -c ${cores:-?}); a crash could write secrets held in memory to disk."; fi
    if have shred; then _audit_add shred info "Secure delete" "shred is available. Overwriting is best-effort on SSDs and copy-on-write filesystems."
    else _audit_add shred info "Secure delete" "shred not found; a single random overwrite is used instead (best-effort)."; fi
    return 0
}

audit_percent() { if (( AUDIT_MAX > 0 )); then printf '%d' $(( AUDIT_SCORE * 100 / AUDIT_MAX )); else printf '100'; fi; }

audit_report_text() {
    local i st col mark pct detail room
    for (( i = 0; i < ${#AUDIT_ID[@]}; i++ )); do
        st="${AUDIT_STATUS[$i]}"
        case "$st" in
            pass) col="$C_OK";   mark="$G_OK" ;;
            warn) col="$C_WARN"; mark="$G_WARN" ;;
            fail) col="$C_ERR";  mark="$G_ERR" ;;
            *)    col="$C_INFO"; mark="$G_INFO" ;;
        esac
        detail="${AUDIT_DETAIL[$i]}"
        if [[ "$st" == "pass" || "$st" == "info" ]]; then
            # Compact: one line, detail trimmed to the terminal width.
            room=$(( UI_W - 34 )); (( room < 10 )) && room=10
            printf '  %s%s%s %s%-26s%s %s%s%s\n' "$col" "$mark" "$RESET" "$BOLD" "$(ui_fit "${AUDIT_TITLE[$i]}" 26)" "$RESET" \
                "$C_MUTED" "$(ui_fit "$detail" "$room")" "$RESET"
        else
            printf '  %s%s %s%s%s %s%s%s\n' "$col" "$mark" "$BOLD" "${AUDIT_TITLE[$i]}" "$RESET" "$col" "(${st})" "$RESET"
            [[ -n "$detail" ]] && printf '      %s\n' "$detail"
            [[ -n "${AUDIT_FIX[$i]}" ]] && printf '      %sFix:%s %s\n' "$C_KEY" "$RESET" "${AUDIT_FIX[$i]}"
        fi
    done
    pct=$(audit_percent)
    col="$C_OK"; local verdict="Excellent"
    if   (( AUDIT_FAILS > 0 )); then col="$C_ERR";  verdict="Action required"
    elif (( AUDIT_WARNS > 0 )); then col="$C_WARN"; verdict="Good, review the warnings"; fi
    printf '\n  %sScore%s  %s  %s%s%d%%%s  %s%s%s  %s(%d failed, %d warning(s))%s\n' "$BOLD" "$RESET" \
        "$(ui_meter "$pct" 100 30 "$col")" "$col" "$BOLD" "$pct" "$RESET" "$col" "$verdict" "$RESET" "$C_MUTED" "$AUDIT_FAILS" "$AUDIT_WARNS" "$RESET"
}

audit_report_json() {
    local i
    printf '{"version":"%s","openssl":"%s","score":%d,"max_score":%d,"percent":%d,"failed":%d,"warnings":%d,"checks":[' \
        "$ENCRYPTOR_VERSION" "$(json_escape "$OPENSSL_VERSION_TEXT")" "$AUDIT_SCORE" "$AUDIT_MAX" "$(audit_percent)" "$AUDIT_FAILS" "$AUDIT_WARNS"
    for (( i = 0; i < ${#AUDIT_ID[@]}; i++ )); do
        (( i > 0 )) && printf ','
        printf '{"id":"%s","status":"%s","title":"%s","detail":"%s","fix":"%s"}' \
            "${AUDIT_ID[$i]}" "${AUDIT_STATUS[$i]}" "$(json_escape "${AUDIT_TITLE[$i]}")" \
            "$(json_escape "${AUDIT_DETAIL[$i]}")" "$(json_escape "${AUDIT_FIX[$i]}")"
    done
    printf ']}\n'
}

# --- Remote TLS scan (testssl.sh) -------------------------------------------
audit_testssl_path() {
    local p
    for p in testssl.sh testssl; do
        if have "$p"; then command -v "$p"; return 0; fi
    done
    [[ -x "$TOOLS_DIR/testssl.sh/testssl.sh" ]] && { printf '%s' "$TOOLS_DIR/testssl.sh/testssl.sh"; return 0; }
    return 1
}

# Strict target grammar: host name, IPv4 or [IPv6], optional :port. Anything
# else (including option-like strings such as "--file=…") is rejected, so user
# input can never be interpreted as a testssl.sh option.
audit_valid_target() {
    local t="$1"
    [[ ${#t} -le 253 ]] || return 1
    [[ "$t" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?(:[0-9]{1,5})?$ ]] && return 0
    [[ "$t" =~ ^\[[0-9A-Fa-f:]+\](:[0-9]{1,5})?$ ]] && return 0
    return 1
}

audit_install_testssl() {
    ENC_ERR=""
    have git || { ENC_ERR="git is required to install testssl.sh."; return "$EX_FAIL"; }
    core_init_state
    local dest="$TOOLS_DIR/testssl.sh" staging="$TOOLS_DIR/.testssl.staging.$$"
    rm -rf -- "$staging"
    if ! git clone --quiet --depth 1 --branch "$TESTSSL_TAG" "$TESTSSL_REPO" "$staging" 2>/dev/null; then
        rm -rf -- "$staging"; ENC_ERR="Download failed (network unavailable, or tag $TESTSSL_TAG not found)."; return "$EX_FAIL"
    fi
    [[ -f "$staging/testssl.sh" ]] || { rm -rf -- "$staging"; ENC_ERR="Unexpected repository content."; return "$EX_FAIL"; }
    rm -rf -- "$dest"
    mv -- "$staging" "$dest" || { ENC_ERR="Could not install into $dest"; return "$EX_FAIL"; }
    chmod 755 "$dest/testssl.sh" 2>/dev/null || true
    log_operation "INFO" "testssl.sh $TESTSSL_TAG installed ($(git -C "$dest" rev-parse --short HEAD 2>/dev/null))"
    return 0
}

# ==============================================================================
# Interactive screens
# ==============================================================================
audit_ui_menu() {
    local rc
    while true; do
        local tpath tnote="not installed"
        tpath=$(audit_testssl_path) && tnote="$(ui_pathfit "$tpath")"
        UI_SEL_HEADER="$(tui_header "Security audit")"
        ui_select "What would you like to check?" \
            "1|Local audit|self-test, permissions, keys, certificates, legacy files" \
            "2|Remote TLS scan|testssl.sh ${G_DOT} ${tnote}" \
            "3|Install / update testssl.sh|pinned release ${TESTSSL_TAG}" \
            "-" \
            "q|Back|"
        rc=$?
        (( rc != 0 )) && return 0
        case "$UI_CHOICE" in
            1) audit_ui_local ;;
            2) audit_ui_remote ;;
            3) audit_ui_install ;;
            q) return 0 ;;
        esac
    done
}

audit_ui_local() {
    tui_screen "Local security audit" "Read-only checks of this installation and of $(ui_pathfit "$PWD")"
    ui_spinner_start "Running checks${G_ELLIPSIS}"
    audit_run "."
    ui_spinner_stop
    audit_report_text
    log_operation "INFO" "Local audit: $(audit_percent)% (${AUDIT_FAILS} failed, ${AUDIT_WARNS} warnings)"
    ui_pause
}

audit_ui_remote() {
    tui_screen "Remote TLS scan" "Runs testssl.sh against a server you are authorised to test."
    local tool
    if ! tool=$(audit_testssl_path); then
        ui_warn "testssl.sh is not installed. Use \"Install / update testssl.sh\" first."
        ui_pause; return 0
    fi
    ui_prompt "Host[:port] to scan (e.g. example.com or example.com:8443)" "" || return 0
    local target="$UI_REPLY"
    [[ -z "$target" ]] && return 0
    if ! audit_valid_target "$target"; then
        ui_err "Invalid target. Use a host name or IP address, optionally followed by :port."
        ui_pause; return 0
    fi
    ui_note "Only scan systems you own or have permission to test. This can take several minutes."
    ui_confirm "Start the scan of ${target}?" y || return 0
    log_operation "INFO" "Remote TLS scan started: $target"
    echo
    "$tool" --protocols --server-defaults --vulnerable --quiet "$target"
    ui_pause "Scan finished — press Enter to continue"
}

audit_ui_install() {
    tui_screen "Install testssl.sh" "Third-party tool by the testssl.sh project (GPLv2), fetched from GitHub."
    ui_row "Source" "$TESTSSL_REPO"; echo
    ui_row "Version" "$TESTSSL_TAG (pinned tag)"; echo
    ui_row "Target" "$(ui_pathfit "$TOOLS_DIR/testssl.sh")"; echo
    echo
    ui_confirm "Download and install?" y || return 0
    ui_spinner_start "Downloading testssl.sh ${TESTSSL_TAG}${G_ELLIPSIS}"
    audit_install_testssl; local rc=$?
    ui_spinner_stop
    if (( rc == 0 )); then ui_ok "testssl.sh ${TESTSSL_TAG} installed."; else ui_err "$ENC_ERR"; fi
    ui_pause
}
