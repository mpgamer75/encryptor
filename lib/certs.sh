#!/usr/bin/env bash
# ==============================================================================
# lib/certs.sh — X.509 / PKI: engine functions (pki_*) + interactive screens
#                (cert_ui_*).
#
# Engine conventions: no prompting, no terminal output; failures are described
# in $ENC_ERR. Passphrases are passed to openssl through anonymous pipes.
# All objects live in $CERT_DIR:  NAME.key  NAME.pem  NAME.csr  NAME.p12
# ==============================================================================

declare -A PKI_KEY_LABEL=(
    [ec256]="ECDSA P-256"  [ec384]="ECDSA P-384"
    [rsa3072]="RSA 3072-bit" [rsa4096]="RSA 4096-bit"
)
readonly PKI_EXPIRY_WARN_DAYS=30
readonly PKI_KEY_KDF_ITER=600000     # PBKDF2 iterations protecting key files and PKCS#12 bundles

declare -A PKI_INFO=()

# --- Validation helpers -----------------------------------------------------
# Escape a value for an OpenSSL config file (quotes, comment and variable
# characters are neutralised). Control characters are rejected by the callers.
_pki_conf_escape() {
    local s="$1" out="" i ch
    for (( i = 0; i < ${#s}; i++ )); do
        ch="${s:i:1}"
        case "$ch" in
            '\'|'$'|'#'|'"'|"'"|'`'|';') out+="\\$ch" ;;
            *) out+="$ch" ;;
        esac
    done
    printf '%s' "$out"
}

pki_valid_text() {    # free-text DN component: 1-64 chars, no control characters
    local s="$1"
    [[ -n "$s" && ${#s} -le 64 ]] || return 1
    # ui_safe replaces C0, DEL, C1 and line-separator characters: a value it
    # would change contains something that must not go into a certificate.
    [[ "$(ui_safe "$s")" == "$s" ]]
}
pki_valid_country() { [[ "$1" =~ ^[A-Za-z]{2}$ ]]; }
pki_valid_email()   { [[ "$1" =~ ^[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)+$ ]]; }
pki_valid_dns()     { [[ "$1" =~ ^(\*\.)?[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?(\.[A-Za-z0-9]([A-Za-z0-9-]*[A-Za-z0-9])?)*$ ]]; }
pki_valid_ip() {
    local ip="$1" o
    if [[ "$ip" =~ ^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})$ ]]; then
        for o in "${BASH_REMATCH[@]:1}"; do (( 10#$o <= 255 )) || return 1; done
        return 0
    fi
    [[ "$ip" =~ ^[0-9A-Fa-f:]+:[0-9A-Fa-f:]*$ && ${#ip} -le 39 ]]
}
# Numbers are always read in base 10 ("030" is thirty, not octal).
pki_valid_days()    { [[ "$1" =~ ^[0-9]{1,5}$ ]] && (( 10#$1 >= 1 && 10#$1 <= 36500 )); }

# Facts about a certificate or CSR are taken from fields OpenSSL prints on
# their own, or from the public key itself — never from a text search that a
# crafted subject name could satisfy.
pki_is_ca() {      # basicConstraints CA:TRUE
    openssl x509 -in "$1" -noout -text 2>/dev/null \
        | awk 'seen == 1 { if ($0 ~ /CA:TRUE/) found = 1; seen = 2 } /^ +X509v3 Basic Constraints:/ && !seen { seen = 1 } END { exit !found }'
}
_pki_ext_value() { # _pki_ext_value CERT "X509v3 Key Usage" → the value line, trimmed
    openssl x509 -in "$1" -noout -text 2>/dev/null \
        | awk -v name="$2" 'seen == 1 { sub(/^ +/, ""); print; seen = 2 } $0 ~ "^ +" name ":" && !seen { seen = 1 }'
}
_pki_csr_is_ec() {
    local text
    text=$(openssl req -in "$1" -noout -pubkey 2>/dev/null | openssl pkey -pubin -noout -text 2>/dev/null)
    grep -Eq '^(ASN1 OID|NIST CURVE)' <<<"$text"
}

# Build a subjectAltName value from a comma-separated user list.
# Entries: DNS names, IP addresses, e-mail addresses. Prints "DNS:a,IP:b,email:c".
pki_build_san() {
    local list="$1" out="" item
    local -a items=()
    IFS=',' read -r -a items <<<"$list"
    for item in "${items[@]:-}"; do
        item=$(trim "$item"); [[ -z "$item" ]] && continue
        if pki_valid_ip "$item"; then out+="${out:+,}IP:$item"
        elif [[ "$item" == *@* ]]; then pki_valid_email "$item" || return 1; out+="${out:+,}email:$item"
        elif pki_valid_dns "$item"; then out+="${out:+,}DNS:$item"
        else return 1; fi
    done
    printf '%s' "$out"
}

# --- Key generation ---------------------------------------------------------
# pki_generate_key OUT TYPE [PASSPHRASE]
pki_generate_key() {
    local out="$1" type="$2" secret="${3:-}"
    local -a args=()
    case "$type" in
        ec256)   args=(-algorithm EC -pkeyopt ec_paramgen_curve:P-256 -pkeyopt ec_param_enc:named_curve) ;;
        ec384)   args=(-algorithm EC -pkeyopt ec_paramgen_curve:P-384 -pkeyopt ec_param_enc:named_curve) ;;
        rsa3072) args=(-algorithm RSA -pkeyopt rsa_keygen_bits:3072) ;;
        rsa4096) args=(-algorithm RSA -pkeyopt rsa_keygen_bits:4096) ;;
        *) ENC_ERR="Unknown key type: $type"; return "$EX_USAGE" ;;
    esac
    local rc
    if [[ -n "$secret" ]]; then
        crypto_check_secret "$secret" "Key passphrase" || return "$EX_USAGE"
        # The key travels over a pipe into PKCS#8 encryption with AES-256 and
        # PBKDF2-HMAC-SHA256 at 600,000 iterations (genpkey's own -aes-256-cbc
        # would use only 2,048).
        ( umask 077
          openssl genpkey "${args[@]}" 2>/dev/null \
            | openssl pkcs8 -topk8 -v2 aes-256-cbc -v2prf hmacWithSHA256 -iter "$PKI_KEY_KDF_ITER" \
                -passout fd:3 -out "$out" 3< <(printf '%s\n' "$secret") ) >/dev/null 2>&1; rc=$?
    else
        ( umask 077; openssl genpkey "${args[@]}" -out "$out" ) >/dev/null 2>&1; rc=$?
    fi
    if (( rc != 0 )) || [[ ! -s "$out" ]]; then
        rm -f -- "$out"; ENC_ERR="Key generation failed (${PKI_KEY_LABEL[$type]})."; return "$EX_FAIL"
    fi
    chmod 400 "$out" 2>/dev/null || true
    return 0
}

_pki_is_ec_type() { [[ "$1" == ec* ]]; }

# Write a throw-away OpenSSL config with the subject and our extension profiles.
#   _pki_write_config FILE IS_EC CN ORG COUNTRY EMAIL SAN
_pki_write_config() {
    local file="$1" is_ec="$2" cn="$3" org="$4" country="$5" email="$6" san="$7"
    local ku_leaf="digitalSignature, keyEncipherment"
    [[ "$is_ec" == "1" ]] && ku_leaf="digitalSignature, keyAgreement"
    {
        printf '[req]\nprompt = no\nutf8 = yes\nstring_mask = utf8only\ndistinguished_name = dn\n\n[dn]\n'
        [[ -n "$country" ]] && printf 'C = %s\n' "${country^^}"
        [[ -n "$org" ]]     && printf 'O = %s\n' "$(_pki_conf_escape "$org")"
        printf 'CN = %s\n' "$(_pki_conf_escape "$cn")"
        [[ -n "$email" ]]   && printf 'emailAddress = %s\n' "$email"

        printf '\n[ca]\nbasicConstraints = critical, CA:TRUE, pathlen:0\nkeyUsage = critical, keyCertSign, cRLSign\nsubjectKeyIdentifier = hash\n'

        printf '\n[identity]\nbasicConstraints = critical, CA:FALSE\nkeyUsage = critical, %s\nextendedKeyUsage = emailProtection, clientAuth\nsubjectKeyIdentifier = hash\n' "$ku_leaf"
        [[ -n "$san" ]] && printf 'subjectAltName = %s\n' "$san"

        printf '\n[server]\nbasicConstraints = critical, CA:FALSE\nkeyUsage = critical, %s\nextendedKeyUsage = serverAuth\nsubjectKeyIdentifier = hash\n' "$ku_leaf"
        [[ -n "$san" ]] && printf 'subjectAltName = %s\n' "$san"

        printf '\n[client]\nbasicConstraints = critical, CA:FALSE\nkeyUsage = critical, digitalSignature\nextendedKeyUsage = clientAuth\nsubjectKeyIdentifier = hash\n'
        [[ -n "$san" ]] && printf 'subjectAltName = %s\n' "$san"
    } > "$file"
}

_pki_check_new_name() {
    local name="$1"; shift
    if ! is_safe_name "$name"; then
        ENC_ERR="Invalid name '$name'. Use letters, digits, dot, dash and underscore (max 64 characters)."; return "$EX_USAGE"
    fi
    local ext
    for ext in "$@"; do
        if [[ -e "$CERT_DIR/$name.$ext" ]]; then
            ENC_ERR="$CERT_DIR/$name.$ext already exists. Choose another name."; return "$EX_CANTCREAT"
        fi
    done
    return 0
}

# openssl req with an optional key passphrase on fd 3.
_pki_req() {
    local secret="$1"; shift
    if [[ -n "$secret" ]]; then
        openssl req "$@" -passin fd:3 3< <(printf '%s\n' "$secret") 2>/dev/null
    else
        openssl req "$@" 2>/dev/null
    fi
}

# --- Create a self-signed identity (key + certificate for file encryption) --
# pki_create_identity NAME CN EMAIL KEYTYPE DAYS [PASSPHRASE]
pki_create_identity() {
    local name="$1" cn="$2" email="$3" type="$4" days="$5" secret="${6:-}"
    ENC_ERR=""
    core_init_state
    _pki_check_new_name "$name" key pem || return $?
    pki_valid_text "$cn" || { ENC_ERR="Invalid common name."; return "$EX_USAGE"; }
    [[ -z "$email" ]] || pki_valid_email "$email" || { ENC_ERR="Invalid e-mail address."; return "$EX_USAGE"; }
    pki_valid_days "$days" || { ENC_ERR="Validity must be 1–36500 days."; return "$EX_USAGE"; }
    days=$(( 10#$days ))

    local key="$CERT_DIR/$name.key" cert="$CERT_DIR/$name.pem" is_ec=0 san=""
    _pki_is_ec_type "$type" && is_ec=1
    [[ -n "$email" ]] && san="email:$email"
    core_tmpdir
    local cnf="$TEMP_DIR/pki.cnf"
    _pki_write_config "$cnf" "$is_ec" "$cn" "" "" "$email" "$san"
    pki_generate_key "$key" "$type" "$secret" || { rm -f "$cnf"; return "$EX_FAIL"; }
    if ! _pki_req "$secret" -new -x509 -key "$key" -config "$cnf" -extensions identity -sha256 -days "$days" -out "$cert" || [[ ! -s "$cert" ]]; then
        rm -f -- "$key" "$cert" "$cnf"; ENC_ERR="Certificate creation failed."; return "$EX_FAIL"
    fi
    rm -f "$cnf"
    chmod 644 "$cert" 2>/dev/null || true
    log_operation "SUCCESS" "Identity created: $cert (${PKI_KEY_LABEL[$type]}, ${days}d)"
    return 0
}

# --- Create a root CA -------------------------------------------------------
# pki_create_ca NAME CN ORG COUNTRY KEYTYPE DAYS [PASSPHRASE]
pki_create_ca() {
    local name="$1" cn="$2" org="$3" country="$4" type="$5" days="$6" secret="${7:-}"
    ENC_ERR=""
    core_init_state
    _pki_check_new_name "$name" key pem || return $?
    pki_valid_text "$cn" || { ENC_ERR="Invalid common name."; return "$EX_USAGE"; }
    [[ -z "$org" ]] || pki_valid_text "$org" || { ENC_ERR="Invalid organization name."; return "$EX_USAGE"; }
    [[ -z "$country" ]] || pki_valid_country "$country" || { ENC_ERR="Country must be a 2-letter code (e.g. FR, US)."; return "$EX_USAGE"; }
    pki_valid_days "$days" || { ENC_ERR="Validity must be 1–36500 days."; return "$EX_USAGE"; }
    days=$(( 10#$days ))

    local key="$CERT_DIR/$name.key" cert="$CERT_DIR/$name.pem" is_ec=0
    _pki_is_ec_type "$type" && is_ec=1
    core_tmpdir
    local cnf="$TEMP_DIR/pki.cnf"
    _pki_write_config "$cnf" "$is_ec" "$cn" "$org" "$country" "" ""
    pki_generate_key "$key" "$type" "$secret" || { rm -f "$cnf"; return "$EX_FAIL"; }
    if ! _pki_req "$secret" -new -x509 -key "$key" -config "$cnf" -extensions ca -sha256 -days "$days" -out "$cert" || [[ ! -s "$cert" ]]; then
        rm -f -- "$key" "$cert" "$cnf"; ENC_ERR="CA certificate creation failed."; return "$EX_FAIL"
    fi
    rm -f "$cnf"
    chmod 644 "$cert" 2>/dev/null || true
    log_operation "SUCCESS" "Root CA created: $cert (${PKI_KEY_LABEL[$type]}, ${days}d)"
    return 0
}

# --- Create key + CSR -------------------------------------------------------
# pki_create_csr NAME CN EMAIL ORG KEYTYPE [PASSPHRASE]
pki_create_csr() {
    local name="$1" cn="$2" email="$3" org="$4" type="$5" secret="${6:-}"
    ENC_ERR=""
    core_init_state
    _pki_check_new_name "$name" key csr || return $?
    pki_valid_text "$cn" || { ENC_ERR="Invalid common name."; return "$EX_USAGE"; }
    [[ -z "$email" ]] || pki_valid_email "$email" || { ENC_ERR="Invalid e-mail address."; return "$EX_USAGE"; }
    [[ -z "$org" ]] || pki_valid_text "$org" || { ENC_ERR="Invalid organization name."; return "$EX_USAGE"; }

    local key="$CERT_DIR/$name.key" csr="$CERT_DIR/$name.csr" is_ec=0
    _pki_is_ec_type "$type" && is_ec=1
    core_tmpdir
    local cnf="$TEMP_DIR/pki.cnf"
    _pki_write_config "$cnf" "$is_ec" "$cn" "$org" "" "$email" ""
    pki_generate_key "$key" "$type" "$secret" || { rm -f "$cnf"; return "$EX_FAIL"; }
    if ! _pki_req "$secret" -new -key "$key" -config "$cnf" -sha256 -out "$csr" || [[ ! -s "$csr" ]]; then
        rm -f -- "$key" "$csr" "$cnf"; ENC_ERR="CSR creation failed."; return "$EX_FAIL"
    fi
    rm -f "$cnf"
    log_operation "SUCCESS" "Key + CSR created: $csr (${PKI_KEY_LABEL[$type]})"
    return 0
}

# --- Sign a CSR -------------------------------------------------------------
# pki_sign_csr CSR CA_CERT CA_KEY PROFILE DAYS SAN_LIST OUT [CA_PASSPHRASE]
#   PROFILE: identity | server | client
pki_sign_csr() {
    local csr="$1" ca_cert="$2" ca_key="$3" profile="$4" days="$5" san_list="$6" out="$7" secret="${8:-}"
    ENC_ERR=""
    local f
    for f in "$csr" "$ca_cert" "$ca_key"; do
        [[ -f "$f" && -r "$f" ]] || { ENC_ERR="File not found: $f"; return "$EX_NOINPUT"; }
    done
    case "$profile" in identity|server|client) ;; *) ENC_ERR="Unknown profile: $profile"; return "$EX_USAGE" ;; esac
    pki_valid_days "$days" || { ENC_ERR="Validity must be 1–36500 days."; return "$EX_USAGE"; }
    days=$(( 10#$days ))
    # `openssl req -verify` exits 0 even for a bad signature on OpenSSL 3.0:
    # rely on its message, not its status.
    local csr_check; csr_check=$(openssl req -in "$csr" -noout -verify 2>&1)
    if [[ "$csr_check" != *"verify OK"* ]]; then
        ENC_ERR="The CSR is invalid or its signature does not verify."; return "$EX_FAIL"
    fi
    if ! pki_is_ca "$ca_cert"; then
        ENC_ERR="$(ui_base "$ca_cert") is not a CA certificate (basicConstraints CA:TRUE missing)."; return "$EX_FAIL"
    fi
    if ! openssl x509 -in "$ca_cert" -noout -checkend 0 >/dev/null 2>&1; then
        ENC_ERR="The CA certificate $(ui_base "$ca_cert") has expired."; return "$EX_FAIL"
    fi
    local ca_ku; ca_ku=$(_pki_ext_value "$ca_cert" "X509v3 Key Usage")
    if [[ -n "$ca_ku" && "$ca_ku" != *"Certificate Sign"* ]]; then
        ENC_ERR="The CA certificate's key usage ($ca_ku) does not allow signing certificates."; return "$EX_FAIL"
    fi
    # A certificate that outlives its issuer cannot be validated after the
    # issuer expires.
    local ca_end ca_left
    ca_end=$(openssl x509 -in "$ca_cert" -noout -enddate 2>/dev/null); ca_end=$(core_date_epoch "${ca_end#*=}")
    if [[ -n "$ca_end" ]]; then
        ca_left=$(( (ca_end - $(date -u +%s)) / 86400 ))
        if (( days > ca_left )); then
            ENC_ERR="The CA itself expires in ${ca_left} days: choose a validity of at most ${ca_left} days."; return "$EX_USAGE"
        fi
    fi
    local san=""
    if [[ -n "$san_list" ]]; then
        san=$(pki_build_san "$san_list") || { ENC_ERR="Invalid subject alternative name list."; return "$EX_USAGE"; }
    fi
    if [[ "$profile" == "server" && -z "$san" ]]; then
        ENC_ERR="Server certificates need at least one DNS name or IP address (subjectAltName)."; return "$EX_USAGE"
    fi
    [[ -e "$out" ]] && { ENC_ERR="$out already exists."; return "$EX_CANTCREAT"; }

    local is_ec=0
    _pki_csr_is_ec "$csr" && is_ec=1
    if [[ -n "$secret" ]]; then crypto_check_secret "$secret" "CA key passphrase" || return "$EX_USAGE"; fi
    core_tmpdir
    local cnf="$TEMP_DIR/pki.cnf" serial rc
    _pki_write_config "$cnf" "$is_ec" "unused" "" "" "" "$san"
    serial="0x$(openssl rand -hex 16 2>/dev/null)"
    local -a args=(x509 -req -in "$csr" -CA "$ca_cert" -CAkey "$ca_key" -set_serial "$serial"
                   -days "$days" -sha256 -extfile "$cnf" -extensions "$profile" -out "$out")
    if [[ -n "$secret" ]]; then
        openssl "${args[@]}" -passin fd:3 3< <(printf '%s\n' "$secret") >/dev/null 2>&1; rc=$?
    else
        openssl "${args[@]}" </dev/null >/dev/null 2>&1; rc=$?
    fi
    rm -f "$cnf"
    if (( rc != 0 )) || [[ ! -s "$out" ]]; then
        rm -f -- "$out"; ENC_ERR="Signing failed (wrong CA key or passphrase?)."; return "$EX_FAIL"
    fi
    chmod 644 "$out" 2>/dev/null || true
    log_operation "SUCCESS" "CSR signed: $csr → $out (profile=$profile, ${days}d)"
    return 0
}

# --- Certificate information ------------------------------------------------
# pki_cert_info FILE → PKI_INFO[subject|issuer|cn|not_before|not_after|days_left|
#   status|key_algo|key_bits|sig_algo|fingerprint|serial|is_ca|self_signed|usage]
pki_cert_info() {
    local file="$1" text hashes kinfo
    PKI_INFO=()
    openssl x509 -in "$file" -noout >/dev/null 2>&1 || return 1

    # Each field is queried on its own and only its first line is used, with
    # control characters escaped by OpenSSL (esc_ctrl) and then by ui_safe:
    # a crafted name cannot inject a fake "issuer=" line or terminal escapes.
    _pki_field() { openssl x509 -in "$file" -noout "$1" -nameopt utf8,esc_ctrl,sep_comma_plus_space 2>/dev/null | sed -n '1p'; }
    local v
    v=$(_pki_field -subject);     PKI_INFO[subject]=$(ui_safe "$(trim "${v#subject=}")")
    v=$(_pki_field -issuer);      PKI_INFO[issuer]=$(ui_safe "$(trim "${v#issuer=}")")
    v=$(_pki_field -startdate);   PKI_INFO[not_before]=$(ui_safe "${v#notBefore=}")
    v=$(_pki_field -enddate);     PKI_INFO[not_after]=$(ui_safe "${v#notAfter=}")
    v=$(_pki_field -serial);      PKI_INFO[serial]=$(ui_safe "${v#serial=}")
    v=$(openssl x509 -in "$file" -noout -fingerprint -sha256 2>/dev/null | sed -n '1p')
    PKI_INFO[fingerprint]=$(ui_safe "${v#*=}")
    unset -f _pki_field

    local cn="${PKI_INFO[subject]}"
    if [[ "$cn" == *CN=* ]]; then cn="${cn##*CN=}"; cn="${cn%%, *}"; fi
    PKI_INFO[cn]="$cn"

    # Key type and size from the public key itself.
    kinfo=$(crypto_cert_key_info "$file") || kinfo="other 0"
    PKI_INFO[key_type]=${kinfo% *}
    PKI_INFO[key_bits]=${kinfo#* }
    text=$(openssl x509 -in "$file" -noout -text 2>/dev/null)
    PKI_INFO[key_algo]=$(sed -n 's/^ \{1,\}Public Key Algorithm: *//p' <<<"$text" | sed -n '1p')
    PKI_INFO[sig_algo]=$(sed -n 's/^ \{1,\}Signature Algorithm: *//p' <<<"$text" | sed -n '1p')
    PKI_INFO[sig_hash]=$(sed -n 's/^ \{1,\}Hash Algorithm: *//p' <<<"$text" | sed -n '1p')     # RSA-PSS
    PKI_INFO[usage]=$(_pki_ext_value "$file" "X509v3 Key Usage")
    PKI_INFO[eku]=$(_pki_ext_value "$file" "X509v3 Extended Key Usage")
    PKI_INFO[san]=$(ui_safe "$(_pki_ext_value "$file" "X509v3 Subject Alternative Name")")
    if pki_is_ca "$file"; then PKI_INFO[is_ca]=1; else PKI_INFO[is_ca]=0; fi
    # Self-signed = issuer and subject are the same name (compared by hash,
    # not by their display strings).
    hashes=$(openssl x509 -in "$file" -noout -subject_hash -issuer_hash 2>/dev/null | tr '\n' ' ')
    if [[ -n "$hashes" && "${hashes%% *}" == "$(awk '{print $2}' <<<"$hashes")" ]]; then PKI_INFO[self_signed]=1; else PKI_INFO[self_signed]=0; fi

    local end now
    end=$(core_date_epoch "${PKI_INFO[not_after]}")
    if [[ -n "$end" ]]; then
        now=$(date -u +%s)
        PKI_INFO[days_left]=$(( (end - now) / 86400 ))
        (( end < now )) && PKI_INFO[days_left]=$(( (end - now - 86399) / 86400 ))
    else
        PKI_INFO[days_left]=""
    fi
    if ! openssl x509 -in "$file" -noout -checkend 0 >/dev/null 2>&1; then PKI_INFO[status]="expired"
    elif ! openssl x509 -in "$file" -noout -checkend $(( PKI_EXPIRY_WARN_DAYS * 86400 )) >/dev/null 2>&1; then PKI_INFO[status]="expiring"
    else PKI_INFO[status]="valid"; fi
    return 0
}

# Findings about a certificate's cryptographic strength (one per line).
pki_cert_findings() {
    local bits="${PKI_INFO[key_bits]:-0}" type="${PKI_INFO[key_type]:-other}" algo="${PKI_INFO[key_algo]:-}"
    local sig="${PKI_INFO[sig_algo]:-}" hash="${PKI_INFO[sig_hash]:-}"
    [[ "$bits" =~ ^[0-9]+$ ]] || bits=0
    case "$type" in
        rsa)
            if   (( bits < 2048 )); then echo "fail|RSA key is only ${bits} bits — below the 2048-bit minimum."
            elif (( bits < 3072 )); then echo "warn|RSA ${bits}-bit: acceptable today; 3072+ recommended for long-lived keys."
            else echo "pass|RSA ${bits}-bit key."; fi ;;
        ec)
            if (( bits < 224 )); then echo "fail|EC key is only ${bits} bits."; else echo "pass|EC ${bits}-bit key."; fi ;;
        *)
            case "${algo,,}" in
                *dsa*) echo "fail|DSA keys are obsolete — replace this certificate." ;;
                *ed25519*|*ed448*) echo "pass|${algo} key." ;;
                *) echo "warn|Unrecognised key algorithm (${algo:-unknown}): strength not assessed." ;;
            esac ;;
    esac
    # For RSA-PSS the hash is a separate parameter.
    local sigdesc="${sig,,} ${hash,,}"
    case "$sigdesc" in
        *md5*|*md2*|*md4*) echo "fail|Signature uses MD5 — broken, replace this certificate." ;;
        *sha1*)            echo "fail|Signature uses SHA-1 — deprecated, replace this certificate." ;;
        *sha224*|*sha256*|*sha384*|*sha512*|*sha3*|*ed25519*|*ed448*) echo "pass|Signature algorithm: ${sig}${hash:+ ($hash)}" ;;
        *) echo "warn|Unrecognised signature algorithm (${sig:-unknown}): strength not assessed." ;;
    esac
    case "${PKI_INFO[status]}" in
        expired)  echo "fail|Certificate has EXPIRED (${PKI_INFO[not_after]})." ;;
        expiring) echo "warn|Certificate expires within ${PKI_EXPIRY_WARN_DAYS} days (${PKI_INFO[not_after]})." ;;
        *)        echo "pass|Within its validity period." ;;
    esac
}

# --- Key ↔ certificate match -----------------------------------------------
# Compares public keys (works for RSA and EC). pki_match CERT KEY [PASSPHRASE]
pki_match() {
    local cert="$1" key="$2" secret="${3:-}" a b
    a=$(openssl x509 -in "$cert" -noout -pubkey 2>/dev/null | openssl pkey -pubin -outform DER 2>/dev/null | openssl dgst -sha256 -r 2>/dev/null)
    if [[ -n "$secret" ]]; then
        b=$(openssl pkey -in "$key" -pubout -outform DER -passin fd:3 3< <(printf '%s\n' "$secret") 2>/dev/null | openssl dgst -sha256 -r 2>/dev/null)
    else
        b=$(openssl pkey -in "$key" -pubout -outform DER </dev/null 2>/dev/null | openssl dgst -sha256 -r 2>/dev/null)
    fi
    a=${a%% *}; b=${b%% *}
    local empty="e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    if [[ -z "$a" || -z "$b" || "$a" == "$empty" || "$b" == "$empty" ]]; then
        ENC_ERR="Could not read the certificate or the key (wrong passphrase or corrupt file)."; return 2
    fi
    [[ "$a" == "$b" ]]
}

pki_verify_chain() { openssl verify -CAfile "$2" "$1" >/dev/null 2>&1; }

PKI_P12_ITER=0      # PBKDF2 iterations used by the last PKCS#12 export
# --- PKCS#12 export ---------------------------------------------------------
# pki_export_p12 CERT KEY OUT EXPORT_PASSWORD [KEY_PASSPHRASE]
# Always AES-256-CBC + PBKDF2 with a SHA-256 MAC (OpenSSL 1.1.1 would otherwise
# default to RC2-40/3DES).
pki_export_p12() {
    local cert="$1" key="$2" out="$3" secret="$4" key_secret="${5:-}" rc
    ENC_ERR=""
    [[ -n "$secret" ]] || { ENC_ERR="An export password is required."; return "$EX_USAGE"; }
    crypto_check_secret "$secret" "Export password" || return "$EX_USAGE"
    if [[ -n "$key_secret" ]]; then crypto_check_secret "$key_secret" "Key passphrase" || return "$EX_USAGE"; fi
    [[ -e "$out" ]] && { ENC_ERR="$out already exists."; return "$EX_CANTCREAT"; }
    local -a args=(pkcs12 -export -in "$cert" -inkey "$key" -out "$out" -name "$(basename "${cert%.*}")"
                   -keypbe AES-256-CBC -certpbe AES-256-CBC -macalg sha256 -passout fd:3)
    # OpenSSL 3.x can raise the PBKDF2 work factor of the bundle; 1.1.1 has no
    # such option and always uses 2,048 iterations. Report what was really used.
    local help; help=$(openssl pkcs12 -help 2>&1)
    if [[ "$help" == *" -iter "* ]]; then
        args+=(-iter "$PKI_KEY_KDF_ITER"); PKI_P12_ITER=$PKI_KEY_KDF_ITER
    else
        PKI_P12_ITER=2048
    fi
    if [[ -n "$key_secret" ]]; then
        ( umask 077; openssl "${args[@]}" -passin fd:4 3< <(printf '%s\n' "$secret") 4< <(printf '%s\n' "$key_secret") ) >/dev/null 2>&1; rc=$?
    else
        ( umask 077; openssl "${args[@]}" 3< <(printf '%s\n' "$secret") </dev/null ) >/dev/null 2>&1; rc=$?
    fi
    if (( rc != 0 )) || [[ ! -s "$out" ]]; then
        rm -f -- "$out"; ENC_ERR="PKCS#12 export failed (do the certificate and key match?)."; return "$EX_FAIL"
    fi
    log_operation "SUCCESS" "PKCS#12 exported: $out"
    return 0
}

# --- Import a recipient certificate into the store --------------------------
pki_import_cert() {
    local src="$1" name="$2"
    ENC_ERR=""
    core_init_state
    openssl x509 -in "$src" -noout >/dev/null 2>&1 || { ENC_ERR="Not a PEM X.509 certificate: $src"; return "$EX_NOINPUT"; }
    _pki_check_new_name "$name" pem || return $?
    openssl x509 -in "$src" -out "$CERT_DIR/$name.pem" 2>/dev/null || { ENC_ERR="Import failed."; return "$EX_FAIL"; }
    chmod 644 "$CERT_DIR/$name.pem" 2>/dev/null || true
    log_operation "INFO" "Certificate imported: $CERT_DIR/$name.pem"
    return 0
}

# --- Store listing ----------------------------------------------------------
# pki_store_files EXT... → prints matching paths in CERT_DIR, one per line.
pki_store_files() {
    local ext f
    for ext in "$@"; do
        for f in "$CERT_DIR"/*."$ext"; do [[ -f "$f" ]] && printf '%s\n' "$f"; done
    done
}

# Summary counters used by the header and the audit: sets PKI_COUNT_*.
PKI_COUNT_CERTS=0; PKI_COUNT_KEYS=0; PKI_COUNT_EXPIRED=0; PKI_COUNT_EXPIRING=0
pki_store_summary() {
    PKI_COUNT_CERTS=0; PKI_COUNT_KEYS=0; PKI_COUNT_EXPIRED=0; PKI_COUNT_EXPIRING=0
    local f
    for f in "$CERT_DIR"/*.pem; do
        [[ -f "$f" ]] || continue
        (( PKI_COUNT_CERTS++ ))
        if ! openssl x509 -in "$f" -noout -checkend 0 >/dev/null 2>&1; then (( PKI_COUNT_EXPIRED++ ))
        elif ! openssl x509 -in "$f" -noout -checkend $(( PKI_EXPIRY_WARN_DAYS * 86400 )) >/dev/null 2>&1; then (( PKI_COUNT_EXPIRING++ )); fi
    done
    for f in "$CERT_DIR"/*.key; do [[ -f "$f" ]] && (( PKI_COUNT_KEYS++ )); done
    return 0
}

# Machine-readable certificate report. Exit status: 0 ok, 1 if any certificate
# is expired or expires within WARN_DAYS.
pki_report_json() {
    local warn_days="${1:-$PKI_EXPIRY_WARN_DAYS}" f first=1 bad=0 st has_key
    printf '{"store":"%s","warn_days":%d,"certificates":[' "$(json_escape "$CERT_DIR")" "$warn_days"
    for f in "$CERT_DIR"/*.pem; do
        [[ -f "$f" ]] || continue
        pki_cert_info "$f" || continue
        st="valid"
        if [[ "${PKI_INFO[status]}" == "expired" ]]; then st="expired"; bad=1
        elif ! openssl x509 -in "$f" -noout -checkend $(( warn_days * 86400 )) >/dev/null 2>&1; then st="expiring"; bad=1; fi
        has_key=false; [[ -f "${f%.pem}.key" ]] && has_key=true
        (( first )) || printf ','
        first=0
        printf '{"file":"%s","subject":"%s","issuer":"%s","not_after":"%s","days_left":%s,"status":"%s","is_ca":%s,"key":"%s %s","signature":"%s","fingerprint_sha256":"%s","has_private_key":%s}' \
            "$(json_escape "$f")" "$(json_escape "${PKI_INFO[subject]}")" "$(json_escape "${PKI_INFO[issuer]}")" \
            "$(json_escape "${PKI_INFO[not_after]}")" "${PKI_INFO[days_left]:-null}" "$st" \
            "$([[ "${PKI_INFO[is_ca]}" == 1 ]] && echo true || echo false)" \
            "$(json_escape "${PKI_INFO[key_algo]}")" "${PKI_INFO[key_bits]}" "$(json_escape "${PKI_INFO[sig_algo]}")" \
            "${PKI_INFO[fingerprint]}" "$has_key"
    done
    printf ']}\n'
    return $bad
}

# Plain-text certificate report (CLI `encryptor certs`).
pki_report_text() {
    local warn_days="${1:-$PKI_EXPIRY_WARN_DAYS}" f bad=0 n=0 st col mark days
    printf '%s%-28s %-8s %-14s %-12s %s%s\n' "$BOLD" "NAME" "TYPE" "KEY" "EXPIRES IN" "STATUS" "$RESET"
    for f in "$CERT_DIR"/*.pem; do
        [[ -f "$f" ]] || continue
        pki_cert_info "$f" || continue
        (( n++ ))
        st="valid"; col="$C_OK"; mark="$G_OK"
        if [[ "${PKI_INFO[status]}" == "expired" ]]; then st="EXPIRED"; col="$C_ERR"; mark="$G_ERR"; bad=1
        elif ! openssl x509 -in "$f" -noout -checkend $(( warn_days * 86400 )) >/dev/null 2>&1; then st="expiring"; col="$C_WARN"; mark="$G_WARN"; bad=1; fi
        days="${PKI_INFO[days_left]:-?}"
        printf '%-28s %-8s %-14s %-12s %s%s %s%s\n' \
            "$(ui_fit "$(ui_base "${f%.pem}")" 28)" \
            "$([[ "${PKI_INFO[is_ca]}" == 1 ]] && echo CA || echo leaf)" \
            "$(_pki_key_short)" "${days} days" "$col" "$mark" "$st" "$RESET"
    done
    (( n == 0 )) && printf '%s(no certificates in %s)%s\n' "$C_MUTED" "$CERT_DIR" "$RESET"
    return $bad
}

_pki_key_short() {
    case "${PKI_INFO[key_type]:-}" in
        rsa) printf 'RSA %s' "${PKI_INFO[key_bits]}" ;;
        ec)  printf 'EC P-%s' "${PKI_INFO[key_bits]}" ;;
        *)   printf '%s' "$(ui_safe "${PKI_INFO[key_algo]:-?}")" ;;
    esac
}

# Subject and key of a CSR, for confirmation before signing. Sets PKI_CSR_SUBJECT
# and PKI_CSR_KEY.
PKI_CSR_SUBJECT=""; PKI_CSR_KEY=""
pki_csr_info() {
    local csr="$1" v text bits
    v=$(openssl req -in "$csr" -noout -subject -nameopt utf8,esc_ctrl,sep_comma_plus_space 2>/dev/null | sed -n '1p') || return 1
    [[ -n "$v" ]] || return 1
    PKI_CSR_SUBJECT=$(ui_safe "$(trim "${v#subject=}")")
    text=$(openssl req -in "$csr" -noout -pubkey 2>/dev/null | openssl pkey -pubin -noout -text 2>/dev/null)
    bits=$(sed -n '1s/.*(\([0-9]*\) bit.*/\1/p' <<<"$text")
    if grep -q '^Modulus' <<<"$text"; then PKI_CSR_KEY="RSA ${bits}"
    elif grep -Eq '^(ASN1 OID|NIST CURVE)' <<<"$text"; then PKI_CSR_KEY="EC P-${bits}"
    else PKI_CSR_KEY="unknown key type"; fi
}

# ==============================================================================
# Interactive screens
# ==============================================================================

cert_ui_menu() {
    local rc
    while true; do
        pki_store_summary
        local sub
        sub="${PKI_COUNT_CERTS} certificate(s), ${PKI_COUNT_KEYS} private key(s) in $(ui_pathfit "$CERT_DIR")"
        UI_SEL_HEADER="$(tui_header "Certificates & keys" "$sub")"
        ui_select "What would you like to do?" \
            "1|Quick identity|key + self-signed certificate, ready for file encryption" \
            "2|Import a recipient certificate|add someone's .pem so you can encrypt for them" \
            "3|Dashboard|all certificates with expiry status" \
            "4|Inspect a certificate|details and strength analysis" \
            "-" \
            "#Certificate authority" \
            "5|Create a root CA|self-signed authority to issue certificates" \
            "6|Create key + signing request (CSR)|" \
            "7|Sign a CSR with a CA|identity, server or client profile" \
            "-" \
            "#Tools" \
            "8|Check a certificate / key pair|do they belong together? does the chain verify?" \
            "9|Export to PKCS#12 (.p12)|for browsers, mail clients, Windows, macOS" \
            "-" \
            "q|Back|"
        rc=$?
        (( rc != 0 )) && return 0
        case "$UI_CHOICE" in
            1) cert_ui_identity ;;
            2) cert_ui_import ;;
            3) cert_ui_dashboard ;;
            4) cert_ui_inspect ;;
            5) cert_ui_create_ca ;;
            6) cert_ui_create_csr ;;
            7) cert_ui_sign ;;
            8) cert_ui_check ;;
            9) cert_ui_export ;;
            q) return 0 ;;
        esac
    done
}

# Pick an object from the store by extension(s). Sets UI_CHOICE to a path.
#   cert_ui_pick "Title" ext [ext...]
cert_ui_pick() {
    local title="$1"; shift
    local f rc hint
    ui_sel_reset
    while IFS= read -r f; do
        [[ -n "$f" ]] || continue
        hint=""
        case "$f" in
            *.pem)
                if pki_cert_info "$f"; then
                    hint="${PKI_INFO[cn]}"
                    [[ "${PKI_INFO[is_ca]}" == 1 ]] && hint+="  ${G_DOT} CA"
                    case "${PKI_INFO[status]}" in
                        expired)  hint+="  ${G_DOT} EXPIRED" ;;
                        expiring) hint+="  ${G_DOT} expires in ${PKI_INFO[days_left]}d" ;;
                    esac
                fi ;;
            *.key) crypto_key_is_encrypted "$f" && hint="passphrase-protected" || hint="not encrypted" ;;
        esac
        ui_sel_add "$f" "$(ui_base "$f")" "$hint"
    done < <(pki_store_files "$@")
    ui_sel_add "@path" "Type a path${G_ELLIPSIS}" "file outside the store"
    UI_SEL_HEADER="$(tui_header "Certificates & keys")"
    UI_SEL_HOTKEYS=0
    ui_sel_run "$title"; rc=$?
    (( rc != 0 )) && return 1
    if [[ "$UI_CHOICE" == "@path" ]]; then
        ui_prompt_path "Path" || return 1
        [[ -f "$UI_REPLY" ]] || { ui_err "No such file: $UI_REPLY"; ui_pause; return 1; }
        UI_CHOICE="$UI_REPLY"
    fi
    return 0
}

_cert_ui_pick_keytype() {
    UI_SEL_HEADER="$(tui_header "Certificates & keys")"
    ui_select "Key type" \
        "ec256|ECDSA P-256|recommended: small, fast, widely supported" \
        "ec384|ECDSA P-384|higher security margin" \
        "rsa3072|RSA 3072-bit|maximum compatibility with older software" \
        "rsa4096|RSA 4096-bit|slow to generate, long-lived keys"
}

# Ask for a passphrase protecting a new private key. Sets UI_REPLY ("" = none).
_cert_ui_key_passphrase() {
    local what="$1"
    echo
    ui_note "A passphrase encrypts the private key file (AES-256). Without one, anyone"
    ui_note "who can read the file can use the key."
    if ui_confirm "Protect the ${what} with a passphrase?" y; then
        tui_new_secret "Key passphrase" || return 1
    else
        UI_REPLY=""
    fi
    return 0
}

_cert_ui_show_created() {
    local title="$1" cert="$2" key="$3" extra="${4:-}"
    local -a lines=()
    if [[ -n "$cert" ]] && pki_cert_info "$cert"; then
        lines+=("$(ui_row "Subject" "${PKI_INFO[subject]}")")
        lines+=("$(ui_row "Key" "$(_pki_key_short)")")
        lines+=("$(ui_row "Valid until" "${PKI_INFO[not_after]}  (${PKI_INFO[days_left]} days)")")
        lines+=("$(ui_row "Certificate" "$(ui_pathfit "$cert")")")
    fi
    if [[ -n "$key" ]]; then
        local prot="not encrypted"; crypto_key_is_encrypted "$key" && prot="passphrase-protected"
        lines+=("$(ui_row "Private key" "$(ui_pathfit "$key")")")
        lines+=("$(ui_row "Key file" "mode $(get_file_mode "$key") ${G_DOT} ${prot}")")
    fi
    [[ -n "$extra" ]] && lines+=("$extra")
    echo
    UI_PANEL_COLOR="$C_OK"
    ui_panel "$G_OK $title" "${lines[@]}"
    if [[ -n "$cert" && -n "${PKI_INFO[fingerprint]:-}" ]]; then
        echo
        ui_note "SHA-256 fingerprint (share it out-of-band so others can verify your certificate):"
        printf '  %s\n' "${PKI_INFO[fingerprint]}"
    fi
}

cert_ui_identity() {
    tui_screen "Quick identity" "Creates a private key and a self-signed certificate you can hand to others."
    ui_prompt "Short name (file name)" "${USER:-me}" || return
    local name="$UI_REPLY"
    is_safe_name "$name" || { ui_err "Use letters, digits, dot, dash, underscore."; ui_pause; return; }
    ui_prompt "Your name (certificate common name)" "$name" || return
    local cn="$UI_REPLY"
    ui_prompt "E-mail (optional)" "" || return
    local email="$UI_REPLY"
    _cert_ui_pick_keytype || return
    local type="$UI_CHOICE"
    tui_screen "Quick identity"
    _cert_ui_key_passphrase "private key" || return
    local secret="$UI_REPLY"
    ui_spinner_start "Generating ${PKI_KEY_LABEL[$type]} key and certificate${G_ELLIPSIS}"
    pki_create_identity "$name" "$cn" "$email" "$type" 825 "$secret"; local rc=$?
    ui_spinner_stop
    if (( rc != 0 )); then ui_err "$(ui_safe "$ENC_ERR")"; ui_pause; return; fi
    _cert_ui_show_created "Identity created" "$CERT_DIR/$name.pem" "$CERT_DIR/$name.key"
    echo
    ui_info "Send ${BOLD}$name.pem${RESET} to people who should encrypt files for you. Never share the .key file."
    ui_pause
}

cert_ui_import() {
    tui_screen "Import a recipient certificate" "Copies a PEM certificate into your store so it appears when encrypting."
    ui_prompt_path "Certificate file (.pem / .crt)" || return
    local src="$UI_REPLY"
    [[ -f "$src" ]] || { ui_err "No such file: $src"; ui_pause; return; }
    if ! pki_cert_info "$src"; then ui_err "Not a PEM X.509 certificate."; ui_pause; return; fi
    echo
    ui_panel "Certificate" \
        "$(ui_row "Subject" "${PKI_INFO[subject]}")" \
        "$(ui_row "Issuer" "${PKI_INFO[issuer]}$([[ "${PKI_INFO[self_signed]}" == 1 ]] && printf ' %s(self-signed)%s' "$C_WARN" "$RESET")")" \
        "$(ui_row "Public key" "$(_pki_key_short)")" \
        "$(ui_row "Valid until" "${PKI_INFO[not_after]}")" \
        "$(ui_row "Fingerprint" "${PKI_INFO[fingerprint]:0:47}")" \
        "$(ui_row "" "${PKI_INFO[fingerprint]:48}")"
    echo
    ui_warn "Names inside a certificate prove nothing by themselves. Verify the fingerprint"
    ui_note "  with the owner through a separate channel before trusting it."
    ui_confirm "Import this certificate?" n || return
    local def; def=$(basename "${src%.*}"); def=${def//[^A-Za-z0-9._-]/_}
    ui_prompt "Name in store" "$def" || return
    if pki_import_cert "$src" "$UI_REPLY"; then ui_ok "Imported as $(ui_pathfit "$CERT_DIR/$UI_REPLY.pem")"; else ui_err "$(ui_safe "$ENC_ERR")"; fi
    ui_pause
}

cert_ui_dashboard() {
    tui_screen "Certificate dashboard" "$(ui_pathfit "$CERT_DIR")"
    local f n=0 col mark st days kind
    printf '  %s%-26s %-8s %-12s %-20s %s%s\n' "$BOLD" "NAME" "TYPE" "KEY" "EXPIRES" "STATUS" "$RESET"
    printf '  %s%s%s\n' "$C_MUTED" "$(ui_repeat "$G_H" $(( UI_W - 2 )))" "$RESET"
    for f in "$CERT_DIR"/*.pem; do
        [[ -f "$f" ]] || continue
        pki_cert_info "$f" || continue
        (( n++ ))
        case "${PKI_INFO[status]}" in
            expired)  col="$C_ERR";  mark="$G_ERR";  st="expired" ;;
            expiring) col="$C_WARN"; mark="$G_WARN"; st="expiring soon" ;;
            *)        col="$C_OK";   mark="$G_OK";   st="valid" ;;
        esac
        days="${PKI_INFO[days_left]:-?}"
        kind="leaf"; [[ "${PKI_INFO[is_ca]}" == 1 ]] && kind="CA"
        [[ -f "${f%.pem}.key" ]] && kind+="+key"
        printf '  %-26s %-8s %-12s %-20s %s%s %s%s\n' "$(ui_fit "$(ui_base "${f%.pem}")" 26)" "${kind:0:8}" "$(_pki_key_short)" \
            "$(ui_fit "${days} days" 20)" "$col" "$mark" "$st" "$RESET"
    done
    (( n == 0 )) && ui_note "  No certificates yet — create a quick identity to get started."

    local k kn=0
    echo
    printf '  %s%-26s %-6s %s%s\n' "$BOLD" "PRIVATE KEY" "MODE" "PROTECTION" "$RESET"
    printf '  %s%s%s\n' "$C_MUTED" "$(ui_repeat "$G_H" $(( UI_W - 2 )))" "$RESET"
    for k in "$CERT_DIR"/*.key; do
        [[ -f "$k" ]] || continue
        (( kn++ ))
        local mode; mode=$(get_file_mode "$k")
        local mcol="$C_OK"; [[ "$mode" == "400" || "$mode" == "600" ]] || mcol="$C_ERR"
        if crypto_key_is_encrypted "$k"; then st="${C_OK}${G_OK} passphrase-protected${RESET}"; else st="${C_WARN}${G_WARN} not encrypted${RESET}"; fi
        printf '  %-26s %s%-6s%s %s\n' "$(ui_fit "$(ui_base "$k")" 26)" "$mcol" "$mode" "$RESET" "$st"
    done
    (( kn == 0 )) && ui_note "  No private keys."
    ui_pause
}

cert_ui_inspect() {
    cert_ui_pick "Certificate to inspect" pem || return
    local file="$UI_CHOICE"
    tui_screen "Inspect: $(ui_base "$file")"
    if ! pki_cert_info "$file"; then ui_err "Not a readable X.509 certificate."; ui_pause; return; fi
    local kind="End-entity certificate"
    [[ "${PKI_INFO[is_ca]}" == 1 ]] && kind="Certificate authority"
    [[ "${PKI_INFO[self_signed]}" == 1 ]] && kind+=" (self-signed)"
    local -a lines=(
        "$(ui_row "Subject" "${PKI_INFO[subject]}")"
        "$(ui_row "Issuer" "${PKI_INFO[issuer]}")"
        "$(ui_row "Type" "$kind")"
        "$(ui_row "Valid from" "${PKI_INFO[not_before]}")"
        "$(ui_row "Valid until" "${PKI_INFO[not_after]}  (${PKI_INFO[days_left]:-?} days)")"
        "$(ui_row "Public key" "$(_pki_key_short)")"
        "$(ui_row "Signature" "${PKI_INFO[sig_algo]}")"
    )
    [[ -n "${PKI_INFO[usage]}" ]] && lines+=("$(ui_row "Key usage" "${PKI_INFO[usage]}")")
    [[ -n "${PKI_INFO[eku]}" ]]   && lines+=("$(ui_row "Ext. usage" "${PKI_INFO[eku]}")")
    [[ -n "${PKI_INFO[san]}" ]]   && lines+=("$(ui_row "Alt. names" "${PKI_INFO[san]}")")
    lines+=("$(ui_row "Serial" "${PKI_INFO[serial]}")")
    ui_panel "Certificate" "${lines[@]}"
    echo
    printf '  %sSHA-256 fingerprint%s\n  %s\n' "$C_MUTED" "$RESET" "${PKI_INFO[fingerprint]}"
    echo
    local level msg
    while IFS='|' read -r level msg; do
        case "$level" in
            pass) ui_ok "$msg" ;; warn) ui_warn "$msg" ;; fail) ui_err "$msg" ;; *) ui_info "$msg" ;;
        esac
    done < <(pki_cert_findings)
    echo
    if ui_confirm "Show the full OpenSSL text dump?" n; then
        openssl x509 -in "$file" -noout -text 2>/dev/null | ui_pager
    fi
}

cert_ui_create_ca() {
    tui_screen "Create a root certificate authority" "A CA signs other certificates. Keep its key offline and passphrase-protected."
    ui_prompt "Short name (file name)" "my-root-ca" || return
    local name="$UI_REPLY"
    is_safe_name "$name" || { ui_err "Use letters, digits, dot, dash, underscore."; ui_pause; return; }
    ui_prompt "Common name" "$name" || return; local cn="$UI_REPLY"
    ui_prompt "Organization (optional)" "" || return; local org="$UI_REPLY"
    ui_prompt "Country code, 2 letters (optional)" "" || return; local country="$UI_REPLY"
    ui_prompt "Validity in days" "3650" || return; local days="$UI_REPLY"
    _cert_ui_pick_keytype || return
    local type="$UI_CHOICE"
    tui_screen "Create a root certificate authority"
    _cert_ui_key_passphrase "CA key" || return
    local secret="$UI_REPLY"
    ui_spinner_start "Generating ${PKI_KEY_LABEL[$type]} CA${G_ELLIPSIS}"
    pki_create_ca "$name" "$cn" "$org" "$country" "$type" "$days" "$secret"; local rc=$?
    ui_spinner_stop
    if (( rc != 0 )); then ui_err "$(ui_safe "$ENC_ERR")"; ui_pause; return; fi
    _cert_ui_show_created "Root CA created" "$CERT_DIR/$name.pem" "$CERT_DIR/$name.key" \
        "$(ui_row "Constraints" "CA:TRUE, pathlen:0 ${G_DOT} keyCertSign, cRLSign")"
    ui_pause
}

cert_ui_create_csr() {
    tui_screen "Create key + certificate signing request" "The CSR is sent to a CA (yours or an external one) to obtain a certificate."
    ui_prompt "Short name (file name)" "" || return
    local name="$UI_REPLY"
    is_safe_name "$name" || { ui_err "Use letters, digits, dot, dash, underscore."; ui_pause; return; }
    ui_prompt "Common name (person or host name)" "$name" || return; local cn="$UI_REPLY"
    ui_prompt "E-mail (optional)" "" || return; local email="$UI_REPLY"
    ui_prompt "Organization (optional)" "" || return; local org="$UI_REPLY"
    _cert_ui_pick_keytype || return
    local type="$UI_CHOICE"
    tui_screen "Create key + certificate signing request"
    _cert_ui_key_passphrase "private key" || return
    local secret="$UI_REPLY"
    ui_spinner_start "Generating ${PKI_KEY_LABEL[$type]} key and CSR${G_ELLIPSIS}"
    pki_create_csr "$name" "$cn" "$email" "$org" "$type" "$secret"; local rc=$?
    ui_spinner_stop
    if (( rc != 0 )); then ui_err "$(ui_safe "$ENC_ERR")"; ui_pause; return; fi
    _cert_ui_show_created "Key and CSR created" "" "$CERT_DIR/$name.key" "$(ui_row "CSR" "$(ui_pathfit "$CERT_DIR/$name.csr")")"
    echo
    ui_info "Next: sign it with your CA (menu 7) or send the .csr to an external CA."
    ui_pause
}

cert_ui_sign() {
    cert_ui_pick "CSR to sign" csr || return
    local csr="$UI_CHOICE"
    cert_ui_pick "CA certificate" pem || return
    local ca_cert="$UI_CHOICE" ca_key="${UI_CHOICE%.pem}.key"
    if [[ ! -f "$ca_key" ]]; then
        cert_ui_pick "CA private key" key || return
        ca_key="$UI_CHOICE"
    fi
    # Show what is about to be certified: the subject comes from the request,
    # not from its file name.
    tui_screen "Sign a certificate request"
    if ! pki_csr_info "$csr"; then ui_err "Not a readable certificate request."; ui_pause; return; fi
    ui_panel "Request" \
        "$(ui_row "File" "$(ui_base "$csr")")" \
        "$(ui_row "Subject" "$PKI_CSR_SUBJECT")" \
        "$(ui_row "Public key" "$PKI_CSR_KEY")" \
        "$(ui_row "Signed by" "$(ui_base "$ca_cert")")"
    echo
    ui_note "Extensions requested inside the CSR are ignored; the profile you choose decides them."
    ui_confirm "Issue a certificate for this subject?" n || return
    UI_SEL_HEADER="$(tui_header "Sign a CSR")"
    ui_select "Certificate profile" \
        "identity|Identity / file encryption|key encipherment + e-mail protection + client auth" \
        "server|TLS server|serverAuth, requires DNS names / IPs" \
        "client|TLS client|clientAuth only" || return
    local profile="$UI_CHOICE"
    tui_screen "Sign $(ui_base "$csr") with $(ui_base "$ca_cert")"
    local san=""
    if [[ "$profile" == "server" ]]; then
        ui_prompt "DNS names / IPs, comma-separated (e.g. example.com, www.example.com, 10.0.0.5)" "" || return
        san="$UI_REPLY"
    else
        ui_prompt "Alternative names, comma-separated e-mails/DNS (optional)" "" || return
        san="$UI_REPLY"
    fi
    local defdays=825; [[ "$profile" == "server" ]] && defdays=397
    ui_prompt "Validity in days" "$defdays" || return
    local days="$UI_REPLY" secret=""
    if crypto_key_is_encrypted "$ca_key"; then
        ui_prompt_secret "Passphrase for $(ui_base "$ca_key")" || return
        secret="$UI_REPLY"
    fi
    local out_name; out_name=$(basename "${csr%.csr}")
    if ! is_safe_name "$out_name"; then
        ui_prompt "Name for the new certificate in the store" "" || return
        out_name="$UI_REPLY"
        is_safe_name "$out_name" || { ui_err "Use letters, digits, dot, dash, underscore."; ui_pause; return; }
    fi
    local out="$CERT_DIR/${out_name}.pem"
    ui_spinner_start "Signing${G_ELLIPSIS}"
    pki_sign_csr "$csr" "$ca_cert" "$ca_key" "$profile" "$days" "$san" "$out" "$secret"; local rc=$?
    ui_spinner_stop
    if (( rc != 0 )); then ui_err "$(ui_safe "$ENC_ERR")"; ui_pause; return; fi
    local key=""; [[ -f "${out%.pem}.key" ]] && key="${out%.pem}.key"
    _cert_ui_show_created "Certificate issued" "$out" "$key" "$(ui_row "Issuer" "$(ui_base "$ca_cert")")"
    ui_pause
}

cert_ui_check() {
    cert_ui_pick "Certificate" pem || return
    local cert="$UI_CHOICE"
    tui_screen "Check: $(ui_base "$cert")"
    local key="${cert%.pem}.key"
    if [[ -f "$key" ]] && ui_confirm "Check against $(ui_base "$key")?" y; then :; else
        cert_ui_pick "Private key" key || return
        key="$UI_CHOICE"
        tui_screen "Check: $(ui_base "$cert")"
    fi
    local secret="" rc
    if crypto_key_is_encrypted "$key"; then
        ui_prompt_secret "Passphrase for $(ui_base "$key")" || return
        secret="$UI_REPLY"
    fi
    pki_match "$cert" "$key" "$secret"; rc=$?
    echo
    case $rc in
        0) ui_ok "${BOLD}Match${RESET} — $(ui_base "$key") is the private key of $(ui_base "$cert")." ;;
        1) ui_err "${BOLD}No match${RESET} — these two files do not belong together." ;;
        *) ui_err "$(ui_safe "$ENC_ERR")" ;;
    esac
    # Chain check against every CA in the store.
    local ca found=0
    for ca in "$CERT_DIR"/*.pem; do
        [[ -f "$ca" && "$ca" != "$cert" ]] || continue
        pki_is_ca "$ca" || continue
        if pki_verify_chain "$cert" "$ca"; then ui_ok "Chain verifies against CA $(ui_base "$ca")."; found=1; fi
    done
    if (( found == 0 )); then
        if pki_cert_info "$cert" && [[ "${PKI_INFO[self_signed]}" == 1 ]]; then ui_info "Self-signed certificate (no issuing CA)."
        else ui_info "No CA in the store issued this certificate."; fi
    fi
    ui_pause
}

cert_ui_export() {
    cert_ui_pick "Certificate to export" pem || return
    local cert="$UI_CHOICE" key="${UI_CHOICE%.pem}.key"
    if [[ ! -f "$key" ]]; then
        cert_ui_pick "Matching private key" key || return
        key="$UI_CHOICE"
    fi
    tui_screen "Export $(ui_base "$cert") to PKCS#12" "Bundles the certificate and its private key into one password-protected .p12 file."
    local key_secret=""
    if crypto_key_is_encrypted "$key"; then
        ui_prompt_secret "Passphrase for $(ui_base "$key")" || return
        key_secret="$UI_REPLY"
    fi
    tui_new_secret "Export password" || return
    local secret="$UI_REPLY"
    local out; out="$CERT_DIR/$(basename "${cert%.pem}").p12"
    ui_spinner_start "Packaging${G_ELLIPSIS}"
    pki_export_p12 "$cert" "$key" "$out" "$secret" "$key_secret"; local rc=$?
    ui_spinner_stop
    if (( rc != 0 )); then ui_err "$(ui_safe "$ENC_ERR")"; ui_pause; return; fi
    echo
    UI_PANEL_COLOR="$C_OK"
    ui_panel "$G_OK PKCS#12 bundle written" \
        "$(ui_row "File" "$(ui_pathfit "$out")  ${C_MUTED}($(human_size "$(get_file_size "$out")"))${RESET}")" \
        "$(ui_row "Protection" "AES-256-CBC, PBKDF2 ${PKI_P12_ITER} iterations, HMAC-SHA256")"
    (( PKI_P12_ITER < 100000 )) && ui_warn "This OpenSSL version cannot raise the bundle's work factor: use a long export password."
    ui_note "Import it in your browser, mail client or OS keychain; the export password is required."
    ui_pause
}
