#!/usr/bin/env bash
# ==============================================================================
# lib/tui.sh — Interactive application: main menu and the encrypt / decrypt /
#              inspect wizards. All cryptographic work is delegated to the
#              engine in lib/crypto.sh; this file only talks to the user.
# ==============================================================================

TUI_ACTIVE=0
TUI_CIPHER="$ENC_DEFAULT_CIPHER"

# Compact header used on every sub-screen.
tui_header() {
    local title="${1:-}" sub="${2:-}"
    printf ' %s%sENCRYPTOR%s %s%s%s' "$C_ACCENT" "$BOLD" "$RESET" "$C_MUTED" "$ENCRYPTOR_VERSION" "$RESET"
    [[ -n "$title" ]] && printf '  %s%s%s  %s%s%s' "$C_MUTED" "$G_DOT" "$RESET" "$BOLD" "$title" "$RESET"
    printf '\n %s%s%s' "$C_MUTED" "$(ui_repeat "$G_H" "$UI_W")" "$RESET"
    [[ -n "$sub" ]] && printf '\n %s%s%s' "$C_MUTED" "$(ui_fit "$sub" "$UI_W")" "$RESET"
    return 0
}

tui_screen() {
    ui_clear
    tui_header "$@"
    printf '\n\n'
}

# Engine progress hook → spinner / progress bar.
crypto_on_phase() {
    (( TUI_ACTIVE )) || return 0
    case "$1" in
        kdf)     ui_spinner_start "Deriving key ${G_DOT} PBKDF2-HMAC-SHA256, ${2:-?} iterations" ;;
        keygen)  ui_spinner_start "Generating and wrapping the file key" ;;
        unwrap)  ui_spinner_start "Unwrapping the file key" ;;
        encrypt) ui_spinner_start "Encrypting" "${2:-}" "${3:-0}" ;;
        mac)     ui_spinner_start "Computing authentication tag" ;;
        verify)  ui_spinner_start "Verifying authenticity before decryption" ;;
        decrypt) ui_spinner_start "Decrypting" "${2:-}" "${3:-0}" ;;
    esac
    return 0
}

# --- Password entry ----------------------------------------------------------
_tui_strength_line() {
    local bits="$1" label col
    if   (( bits < 45 )); then label="weak";   col="$C_ERR"
    elif (( bits < 65 )); then label="fair";   col="$C_WARN"
    elif (( bits < 90 )); then label="good";   col="$C_OK"
    else                       label="strong"; col="$C_OK"; fi
    printf '  %sStrength%s  %s  %s%s%s %s(~%d bits)%s\n' "$C_MUTED" "$RESET" "$(ui_meter "$bits" 110 24 "$col")" "$col" "$label" "$RESET" "$C_MUTED" "$bits" "$RESET"
}

# Ask for a NEW secret with confirmation, strength feedback and an optional
# generator. Sets UI_REPLY. Returns 1 if the user gives up.
tui_new_secret() {
    local label="$1" pw pw2 bits tries=0
    ui_note "Leave empty to generate a strong random one."
    while (( tries < 5 )); do
        (( tries++ ))
        ui_prompt_secret "$label" || return 1
        pw="$UI_REPLY"
        if [[ -z "$pw" ]]; then
            pw=$(crypto_generate_password 24) || { ui_err "Could not generate a password."; return 1; }
            echo
            UI_PANEL_COLOR="$C_WARN"
            ui_panel "Generated password ${G_DOT} shown once" \
                "" \
                "    ${BOLD}${C_KEY}${pw}${RESET}" \
                "" \
                "${C_MUTED}24 random characters (~142 bits). Store it in your password manager now.${RESET}"
            if ui_confirm "I have saved it" n; then UI_REPLY="$pw"; return 0; fi
            continue
        fi
        if (( ${#pw} > ENC_PASS_MAX )); then ui_err "Too long (limit ${ENC_PASS_MAX} characters)."; continue; fi
        ui_prompt_secret "Confirm" || return 1
        pw2="$UI_REPLY"
        if [[ "$pw" != "$pw2" ]]; then ui_err "The two entries do not match."; continue; fi
        bits=$(crypto_password_bits "$pw")
        _tui_strength_line "$bits"
        if (( bits < 45 )); then
            ui_warn "This password could be guessed by an offline attack."
            ui_note "  Aim for 4+ random words or 14+ mixed characters."
            ui_confirm "Use it anyway?" n || continue
        fi
        UI_REPLY="$pw"; return 0
    done
    return 1
}

# Resolve an output path that may already exist. Sets UI_REPLY; returns 1 on cancel.
_tui_resolve_output() {
    local out="$1" rc
    while [[ -e "$out" ]]; do
        UI_SEL_HEADER="$(tui_header "Output file")"
        ui_select "$(ui_pathfit "$out") already exists" \
            "o|Overwrite it|" \
            "n|Choose another name|" \
            "q|Cancel|"
        rc=$?
        (( rc != 0 )) && return 1
        case "$UI_CHOICE" in
            o) break ;;
            n) ui_prompt_path "New output path" || return 1
               [[ -n "$UI_REPLY" ]] && out="$UI_REPLY" ;;
            *) return 1 ;;
        esac
    done
    UI_REPLY="$out"
}

# --- Recipient selection (multi-select) -------------------------------------
declare -a TUI_RECIPIENTS=()
_tui_pick_recipients() {
    TUI_RECIPIENTS=()
    local -a extra=()
    local f rc sel mark hint status last=""
    while true; do
        ui_sel_reset
        local -a all=()
        while IFS= read -r f; do [[ -n "$f" ]] && all+=("$f"); done < <(pki_store_files pem)
        for f in "${extra[@]:-}"; do [[ -n "$f" ]] && all+=("$f"); done
        for f in "${all[@]:-}"; do
            [[ -n "$f" ]] || continue
            pki_cert_info "$f" || continue
            [[ "${PKI_INFO[is_ca]}" == 1 ]] && continue
            mark="$G_CHECK_OFF"
            for sel in "${TUI_RECIPIENTS[@]:-}"; do [[ "$sel" == "$f" ]] && mark="$G_CHECK_ON"; done
            status=""
            [[ "${PKI_INFO[status]}" == "expired" ]]  && status="  ${G_DOT} EXPIRED"
            [[ "${PKI_INFO[status]}" == "expiring" ]] && status="  ${G_DOT} expires in ${PKI_INFO[days_left]}d"
            hint="${PKI_INFO[cn]}  ${G_DOT} $(_pki_key_short)${status}"
            ui_sel_add "$f" "$mark $(basename "$f")" "$hint"
        done
        ui_sel_sep
        ui_sel_add "@path" "Add a certificate from a path${G_ELLIPSIS}" ""
        ui_sel_add "@done" "Continue with ${#TUI_RECIPIENTS[@]} recipient(s)" ""
        UI_SEL_HEADER="$(tui_header "Encrypt" "Everyone selected here will be able to decrypt with their own private key.")"
        UI_SEL_HOTKEYS=0
        [[ -n "$last" ]] && UI_SEL_START="$last"
        ui_sel_run "Select recipients (Enter toggles)"; rc=$?
        (( rc != 0 )) && return 1
        case "$UI_CHOICE" in
            @done)
                (( ${#TUI_RECIPIENTS[@]} > 0 )) && return 0
                ui_err "Select at least one recipient."; ui_pause ;;
            @path)
                ui_prompt_path "Certificate (.pem)" || continue
                if [[ -f "$UI_REPLY" ]] && pki_cert_info "$UI_REPLY"; then extra+=("$UI_REPLY"); TUI_RECIPIENTS+=("$UI_REPLY")
                else ui_err "Not a readable PEM certificate: $UI_REPLY"; ui_pause; fi ;;
            *)
                f="$UI_CHOICE"; last="$f"
                local -a keep=(); local was=0
                for sel in "${TUI_RECIPIENTS[@]:-}"; do
                    [[ -z "$sel" ]] && continue
                    if [[ "$sel" == "$f" ]]; then was=1; else keep+=("$sel"); fi
                done
                if (( was )); then TUI_RECIPIENTS=("${keep[@]:-}"); [[ -z "${TUI_RECIPIENTS[0]:-}" ]] && TUI_RECIPIENTS=()
                else
                    if openssl x509 -in "$f" -noout -checkend 0 >/dev/null 2>&1; then TUI_RECIPIENTS+=("$f")
                    else ui_err "$(basename "$f") has expired and cannot be used."; ui_pause; fi
                fi ;;
        esac
    done
}

_tui_pick_cipher() {
    local c hint
    ui_sel_reset
    for c in "${ENC_CIPHER_IDS[@]}"; do
        hint="${ENC_CIPHER_DESC[$c]}"
        crypto_cipher_available "$c" || hint="not available in this OpenSSL build"
        ui_sel_add "$c" "${ENC_CIPHER_LABEL[$c]}" "$hint"
    done
    UI_SEL_HEADER="$(tui_header "Encrypt" "Every option is authenticated (encrypt-then-MAC): tampering is always detected.")"
    UI_SEL_HOTKEYS=0; UI_SEL_START="$TUI_CIPHER"
    ui_sel_run "Cipher" || return 1
    if crypto_cipher_available "$UI_CHOICE"; then TUI_CIPHER="$UI_CHOICE"; else ui_err "That cipher is not available here."; ui_pause; fi
}

# --- Encrypt wizard ----------------------------------------------------------
tui_encrypt() {
    local -a steps=(File Protection Secret Result)
    local in out method rc

    ui_pick_file "Select a file to encrypt" "." "$(tui_header "Encrypt"; echo; ui_steps 1 "${steps[@]}")" || return 0
    in="$UI_CHOICE"

    while true; do
        UI_SEL_HEADER="$(tui_header "Encrypt" "$(ui_pathfit "$in")  ($(human_size "$(get_file_size "$in")"))"; echo; ui_steps 2 "${steps[@]}")"
        ui_select "How should this file be protected?" \
            "p|Password|anyone who knows the password can decrypt" \
            "r|Certificate recipients|only the people you choose can decrypt" \
            "-" \
            "c|Change cipher|now: ${ENC_CIPHER_LABEL[$TUI_CIPHER]}" \
            "q|Cancel|"
        rc=$?
        (( rc != 0 )) && return 0
        case "$UI_CHOICE" in
            p|r) method="$UI_CHOICE"; break ;;
            c)   _tui_pick_cipher ;;
            *)   return 0 ;;
        esac
    done

    crypto_reset_inputs
    if [[ "$method" == "p" ]]; then
        tui_screen "Encrypt" "$(ui_pathfit "$in")"
        ui_steps 3 "${steps[@]}"; echo
        tui_new_secret "Password" || return 0
        ENC_SECRET="$UI_REPLY"
    else
        _tui_pick_recipients || return 0
        ENC_RECIPIENTS=("${TUI_RECIPIENTS[@]}")
    fi

    _tui_resolve_output "${in}.enc" || { crypto_reset_inputs; return 0; }
    out="$UI_REPLY"

    tui_screen "Encrypt" "$(ui_pathfit "$in")"
    ui_steps 4 "${steps[@]}"; echo
    local t0 t1; t0=$(now_ms)
    TUI_ACTIVE=1
    crypto_encrypt "$in" "$out" "$TUI_CIPHER"; rc=$?
    TUI_ACTIVE=0; ui_spinner_stop
    t1=$(now_ms)

    if (( rc != 0 )); then
        log_operation "ERROR" "Encrypt failed: $in — $ENC_ERR"
        UI_PANEL_COLOR="$C_ERR"
        ui_panel "$G_ERR Encryption failed" "$ENC_ERR" "${C_MUTED}The original file was not changed.${RESET}"
        crypto_reset_inputs; ui_pause; return 0
    fi
    local keyline
    if [[ "$method" == "p" ]]; then keyline="Password ${G_DOT} PBKDF2-HMAC-SHA256, ${ENC_DEFAULT_ITER} iterations"
    else keyline="${#ENC_RECIPIENTS[@]} certificate recipient(s) ${G_DOT} CMS key wrap"; fi
    log_operation "SUCCESS" "Encrypted: $in → $out (cipher=$TUI_CIPHER, mode=$([[ $method == p ]] && echo password || echo recipient))"
    UI_PANEL_COLOR="$C_OK"
    ui_panel "$G_OK Encrypted" \
        "$(ui_row "Source" "$(ui_pathfit "$in")  ${C_MUTED}($(human_size "$ENC_RESULT_BYTES_IN"))${RESET}")" \
        "$(ui_row "Output" "${C_OK}$(ui_pathfit "$out")${RESET}  ${C_MUTED}($(human_size "$ENC_RESULT_BYTES_OUT"))${RESET}")" \
        "$(ui_row "Protection" "${ENC_CIPHER_LABEL[$TUI_CIPHER]} ${G_DOT} authenticated")" \
        "$(ui_row "Key" "$keyline")" \
        "$(ui_row "Time" "$(( t1 - t0 )) ms")"
    echo
    ui_note "To decrypt later:  encryptor decrypt \"$out\""
    [[ "$method" == "p" ]] && ui_note "There is no password recovery. Without the password the data is lost."
    echo

    if ui_confirm "Securely delete the original file?" n; then
        _tui_delete_original "$in" "$out" "$method"
    else
        ui_note "Original file kept."
    fi
    crypto_reset_inputs
    ui_pause
}

# Delete the plaintext only after proving the encrypted copy can be opened.
_tui_delete_original() {
    local in="$1" out="$2" method="$3" rc
    if [[ "$method" == "p" ]]; then
        TUI_ACTIVE=1; crypto_verify "$out"; rc=$?; TUI_ACTIVE=0; ui_spinner_stop
        if (( rc != 0 )); then
            ui_err "Verification of the encrypted copy failed — the original was NOT deleted. ($ENC_ERR)"
            return 1
        fi
        ui_ok "Encrypted copy verified with your password."
    else
        if ! crypto_inspect "$out"; then ui_err "The encrypted copy looks invalid — the original was NOT deleted."; return 1; fi
        ui_warn "The copy can only be opened by the recipients' private keys, so it cannot be test-decrypted here."
        ui_confirm "Delete the original anyway?" n || { ui_note "Original file kept."; return 0; }
    fi
    if secure_delete "$in"; then
        ui_ok "Original deleted ${C_MUTED}(${SECURE_DELETE_METHOD})${RESET}"
        ui_note "On SSDs and copy-on-write / journaling filesystems old blocks may survive an overwrite."
        log_operation "INFO" "Original securely deleted: $in"
    else
        ui_err "$ENC_ERR"
    fi
}

# --- Container description ---------------------------------------------------
# Builds panel lines for the container currently described by ENC_META.
declare -a TUI_DESC=()
_tui_describe() {
    local file="$1" fp n=0
    TUI_DESC=("$(ui_row "File" "$(ui_pathfit "$file")  ${C_MUTED}($(human_size "${ENC_META[size]:-0}"))${RESET}")")
    case "${ENC_META[format]:-}" in
        v3)
            TUI_DESC+=("$(ui_row "Format" "ENCRYPTOR/3 ${G_DOT} ${C_OK}authenticated${RESET}")")
            TUI_DESC+=("$(ui_row "Cipher" "${ENC_CIPHER_LABEL[${ENC_META[cipher]}]}")")
            if [[ "${ENC_META[mode]}" == "password" ]]; then
                TUI_DESC+=("$(ui_row "Key" "Password ${G_DOT} PBKDF2-HMAC-SHA256, ${ENC_META[iter]} iterations")")
            else
                TUI_DESC+=("$(ui_row "Key" "${#ENC_META_RCPT[@]} certificate recipient(s) ${G_DOT} CMS key wrap")")
                for fp in "${ENC_META_RCPT[@]:-}"; do
                    [[ -n "$fp" ]] || continue
                    (( n++ ))
                    TUI_DESC+=("$(ui_row "Recipient $n" "$(_tui_recipient_name "$fp")")")
                done
            fi
            TUI_DESC+=("$(ui_row "Ciphertext" "$(human_size "${ENC_META[body_len]}")")") ;;
        legacy-enc)
            TUI_DESC+=("$(ui_row "Format" "Encryptor 2.x / raw openssl enc ${G_DOT} ${C_WARN}not authenticated${RESET}")")
            TUI_DESC+=("$(ui_row "Key" "Password (algorithm is not recorded in the file)")") ;;
        legacy-smime)
            TUI_DESC+=("$(ui_row "Format" "Encryptor 2.x S/MIME (PKCS#7) ${G_DOT} ${C_WARN}not authenticated${RESET}")")
            TUI_DESC+=("$(ui_row "Key" "Certificate recipient")") ;;
    esac
}

# Map a recipient fingerprint to a certificate in the local store, if any.
_tui_recipient_name() {
    local fp="$1" f have
    for f in "$CERT_DIR"/*.pem; do
        [[ -f "$f" ]] || continue
        have=$(crypto_cert_fingerprint "$f") || continue
        if [[ "$have" == "$fp" ]]; then
            local note=""; [[ -f "${f%.pem}.key" ]] && note="  ${C_OK}(you hold the key)${RESET}"
            printf '%s%s' "$(basename "$f")" "$note"; return
        fi
    done
    printf '%s%s%s%s' "$C_MUTED" "${fp:0:16}" "$G_ELLIPSIS" "$RESET"
}

# Find a private key in the store matching one of the file's recipients.
_tui_find_own_key() {
    local fp f have
    for f in "$CERT_DIR"/*.pem; do
        [[ -f "$f" && -f "${f%.pem}.key" ]] || continue
        have=$(crypto_cert_fingerprint "$f") || continue
        for fp in "${ENC_META_RCPT[@]:-}"; do
            if [[ "$fp" == "$have" ]]; then printf '%s' "${f%.pem}.key"; return 0; fi
        done
    done
    return 1
}

# Collect the credentials needed for the container in ENC_META.
# Returns 1 if the user cancels.
_tui_collect_credentials() {
    local rc
    case "${ENC_META[format]}:${ENC_META[mode]:-}" in
        v3:password)
            ui_prompt_secret "Password" || return 1
            ENC_SECRET="$UI_REPLY" ;;
        v3:recipient|legacy-smime:*)
            local key=""
            if [[ "${ENC_META[format]}" == "v3" ]] && key=$(_tui_find_own_key); then
                ui_info "Using your key $(basename "$key") (it matches a recipient of this file)."
            else
                cert_ui_pick "Private key to decrypt with" key || return 1
                key="$UI_CHOICE"
                tui_screen "Decrypt"
            fi
            ENC_KEY_FILE="$key"
            [[ -f "${key%.key}.pem" ]] && ENC_CERT_FILE="${key%.key}.pem"
            if crypto_key_is_encrypted "$key"; then
                ui_prompt_secret "Passphrase for $(basename "$key")" || return 1
                ENC_KEY_SECRET="$UI_REPLY"
            fi ;;
        legacy-enc:*)
            ui_warn "Legacy file: the algorithm was not stored, and the content cannot be authenticated."
            local c
            ui_sel_reset
            for c in "${ENC_CIPHER_IDS[@]}"; do ui_sel_add "$c" "$c" ""; done
            UI_SEL_HEADER="$(tui_header "Decrypt" "Legacy Encryptor 2.x file")"
            UI_SEL_HOTKEYS=0; UI_SEL_START="aes-256-cbc"
            ui_sel_run "Which algorithm was used to encrypt it?" || return 1
            ENC_LEGACY_ALGO="$UI_CHOICE"
            UI_SEL_HEADER="$(tui_header "Decrypt" "Legacy Encryptor 2.x file")"
            ui_select "Which version created the file?" \
                "1|Encryptor 2.1|PBKDF2 600,000 iterations" \
                "0|Encryptor 2.0|PBKDF2 100,000 iterations" || return 1
            if [[ "$UI_CHOICE" == "0" ]]; then ENC_LEGACY_ITER=$ENC_LEGACY_ITER_V20; else ENC_LEGACY_ITER=$ENC_LEGACY_ITER_V21; fi
            tui_screen "Decrypt"
            ui_prompt_secret "Password" || return 1
            ENC_SECRET="$UI_REPLY" ;;
    esac
    return 0
}

# --- Decrypt wizard ----------------------------------------------------------
tui_decrypt() {
    local in out rc attempt
    ui_pick_file "Select a file to decrypt" "." "$(tui_header "Decrypt")" || return 0
    in="$UI_CHOICE"

    tui_screen "Decrypt"
    if ! crypto_inspect "$in"; then
        UI_PANEL_COLOR="$C_ERR"
        ui_panel "$G_ERR Cannot decrypt" "$ENC_ERR"
        ui_pause; return 0
    fi
    _tui_describe "$in"
    ui_panel "Detected" "${TUI_DESC[@]}"
    echo

    local def="${in}.dec"
    [[ "$in" == *.enc ]] && def="${in%.enc}"

    for attempt in 1 2 3; do
        crypto_reset_inputs
        _tui_collect_credentials || { crypto_reset_inputs; return 0; }
        if (( attempt == 1 )); then
            _tui_resolve_output "$def" || { crypto_reset_inputs; return 0; }
            out="$UI_REPLY"
            tui_screen "Decrypt" "$(ui_pathfit "$in")"
        fi
        local t0 t1; t0=$(now_ms)
        TUI_ACTIVE=1
        crypto_decrypt "$in" "$out"; rc=$?
        TUI_ACTIVE=0; ui_spinner_stop
        t1=$(now_ms)
        (( rc == 0 )) && break
        log_operation "ERROR" "Decrypt failed: $in — $ENC_ERR"
        ui_err "$ENC_ERR"
        if (( rc != EX_AUTH || attempt == 3 )); then
            ui_note "No output was written."
            crypto_reset_inputs; ui_pause; return 0
        fi
        ui_note "Try again ($(( 3 - attempt )) attempt(s) left)."
        echo
    done
    crypto_reset_inputs

    log_operation "SUCCESS" "Decrypted: $in → $out (format=${ENC_META[format]})"
    local auth="${C_OK}verified before decryption${RESET}"
    [[ "${ENC_META[format]}" == v3 ]] || auth="${C_WARN}not available for legacy files${RESET}"
    echo
    UI_PANEL_COLOR="$C_OK"
    ui_panel "$G_OK Decrypted" \
        "$(ui_row "Source" "$(ui_pathfit "$in")")" \
        "$(ui_row "Output" "${C_OK}$(ui_pathfit "$out")${RESET}  ${C_MUTED}($(human_size "$ENC_RESULT_BYTES_OUT"))${RESET}")" \
        "$(ui_row "Integrity" "$auth")" \
        "$(ui_row "Time" "$(( t1 - t0 )) ms")"
    if [[ "${ENC_META[format]}" != v3 ]]; then
        echo
        ui_info "Tip: re-encrypt this file to upgrade it to the authenticated ENCRYPTOR/3 format."
    fi
    echo
    if ui_confirm "Delete the encrypted file $(basename "$in")?" n; then
        rm -f -- "$in" "${in}.sha256" && ui_ok "Encrypted file removed."
        log_operation "INFO" "Encrypted file removed: $in"
    fi
    ui_pause
}

# --- Inspect / verify --------------------------------------------------------
tui_inspect() {
    local in rc
    ui_pick_file "Select an encrypted file to inspect" "." "$(tui_header "Inspect & verify")" || return 0
    in="$UI_CHOICE"
    tui_screen "Inspect & verify"
    if ! crypto_inspect "$in"; then
        UI_PANEL_COLOR="$C_WARN"
        ui_panel "$G_WARN Not an Encryptor file" "$ENC_ERR"
        ui_pause; return 0
    fi
    _tui_describe "$in"
    ui_panel "Container" "${TUI_DESC[@]}"
    echo
    if [[ "${ENC_META[format]}" != v3 ]]; then
        ui_warn "Legacy files have no authentication tag: integrity cannot be verified."
        ui_pause; return 0
    fi
    ui_note "Verification checks the authentication tag over the whole file without writing any plaintext."
    if ui_confirm "Verify now?" y; then
        crypto_reset_inputs
        if _tui_collect_credentials; then
            TUI_ACTIVE=1; crypto_verify "$in"; rc=$?; TUI_ACTIVE=0; ui_spinner_stop
            if (( rc == 0 )); then ui_ok "${BOLD}Authentic${RESET} — the file is intact and your credentials are correct."
            else ui_err "$ENC_ERR"; fi
            log_operation "INFO" "Verify: $in → rc=$rc"
        fi
        crypto_reset_inputs
    fi
    ui_pause
}

# --- Activity log ------------------------------------------------------------
tui_log() {
    tui_screen "Activity log" "$(ui_pathfit "$LOG_FILE")"
    if [[ ! -s "$LOG_FILE" ]]; then ui_note "No activity recorded yet."; ui_pause; return 0; fi
    local line col
    {
        while IFS= read -r line; do
            col=""
            case "$line" in
                *"[SUCCESS]"*) col="$C_OK" ;;
                *"[ERROR]"*)   col="$C_ERR" ;;
                *"[WARN]"*)    col="$C_WARN" ;;
                *)             col="$C_MUTED" ;;
            esac
            printf '%s%s%s\n' "$col" "$line" "$RESET"
        done < <(tail -n 500 "$LOG_FILE")
    } | ui_pager
    (( UI_TTY )) && have less || ui_pause
}

tui_help() {
    ui_clear
    cli_help_text | ui_pager
    (( UI_TTY )) && have less || ui_pause
}

# --- Main menu ---------------------------------------------------------------
_tui_main_header() {
    core_probe_openssl
    pki_store_summary
    ui_banner
    printf '  %sAuthenticated file encryption %s X.509 toolkit%s%*s%sv%s%s\n' "$C_MUTED" "$G_DOT" "$RESET" 6 '' "$C_ACCENT" "$ENCRYPTOR_VERSION" "$RESET"
    printf ' %s%s%s\n' "$C_MUTED" "$(ui_repeat "$G_H" "$UI_W")" "$RESET"
    printf '  %s%s%s %s   %s%s%s %s   %s%s%s PBKDF2 %s\n' \
        "$C_OK" "$G_INFO" "$RESET" "$OPENSSL_VERSION_TEXT" \
        "$C_OK" "$G_INFO" "$RESET" "${ENC_CIPHER_LABEL[$TUI_CIPHER]}" \
        "$C_OK" "$G_INFO" "$RESET" "$ENC_DEFAULT_ITER"
    local certline="${C_INFO}${G_INFO}${RESET} ${PKI_COUNT_CERTS} certificate(s) ${G_DOT} ${PKI_COUNT_KEYS} key(s)"
    (( PKI_COUNT_EXPIRED > 0 ))  && certline+="   ${C_ERR}${G_ERR} ${PKI_COUNT_EXPIRED} expired${RESET}"
    (( PKI_COUNT_EXPIRING > 0 )) && certline+="   ${C_WARN}${G_WARN} ${PKI_COUNT_EXPIRING} expiring soon${RESET}"
    printf '  %s   %s%s%s %s\n' "$certline" "$C_INFO" "$G_INFO" "$RESET" "$(ui_pathfit "$PWD" 34)"
    local last=""
    [[ -s "$LOG_FILE" ]] && last=$(tail -n 1 "$LOG_FILE" 2>/dev/null)
    [[ -n "$last" ]] && printf '  %sLast: %s%s\n' "$C_MUTED" "$(ui_fit "$last" $(( UI_W - 8 )))" "$RESET"
    printf ' %s%s%s' "$C_MUTED" "$(ui_repeat "$G_H" "$UI_W")" "$RESET"
}

tui_main() {
    core_init_state
    ui_screen_enter
    log_operation "INFO" "Interactive session started (v${ENCRYPTOR_VERSION})"
    local rc
    while true; do
        UI_SEL_HEADER="$(_tui_main_header)"
        ui_select "Main menu" \
            "e|Encrypt a file|password or certificate recipients" \
            "d|Decrypt a file|format is detected automatically" \
            "i|Inspect & verify|read metadata, check integrity without decrypting" \
            "-" \
            "c|Certificates & keys|identities, CA, signing, PKCS#12" \
            "a|Security audit|self-test, permissions, expiry, TLS scan" \
            "-" \
            "l|Activity log|" \
            "h|Help|" \
            "q|Quit|"
        rc=$?
        if (( rc != 0 )); then UI_CHOICE="q"; fi
        case "$UI_CHOICE" in
            e) tui_encrypt ;;
            d) tui_decrypt ;;
            i) tui_inspect ;;
            c) cert_ui_menu ;;
            a) audit_ui_menu ;;
            l) tui_log ;;
            h) tui_help ;;
            q)
                log_operation "INFO" "Interactive session ended"
                ui_screen_leave
                return 0 ;;
        esac
    done
}
