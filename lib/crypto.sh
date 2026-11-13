#!/usr/bin/env bash
# ==============================================================================
# lib/crypto.sh — Encryption engine (no UI).
#
# Container format ENCRYPTOR/3 (see docs/FORMAT.md):
#
#   ENCRYPTOR/3\n
#   mode: password | recipient\n
#   cipher: <openssl cipher name>\n
#   mac: hmac-sha256\n
#   ...mode-specific fields...\n
#   ---\n
#   <body: standard `openssl enc` stream keyed with the derived body key>
#   <tag: 64 hex chars = HMAC-SHA256(mac_key, header || body)>
#
# Construction: encrypt-then-MAC. One master key per file (PBKDF2 from the
# password, or random and CMS-wrapped to X.509 recipients). Two independent
# subkeys are derived from it with HMAC-SHA256. The tag covers the header and
# the ciphertext and is verified BEFORE any plaintext is produced.
#
# Secrets never appear in argv and never touch the disk: passwords and keys
# are handed to openssl through anonymous pipes (`-pass fd:N`), and HMAC keys
# are fed through stdin by shell builtins.
#
# Engine functions return an exit code from lib/core.sh and describe failures
# in $ENC_ERR; they never prompt and never print to the terminal.
# ==============================================================================

readonly ENC_MAGIC="ENCRYPTOR/3"
readonly ENC_TAG_LEN=64                 # hex characters
readonly ENC_DEFAULT_CIPHER="aes-256-ctr"
readonly ENC_BODY_ITER=1                # body key is already uniformly random
readonly ENC_ITER_MIN=100000            # lowest accepted for new files
readonly ENC_ITER_READ_MIN=1000         # lowest accepted when reading
readonly ENC_ITER_MAX=10000000          # cost cap: also applied to (unauthenticated) headers before any work
readonly ENC_PASS_MAX=1000              # openssl reads at most ~1 KiB per pass line
readonly ENC_LEGACY_ITER_V21=600000
readonly ENC_LEGACY_ITER_V20=100000
readonly CRYPTO_KAT_PBKDF2="b62df00c273cfbe46c0e32299cc54f143709d1b0b28b6f674a2fb0d68f8a16fa"

# OWASP Password Storage Cheat Sheet: PBKDF2-HMAC-SHA256 >= 600,000.
ENC_DEFAULT_ITER=600000
if [[ "${ENCRYPTOR_PBKDF2_ITER:-}" =~ ^[0-9]{1,9}$ ]]; then
    ENC_DEFAULT_ITER=$(( 10#$ENCRYPTOR_PBKDF2_ITER ))      # base 10 even with leading zeros
fi

# Password KDF selection: scrypt (memory-hard) | pbkdf2 (NIST-approved) | auto.
# "auto" uses scrypt when this OpenSSL build supports it, otherwise PBKDF2.
ENC_DEFAULT_KDF="auto"
case "${ENCRYPTOR_KDF:-}" in scrypt|pbkdf2|auto) ENC_DEFAULT_KDF="$ENCRYPTOR_KDF" ;; esac

# scrypt cost: N=2^14, r=8, p=5 — one of the equivalent configurations in the
# OWASP Password Storage Cheat Sheet. 16 MiB of memory per guess; it is also
# the largest N the OpenSSL command line accepts (its PKCS#8 code caps scrypt
# memory at 32 MiB), so p carries the remaining work.
readonly ENC_SCRYPT_N=16384 ENC_SCRYPT_R=8 ENC_SCRYPT_P=5
# Bounds enforced on parameters read from a (not yet authenticated) file
# before any work is done: at most 32 MiB of memory (128*N*r bytes) and about
# six times the default amount of computation (N*r*p).
readonly ENC_SCRYPT_MAX_NR=262144 ENC_SCRYPT_MAX_NRP=4194304
# DER PrivateKeyInfo header of an X25519 key (RFC 8410); the 32 bytes that
# follow are the master key. Used only as a standard container for sealing.
readonly ENC_SEAL_PREFIX="302e020100300506032b656e04220420"
readonly CRYPTO_KAT_SCRYPT_SEALED="MIGTME8GCSqGSIb3DQEFDTBCMCEGCSsGAQQB2kcECzAUBAjoyR3s99viigICBAACAQgCAQEwHQYJYIZIAWUDBAEqBBBU8Qfl5ju7WmkxHqLyteSCBED9l6fp28DBgaHrLoEzeJJz1XC99I0gy+an7JY4mtltBIYICBnVYDNCBORl3imPjhDqGgClYcVcljagCdu9+HNb"
readonly CRYPTO_KAT_SCRYPT_MASTER="000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f"

# Cipher registry. Every cipher is combined with HMAC-SHA256 (encrypt-then-MAC),
# so all of them yield authenticated encryption inside the v3 container.
readonly -a ENC_CIPHER_IDS=(aes-256-ctr chacha20 aes-256-cbc camellia-256-cbc aria-256-cbc)
declare -A ENC_CIPHER_LABEL=(
    [aes-256-ctr]="AES-256-CTR + HMAC-SHA256"
    [chacha20]="ChaCha20 + HMAC-SHA256"
    [aes-256-cbc]="AES-256-CBC + HMAC-SHA256"
    [camellia-256-cbc]="Camellia-256-CBC + HMAC-SHA256"
    [aria-256-cbc]="ARIA-256-CBC + HMAC-SHA256"
)
declare -A ENC_CIPHER_DESC=(
    [aes-256-ctr]="Recommended. NIST-approved primitives, hardware accelerated (AES-NI)."
    [chacha20]="Fast constant-time stream cipher; best on CPUs without AES acceleration."
    [aes-256-cbc]="Classic block mode, widest compatibility with older OpenSSL builds."
    [camellia-256-cbc]="Japanese standard (CRYPTREC, ISO/IEC 18033-3)."
    [aria-256-cbc]="Korean standard (KS X 1213, ISO/IEC 18033-3)."
)

# --- Engine inputs (set by the caller before invoking an operation) ---------
ENC_SECRET=""                # password (password mode)
declare -a ENC_RECIPIENTS=() # recipient certificate paths (recipient mode)
ENC_KEY_FILE=""              # private key for recipient-mode decryption
ENC_CERT_FILE=""             # optional matching certificate (speeds up lookup)
ENC_KEY_SECRET=""            # passphrase of an encrypted private key (optional)
ENC_LEGACY_ALGO="aes-256-cbc"
ENC_LEGACY_ITER=$ENC_LEGACY_ITER_V21
ENC_ALLOW_LEGACY=0           # 1 = the caller explicitly accepted an unauthenticated 2.x file

# --- Engine outputs ---------------------------------------------------------
declare -A ENC_META=()       # parsed container metadata (crypto_inspect)
declare -a ENC_META_RCPT=()  # recipient certificate fingerprints
ENC_RESULT_BYTES_IN=0
ENC_RESULT_BYTES_OUT=0
ENC_RESULT_KDF=""            # KDF actually used by the last password-mode encryption

crypto_reset_inputs() {
    ENC_SECRET=""; ENC_RECIPIENTS=(); ENC_KEY_FILE=""; ENC_CERT_FILE=""
    ENC_KEY_SECRET=""; ENC_LEGACY_ALGO="aes-256-cbc"; ENC_LEGACY_ITER=$ENC_LEGACY_ITER_V21
    ENC_ALLOW_LEGACY=0
}

# Optional progress hook: the TUI defines crypto_on_phase to update its display.
_crypto_phase() {
    declare -F crypto_on_phase >/dev/null 2>&1 && crypto_on_phase "$@"
    return 0
}

crypto_is_cipher() {
    local c
    for c in "${ENC_CIPHER_IDS[@]}"; do [[ "$c" == "$1" ]] && return 0; done
    return 1
}

# Does the installed OpenSSL implement this cipher? (cached)
declare -A _CRYPTO_CIPHER_OK=()
crypto_cipher_available() {
    local c="$1"
    crypto_is_cipher "$c" || return 1
    if [[ -z "${_CRYPTO_CIPHER_OK[$c]:-}" ]]; then
        # "probe" is a constant, not a secret.
        if openssl enc "-$c" -pbkdf2 -iter 1 -md sha256 -pass pass:probe </dev/null >/dev/null 2>&1; then
            _CRYPTO_CIPHER_OK[$c]=yes
        else
            _CRYPTO_CIPHER_OK[$c]=no
        fi
    fi
    [[ "${_CRYPTO_CIPHER_OK[$c]}" == yes ]]
}

# Path of the in-progress output for a given final output (same directory, so
# the final rename is atomic).
crypto_part_path() {
    if [[ "$1" == "-" ]]; then
        # TEMP_DIR is created by the caller: this function runs in a command
        # substitution, where creating it would leak an untracked directory.
        printf '%s' "$TEMP_DIR/stdout.part"
    else
        printf '%s' "${1}.encryptor-part.$$.${RANDOM}${RANDOM}"
    fi
}

# Create the in-progress file exclusively (O_EXCL via noclobber): refuses to
# follow a pre-existing file or symlink planted under that name in a shared
# directory. Registers it for removal on abnormal exit.
_crypto_part_create() {
    local part="$1"
    if ! ( set -o noclobber; : > "$part" ) 2>/dev/null; then return 1; fi
    core_cleanup_add "$part"
}

# --- Primitives -------------------------------------------------------------

_crypto_rand_hex() { openssl rand -hex "$1" 2>/dev/null; }

# HMAC-SHA256 with a hex key; message on stdin; prints lowercase hex.
# Implemented from the RFC 2104 definition on top of `openssl dgst` so the key
# is delivered by a shell builtin through a pipe — never as a process argument.
# Interoperable: equals `openssl dgst -sha256 -mac HMAC -macopt hexkey:KEY`.
_crypto_hmac() {
    local key="$1" i b ipad="" opad="" inner outer inner_fmt=""
    # Keys are 1–64 bytes of lowercase hex. (RFC 2104 hashes longer keys first;
    # this tool never uses one, so they are refused rather than mishandled.)
    [[ "$key" =~ ^([0-9a-f]{2}){1,64}$ ]] || return 1
    for (( i = 0; i < 64; i++ )); do
        if (( i * 2 < ${#key} )); then b=$(( 16#${key:i*2:2} )); else b=0; fi
        printf -v ipad '%s\\x%02x' "$ipad" $(( b ^ 0x36 ))
        printf -v opad '%s\\x%02x' "$opad" $(( b ^ 0x5c ))
    done
    # shellcheck disable=SC2059  # the format strings contain only \xHH escapes
    inner=$( { printf "$ipad"; cat; } | openssl dgst -sha256 -r 2>/dev/null ) || return 1
    inner=${inner%% *}
    [[ ${#inner} -eq 64 ]] || return 1
    for (( i = 0; i < 64; i += 2 )); do inner_fmt+="\\x${inner:i:2}"; done
    # shellcheck disable=SC2059
    outer=$( { printf "$opad"; printf "$inner_fmt"; } | openssl dgst -sha256 -r 2>/dev/null ) || return 1
    outer=${outer%% *}
    [[ ${#outer} -eq 64 ]] || return 1
    printf '%s' "$outer"
}

# A secret is handed to openssl as one line on a pipe, and openssl reads at
# most about 1 KiB of it. Anything that would be silently cut — an embedded
# line break, or more than ENC_PASS_MAX *bytes* — is refused instead.
# Sets ENC_ERR and returns non-zero when the secret is unusable.
crypto_check_secret() {
    local secret="$1" what="${2:-Password}" LC_ALL=C
    if [[ -z "$secret" ]]; then ENC_ERR="$what is empty."; return 1; fi
    if [[ "$secret" == *$'\n'* || "$secret" == *$'\r'* ]]; then
        ENC_ERR="$what contains a line break; only single-line secrets are supported."; return 1
    fi
    if (( ${#secret} > ENC_PASS_MAX )); then
        ENC_ERR="$what is too long (limit: ${ENC_PASS_MAX} bytes)."; return 1
    fi
    return 0
}

# Subkey derivation: HMAC-SHA256(master, label). Labels are fixed ASCII strings.
_crypto_subkey() { printf '%s' "$2" | _crypto_hmac "$1"; }

# PBKDF2-HMAC-SHA256(password, salt, iter) → 32-byte master key (hex).
# Uses `openssl enc -P`, which prints the derived key without encrypting; the
# password travels over an anonymous pipe on fd 3.
_crypto_pbkdf2() {
    local password="$1" salt="$2" iter="$3" out key
    out=$(openssl enc -aes-256-ctr -pbkdf2 -iter "$iter" -md sha256 -S "$salt" -P \
            -pass fd:3 3< <(printf '%s\n' "$password") </dev/null 2>/dev/null) || return 1
    key=$(sed -n 's/^key[[:space:]]*=[[:space:]]*//p' <<<"$out")
    key=${key,,}
    [[ "$key" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s' "$key"
}

# --- scrypt-sealed master key -------------------------------------------------
# The OpenSSL command line can run scrypt with the password supplied through a
# pipe in exactly one place: PKCS#8 private-key encryption (PBES2 with scrypt,
# RFC 7914 / RFC 8018). We therefore store a random 256-bit master key inside
# a standard X25519 PrivateKeyInfo and let `openssl pkcs8` seal it with
# scrypt + AES-256-CBC. No X25519 operation is ever performed; the structure
# is only a well-specified envelope that stock OpenSSL can open.

# Hex string → printf format of \xHH escapes (for binary output via a builtin).
_crypto_hex_fmt() {
    local hex="$1" i out=""
    for (( i = 0; i < ${#hex}; i += 2 )); do out+="\\x${hex:i:2}"; done
    printf '%s' "$out"
}

# Does this OpenSSL build support scrypt-sealed PKCS#8 with X25519? (cached)
_CRYPTO_SCRYPT_OK=""
crypto_scrypt_available() {
    if [[ -z "$_CRYPTO_SCRYPT_OK" ]]; then
        local fmt n
        fmt=$(_crypto_hex_fmt "${ENC_SEAL_PREFIX}${CRYPTO_KAT_SCRYPT_MASTER}")
        # "probe" is a constant, not a secret.
        # shellcheck disable=SC2059
        n=$(printf "$fmt" | openssl pkcs8 -topk8 -inform DER -outform DER -scrypt \
                -scrypt_N 16 -scrypt_r 1 -scrypt_p 1 -passout pass:probe 2>/dev/null | wc -c)
        if [[ "${n//[[:space:]]/}" -gt 100 ]]; then _CRYPTO_SCRYPT_OK=yes; else _CRYPTO_SCRYPT_OK=no; fi
    fi
    [[ "$_CRYPTO_SCRYPT_OK" == yes ]]
}

# Resolve a requested KDF name (scrypt | pbkdf2 | auto) to the one to use.
crypto_resolve_kdf() {
    case "${1:-auto}" in
        pbkdf2) printf 'pbkdf2' ;;
        scrypt) printf 'scrypt' ;;
        *)      if crypto_scrypt_available; then printf 'scrypt'; else printf 'pbkdf2'; fi ;;
    esac
}

# Seal a master key under a password → base64 PKCS#8 EncryptedPrivateKeyInfo.
_crypto_seal_master() {
    local master="$1" password="$2" fmt b64
    fmt=$(_crypto_hex_fmt "${ENC_SEAL_PREFIX}${master}")
    # shellcheck disable=SC2059
    b64=$(printf "$fmt" | openssl pkcs8 -topk8 -inform DER -outform DER -scrypt \
            -scrypt_N "$ENC_SCRYPT_N" -scrypt_r "$ENC_SCRYPT_R" -scrypt_p "$ENC_SCRYPT_P" -v2 aes-256-cbc \
            -passout fd:3 3< <(printf '%s\n' "$password") 2>/dev/null | openssl base64 -A 2>/dev/null)
    [[ ${#b64} -ge 150 ]] || return 1
    printf '%s' "$b64"
}

# Read and bound-check the scrypt parameters inside a sealed blob → "N:r:p".
# Runs before any key derivation so that a crafted file cannot request an
# arbitrary amount of CPU or memory.
_crypto_sealed_params() {
    local b64="$1" dump n r p
    (( ${#b64} <= 2048 )) || return 1
    dump=$(printf '%s' "$b64" | openssl base64 -d -A 2>/dev/null | openssl asn1parse -inform DER 2>/dev/null) || return 1
    # The three INTEGERs that follow the scrypt algorithm identifier and its salt.
    read -r n r p < <(awk '
        /OBJECT/ && (/:scrypt/ || /1\.3\.6\.1\.4\.1\.11591\.4\.11/) { seen = 1; next }
        seen && /INTEGER/ && k < 3 { sub(/.*:/, ""); vals[++k] = $0; if (k == 3) print vals[1], vals[2], vals[3] }
    ' <<<"$dump")
    [[ "$n" =~ ^[0-9A-Fa-f]{1,8}$ && "$r" =~ ^[0-9A-Fa-f]{1,8}$ && "$p" =~ ^[0-9A-Fa-f]{1,8}$ ]] || return 1
    n=$(( 16#$n )); r=$(( 16#$r )); p=$(( 16#$p ))
    (( n >= 2 && r >= 1 && p >= 1 && (n & (n - 1)) == 0 )) || return 1
    (( n * r <= ENC_SCRYPT_MAX_NR && n * r * p <= ENC_SCRYPT_MAX_NRP )) || return 1
    grep -q ':aes-256-cbc' <<<"$dump" || return 1
    printf '%d:%d:%d' "$n" "$r" "$p"
}

# Open a sealed blob with the password → master key (hex).
# Plain `pkcs8 -inform DER` (no -topk8): OpenSSL 1.1.1 can only read an
# encrypted DER key this way, and 3.x/4.x produce the same 48 bytes.
_crypto_unseal_master() {
    local b64="$1" password="$2" der
    der=$(printf '%s' "$b64" | openssl base64 -d -A 2>/dev/null \
          | openssl pkcs8 -inform DER -outform DER -passin fd:3 3< <(printf '%s\n' "$password") 2>/dev/null \
          | od -An -v -tx1 | tr -d ' \n')
    [[ ${#der} -eq 96 && "${der:0:32}" == "$ENC_SEAL_PREFIX" ]] || return 1
    printf '%s' "${der:32}"
}

# Human-readable description of the password KDF recorded in ENC_META.
crypto_meta_kdf_label() {
    if [[ "${ENC_META[kdf]:-}" == "scrypt" ]]; then
        local n r p
        IFS=: read -r n r p <<<"${ENC_META[scrypt]:-?:?:?}"
        printf 'scrypt (N=%s, r=%s, p=%s; memory-hard)' "$n" "$r" "$p"
    else
        printf 'PBKDF2-HMAC-SHA256, %s iterations' "${ENC_META[iter]:-?}"
    fi
}

# Description of the KDF a new password-protected file would get.
crypto_new_kdf_label() {
    if [[ "$(crypto_resolve_kdf "${1:-$ENC_DEFAULT_KDF}")" == "scrypt" ]]; then
        printf 'scrypt (N=%d, r=%d, p=%d; memory-hard)' "$ENC_SCRYPT_N" "$ENC_SCRYPT_R" "$ENC_SCRYPT_P"
    else
        printf 'PBKDF2-HMAC-SHA256, %s iterations' "$ENC_DEFAULT_ITER"
    fi
}

# Certificate helpers (public information only).
crypto_cert_fingerprint() {
    local fp
    fp=$(openssl x509 -in "$1" -noout -fingerprint -sha256 2>/dev/null) || return 1
    fp=${fp#*=}; fp=${fp//:/}
    printf '%s' "${fp,,}"
}
# Key type and size, taken from the public key itself (never from text that a
# certificate subject could imitate). Prints "rsa 3072", "ec 256" or "other 0".
crypto_cert_key_info() {
    local text bits
    text=$(openssl x509 -in "$1" -noout -pubkey 2>/dev/null | openssl pkey -pubin -noout -text 2>/dev/null) || return 1
    bits=$(sed -n '1s/.*(\([0-9]*\) bit.*/\1/p' <<<"$text")
    [[ "$bits" =~ ^[0-9]+$ ]] || bits=0
    if grep -q '^Modulus' <<<"$text"; then printf 'rsa %s' "$bits"
    elif grep -Eq '^(ASN1 OID|NIST CURVE)' <<<"$text"; then printf 'ec %s' "$bits"
    else printf 'other %s' "$bits"; fi
}
crypto_cert_is_rsa() { [[ "$(crypto_cert_key_info "$1")" == rsa* ]]; }

# Is this certificate usable as an encryption recipient right now?
# Sets ENC_ERR and returns non-zero when it is not.
crypto_check_recipient() {
    local cert="$1" info type bits ku start now
    if ! openssl x509 -in "$cert" -noout >/dev/null 2>&1; then
        ENC_ERR="Not a readable X.509 certificate: $cert"; return "$EX_NOINPUT"
    fi
    if ! openssl x509 -in "$cert" -noout -checkend 0 >/dev/null 2>&1; then
        ENC_ERR="Recipient certificate has expired: $cert"; return "$EX_FAIL"
    fi
    start=$(openssl x509 -in "$cert" -noout -startdate 2>/dev/null); start=$(core_date_epoch "${start#*=}")
    now=$(date -u +%s)
    if [[ -n "$start" ]] && (( start > now + 300 )); then
        ENC_ERR="Recipient certificate is not valid yet: $cert"; return "$EX_FAIL"
    fi
    info=$(crypto_cert_key_info "$cert") || { ENC_ERR="Cannot read the public key of $cert"; return "$EX_FAIL"; }
    type=${info% *}; bits=${info#* }
    case "$type" in
        rsa) if (( bits < 2048 )); then ENC_ERR="Recipient RSA key is only ${bits} bits (minimum 2048): $cert"; return "$EX_FAIL"; fi ;;
        ec)  if (( bits < 224 ));  then ENC_ERR="Recipient EC key is only ${bits} bits (minimum 224): $cert"; return "$EX_FAIL"; fi ;;
        *)   ENC_ERR="Unsupported recipient key type (RSA and EC certificates are supported): $cert"; return "$EX_FAIL" ;;
    esac
    # keyUsage, when present, must permit encrypting a key to this certificate.
    ku=$(openssl x509 -in "$cert" -noout -ext keyUsage 2>/dev/null | tail -n +2)
    if [[ -n "$ku" ]]; then
        if [[ "$type" == "rsa" && "$ku" != *"Key Encipherment"* ]] ||
           [[ "$type" == "ec"  && "$ku" != *"Key Agreement"* ]]; then
            ENC_ERR="The certificate's key usage ($(trim "$ku")) does not permit encryption: $cert"; return "$EX_FAIL"
        fi
    fi
    return 0
}

# Wrap the master key for every recipient with CMS EnvelopedData → base64 line.
# RSA recipients use RSA-OAEP(SHA-256); EC recipients use ECDH key agreement.
# The wrapped blob's integrity is covered by the container HMAC.
_crypto_wrap_master() {
    local master="$1"; shift
    local -a args=()
    local cert
    for cert in "$@"; do
        args+=(-recip "$cert")
        if crypto_cert_is_rsa "$cert"; then
            args+=(-keyopt rsa_padding_mode:oaep -keyopt rsa_oaep_md:sha256)
        fi
    done
    local b64
    # No fallback to PKCS#1 v1.5 key transport: if OAEP is unavailable the
    # operation fails rather than silently producing a weaker file.
    b64=$(printf '%s' "$master" | openssl cms -encrypt -binary -aes-256-cbc -outform DER "${args[@]}" 2>/dev/null | openssl base64 -A 2>/dev/null)
    [[ -n "$b64" ]] || return 1
    printf '%s' "$b64"
}

# Unwrap the master key with the recipient's private key. On failure the
# openssl diagnostic is left in $_CRYPTO_UNWRAP_ERR.
_CRYPTO_UNWRAP_ERR=""
_crypto_unwrap_master() {
    local wrapped="$1" key_file="$2" cert_file="$3" key_secret="$4"
    local -a args=(-decrypt -binary -inform DER -inkey "$key_file")
    [[ -n "$cert_file" ]] && args+=(-recip "$cert_file")
    local errf="$TEMP_DIR/unwrap.err" master   # TEMP_DIR prepared by the caller
    if [[ -n "$key_secret" ]]; then
        master=$(printf '%s' "$wrapped" | openssl base64 -d -A 2>/dev/null \
                 | openssl cms "${args[@]}" -passin fd:4 4< <(printf '%s\n' "$key_secret") 2>"$errf" \
                 | head -c 64 | tr -cd '0-9a-f')
    else
        master=$(printf '%s' "$wrapped" | openssl base64 -d -A 2>/dev/null \
                 | openssl cms "${args[@]}" 2>"$errf" | head -c 64 | tr -cd '0-9a-f')
    fi
    _CRYPTO_UNWRAP_ERR=$(head -n 3 "$errf" 2>/dev/null); rm -f "$errf"
    [[ "$master" =~ ^[0-9a-f]{64}$ ]] || return 1
    printf '%s' "$master"
}

# Is a PEM private key passphrase-protected?
# Structural test, not a text search: the key is "encrypted" only if OpenSSL
# cannot load it with an empty passphrase AND it carries an encrypted-key
# header on its first lines (a comment elsewhere in the file cannot fake it).
crypto_key_is_encrypted() {
    local f="$1"
    [[ -f "$f" && -r "$f" ]] || return 1
    if openssl pkey -in "$f" -noout -passin pass: </dev/null >/dev/null 2>&1; then return 1; fi
    local head3; head3=$(head -n 3 -- "$f" 2>/dev/null)
    grep -qE -e '^-----BEGIN ENCRYPTED PRIVATE KEY-----' -e '^Proc-Type: 4,ENCRYPTED' <<<"$head3"
}

# --- Container inspection ---------------------------------------------------
# crypto_inspect FILE → fills ENC_META / ENC_META_RCPT.
#   ENC_META[format] = v3 | legacy-enc | legacy-smime | unsupported | unknown
crypto_inspect() {
    local file="$1"
    ENC_META=(); ENC_META_RCPT=(); ENC_ERR=""
    if [[ ! -f "$file" || ! -r "$file" ]]; then
        ENC_ERR="File not found or not readable: $file"; return "$EX_NOINPUT"
    fi
    ENC_META[size]=$(get_file_size "$file")
    local magic; magic=$(file_magic_hex "$file" 16)
    case "$magic" in
        454e43525950544f522f330a*)          ENC_META[format]="v3" ;;
        454e43525950544f522f*)              ENC_META[format]="unsupported"
            ENC_ERR="This file was written by a newer Encryptor format version. Please upgrade."
            return "$EX_UNSUPPORTED" ;;
        53616c7465645f5f*)                  ENC_META[format]="legacy-enc"; return 0 ;;
        2d2d2d2d2d424547494e20504b435337*)  ENC_META[format]="legacy-smime"; return 0 ;;
        *)                                  ENC_META[format]="unknown"
            ENC_ERR="Not an Encryptor file (unrecognised format): $file"
            return "$EX_UNSUPPORTED" ;;
    esac

    # Parse the text header. Only the first 256 KiB are examined; every line
    # must match a strict grammar, so binary garbage cannot be interpreted.
    local LC_ALL=C line n=0 hdr_len=0 done_hdr=0 key val
    while IFS= read -r line; do
        (( n++ ))
        hdr_len=$(( hdr_len + ${#line} + 1 ))
        if (( n == 1 )); then
            [[ "$line" == "$ENC_MAGIC" ]] || break
            continue
        fi
        if [[ "$line" == "---" ]]; then done_hdr=1; break; fi
        (( n > 64 )) && break
        if (( ${#line} <= 131072 )) && [[ "$line" =~ ^([a-z][a-z0-9-]{0,31}):\ ([A-Za-z0-9+/=._:-]+)$ ]]; then
            key="${BASH_REMATCH[1]}"; val="${BASH_REMATCH[2]}"
            if [[ "$key" == "recipient-fp" ]]; then
                ENC_META_RCPT+=("$val")
            else
                ENC_META[$key]="$val"
            fi
        else
            break
        fi
    done < <(head -c 262144 -- "$file" | tr -d '\000')

    if (( done_hdr == 0 )); then
        ENC_ERR="Corrupt container header: $file"; return "$EX_UNSUPPORTED"
    fi
    ENC_META[hdr_len]=$hdr_len

    # Semantic validation.
    local cipher="${ENC_META[cipher]:-}" mode="${ENC_META[mode]:-}"
    if ! crypto_is_cipher "$cipher"; then
        ENC_ERR="Unsupported cipher in header: ${cipher:-<missing>}"; return "$EX_UNSUPPORTED"
    fi
    if [[ "${ENC_META[mac]:-}" != "hmac-sha256" ]]; then
        ENC_ERR="Unsupported MAC in header: ${ENC_META[mac]:-<missing>}"; return "$EX_UNSUPPORTED"
    fi
    case "$mode" in
        password)
            case "${ENC_META[kdf]:-}" in
                pbkdf2-hmac-sha256)
                    if [[ ! "${ENC_META[iter]:-}" =~ ^[1-9][0-9]{0,8}$ ]] ||
                       (( ENC_META[iter] < ENC_ITER_READ_MIN || ENC_META[iter] > ENC_ITER_MAX )); then
                        ENC_ERR="Invalid KDF iteration count in header."; return "$EX_UNSUPPORTED"
                    fi
                    if [[ ! "${ENC_META[salt]:-}" =~ ^[0-9a-f]{16}$ ]]; then
                        ENC_ERR="Invalid salt in header."; return "$EX_UNSUPPORTED"
                    fi ;;
                scrypt)
                    # The authoritative parameters are the ones inside the sealed
                    # blob; they are extracted and bounded here, before any work.
                    local sp
                    sp=$(_crypto_sealed_params "${ENC_META[sealed]:-}") || {
                        ENC_ERR="Invalid or out-of-range scrypt key envelope in header."; return "$EX_UNSUPPORTED"
                    }
                    ENC_META[scrypt]="$sp" ;;
                *)
                    ENC_ERR="Unsupported KDF in header: ${ENC_META[kdf]:-<missing>}"; return "$EX_UNSUPPORTED" ;;
            esac
            ;;
        recipient)
            if [[ "${ENC_META[keywrap]:-}" != "cms" || -z "${ENC_META[wrapped]:-}" ]]; then
                ENC_ERR="Invalid recipient key-wrap data in header."; return "$EX_UNSUPPORTED"
            fi
            ;;
        *)
            ENC_ERR="Unsupported mode in header: ${mode:-<missing>}"; return "$EX_UNSUPPORTED" ;;
    esac
    # Smallest valid body is the 16-byte `openssl enc` salt header.
    if (( ENC_META[size] < hdr_len + 16 + ENC_TAG_LEN )); then
        ENC_ERR="Container is truncated: $file"; return "$EX_UNSUPPORTED"
    fi
    ENC_META[body_len]=$(( ENC_META[size] - hdr_len - ENC_TAG_LEN ))
    return 0
}

# --- Encryption -------------------------------------------------------------
# crypto_encrypt IN OUT [CIPHER] [ITER]
#   IN  : path, or "-" for stdin        OUT : path, or "-" for stdout
#   Mode: recipient if ENC_RECIPIENTS is non-empty, otherwise password (ENC_SECRET).
crypto_encrypt() {
    local in="$1" out="$2" cipher="${3:-$ENC_DEFAULT_CIPHER}" iter="${4:-$ENC_DEFAULT_ITER}" kdf_req="${5:-$ENC_DEFAULT_KDF}"
    ENC_ERR=""; ENC_RESULT_BYTES_IN=0; ENC_RESULT_BYTES_OUT=0
    core_tmpdir

    if ! crypto_is_cipher "$cipher"; then
        ENC_ERR="Unknown algorithm '$cipher'. Valid: ${ENC_CIPHER_IDS[*]}"; return "$EX_USAGE"
    fi
    if ! crypto_cipher_available "$cipher"; then
        ENC_ERR="Algorithm '$cipher' is not available in this OpenSSL build."; return "$EX_UNSUPPORTED"
    fi
    if [[ "$in" != "-" ]]; then
        if [[ ! -f "$in" || ! -r "$in" ]]; then
            ENC_ERR="File not found or not readable: $in"; return "$EX_NOINPUT"
        fi
        ENC_RESULT_BYTES_IN=$(get_file_size "$in")
    fi
    if [[ "$out" != "-" ]]; then
        if [[ -d "$out" ]]; then ENC_ERR="Output is a directory: $out"; return "$EX_CANTCREAT"; fi
        if [[ "$in" != "-" ]] && same_file "$in" "$out"; then
            ENC_ERR="Input and output are the same file: $in"; return "$EX_USAGE"
        fi
    fi

    local mode master header="" salt wrapped cert fp
    if (( ${#ENC_RECIPIENTS[@]} > 0 )); then
        mode="recipient"
        for cert in "${ENC_RECIPIENTS[@]}"; do
            crypto_check_recipient "$cert" || return $?
        done
        _crypto_phase keygen
        master=$(_crypto_rand_hex 32)
        if [[ ! "$master" =~ ^[0-9a-f]{64}$ ]]; then
            ENC_ERR="Could not obtain random bytes from OpenSSL."; return "$EX_FAIL"
        fi
        wrapped=$(_crypto_wrap_master "$master" "${ENC_RECIPIENTS[@]}") || {
            ENC_ERR="Could not encrypt the file key for the recipient certificate(s) (CMS key wrapping with RSA-OAEP / ECDH failed in this OpenSSL build)."
            return "$EX_FAIL"
        }
        header="${ENC_MAGIC}"$'\n'"mode: recipient"$'\n'"cipher: ${cipher}"$'\n'"mac: hmac-sha256"$'\n'"keywrap: cms"$'\n'
        for cert in "${ENC_RECIPIENTS[@]}"; do
            fp=$(crypto_cert_fingerprint "$cert") && header+="recipient-fp: ${fp}"$'\n'
        done
        header+="wrapped: ${wrapped}"$'\n'"---"$'\n'
    else
        mode="password"
        crypto_check_secret "$ENC_SECRET" "Password" || return "$EX_USAGE"
        local kdf sealed
        case "$kdf_req" in scrypt|pbkdf2|auto) ;; *) ENC_ERR="Unknown KDF '$kdf_req'. Valid: scrypt pbkdf2 auto"; return "$EX_USAGE" ;; esac
        kdf=$(crypto_resolve_kdf "$kdf_req")
        if [[ "$kdf" == "scrypt" ]]; then
            if ! crypto_scrypt_available; then
                ENC_ERR="scrypt is not available in this OpenSSL build; use --kdf pbkdf2."; return "$EX_UNSUPPORTED"
            fi
            master=$(_crypto_rand_hex 32)
            if [[ ! "$master" =~ ^[0-9a-f]{64}$ ]]; then
                ENC_ERR="Could not obtain random bytes from OpenSSL."; return "$EX_FAIL"
            fi
            _crypto_phase kdf "scrypt N=${ENC_SCRYPT_N} r=${ENC_SCRYPT_R} p=${ENC_SCRYPT_P}"
            sealed=$(_crypto_seal_master "$master" "$ENC_SECRET") || {
                ENC_ERR="Could not seal the file key with scrypt."; return "$EX_FAIL"
            }
            header="${ENC_MAGIC}"$'\n'"mode: password"$'\n'"cipher: ${cipher}"$'\n'"mac: hmac-sha256"$'\n'"kdf: scrypt"$'\n'"sealed: ${sealed}"$'\n'"---"$'\n'
        else
            if [[ ! "$iter" =~ ^[0-9]{1,9}$ ]] || (( 10#$iter < ENC_ITER_MIN || 10#$iter > ENC_ITER_MAX )); then
                ENC_ERR="PBKDF2 iteration count must be between ${ENC_ITER_MIN} and ${ENC_ITER_MAX}."; return "$EX_USAGE"
            fi
            iter=$(( 10#$iter ))
            salt=$(_crypto_rand_hex 8)
            if [[ ! "$salt" =~ ^[0-9a-f]{16}$ ]]; then
                ENC_ERR="Could not obtain random bytes from OpenSSL."; return "$EX_FAIL"
            fi
            _crypto_phase kdf "PBKDF2-HMAC-SHA256, ${iter} iterations"
            master=$(_crypto_pbkdf2 "$ENC_SECRET" "$salt" "$iter") || {
                ENC_ERR="Key derivation failed (PBKDF2 is not supported by this OpenSSL build?)."; return "$EX_FAIL"
            }
            header="${ENC_MAGIC}"$'\n'"mode: password"$'\n'"cipher: ${cipher}"$'\n'"mac: hmac-sha256"$'\n'"kdf: pbkdf2-hmac-sha256"$'\n'"iter: ${iter}"$'\n'"salt: ${salt}"$'\n'"---"$'\n'
        fi
        ENC_RESULT_KDF="$kdf"
    fi

    local enc_key mac_key
    enc_key=$(_crypto_subkey "$master" "encryptor/3 body-encryption") &&
    mac_key=$(_crypto_subkey "$master" "encryptor/3 authentication") || {
        ENC_ERR="Subkey derivation failed (SHA-256 unavailable?)."; return "$EX_FAIL"
    }
    master=""

    local part; part=$(crypto_part_path "$out")
    local errf="$TEMP_DIR/enc.err" rc=0
    if ! _crypto_part_create "$part" || ! printf '%s' "$header" 2>/dev/null >> "$part"; then
        rm -f -- "$part" 2>/dev/null; core_cleanup_forget "$part"
        ENC_ERR="Cannot write output: $out"; return "$EX_CANTCREAT"
    fi

    _crypto_phase encrypt "$part" "$ENC_RESULT_BYTES_IN"
    if [[ "$in" == "-" ]]; then
        openssl enc "-$cipher" -pbkdf2 -iter "$ENC_BODY_ITER" -md sha256 -salt \
            -pass fd:3 3< <(printf '%s\n' "$enc_key") >> "$part" 2>"$errf"
        rc=$?
    else
        openssl enc "-$cipher" -pbkdf2 -iter "$ENC_BODY_ITER" -md sha256 -salt \
            -in "$in" -pass fd:3 3< <(printf '%s\n' "$enc_key") >> "$part" 2>"$errf"
        rc=$?
    fi
    enc_key=""
    if (( rc != 0 )); then
        ENC_ERR="OpenSSL encryption failed: $(head -n 2 "$errf" 2>/dev/null | tr '\n' ' ')"
        rm -f -- "$part" "$errf"; core_cleanup_forget "$part"
        return "$EX_FAIL"
    fi
    rm -f "$errf"

    _crypto_phase mac
    local tag
    tag=$(_crypto_hmac "$mac_key" < "$part") || {
        rm -f -- "$part"; core_cleanup_forget "$part"
        ENC_ERR="Could not compute the authentication tag."; return "$EX_FAIL"
    }
    mac_key=""
    if ! printf '%s' "$tag" >> "$part"; then
        rm -f -- "$part"; core_cleanup_forget "$part"
        ENC_ERR="Cannot write output: $out"; return "$EX_CANTCREAT"
    fi

    ENC_RESULT_BYTES_OUT=$(get_file_size "$part")
    if [[ "$out" == "-" ]]; then
        cat -- "$part"; rc=$?
        rm -f -- "$part"; core_cleanup_forget "$part"
        (( rc == 0 )) || { ENC_ERR="Cannot write to standard output."; return "$EX_CANTCREAT"; }
    else
        if ! mv -f -- "$part" "$out" 2>/dev/null; then
            rm -f -- "$part"; core_cleanup_forget "$part"
            ENC_ERR="Cannot write output: $out"; return "$EX_CANTCREAT"
        fi
        core_cleanup_forget "$part"
    fi
    ENC_META=([format]=v3 [mode]=$mode [cipher]=$cipher)
    return 0
}

# Copy stdin to stdout, discarding exactly the first N bytes. Works on pipes
# and FIFOs with every coreutils implementation: `tail -c +N` hangs on a FIFO
# with uutils coreutils (Ubuntu 25.10+), and `head -c` may read ahead. One-byte
# reads cannot overshoot; headers are small, so this costs nothing measurable.
_crypto_skip() {
    dd bs=1 count="$1" of=/dev/null 2>/dev/null
    cat
}

# --- Decryption / verification ---------------------------------------------
# crypto_decrypt IN OUT [verify-only]
#   v3 containers: authenticate first, then decrypt.
#   legacy files : best effort (see _crypto_decrypt_legacy_*).
crypto_decrypt() {
    local in="$1" out="$2" verify_only="${3:-}" private_input=0
    ENC_ERR=""; ENC_RESULT_BYTES_IN=0; ENC_RESULT_BYTES_OUT=0
    core_tmpdir

    # Standard input is spooled into the private temp dir (ciphertext only).
    if [[ "$in" == "-" ]]; then
        local spool="$TEMP_DIR/stdin.spool"
        if ! cat > "$spool"; then ENC_ERR="Cannot read standard input."; return "$EX_NOINPUT"; fi
        in="$spool"; private_input=1
    fi
    [[ "$in" == "$TEMP_DIR"/* ]] && private_input=1

    crypto_inspect "$in" || return $?
    ENC_RESULT_BYTES_IN=${ENC_META[size]}
    if [[ -z "$verify_only" && "$out" != "-" ]]; then
        if [[ -d "$out" ]]; then ENC_ERR="Output is a directory: $out"; return "$EX_CANTCREAT"; fi
        if same_file "$in" "$out"; then ENC_ERR="Input and output are the same file: $in"; return "$EX_USAGE"; fi
    fi

    case "${ENC_META[format]}" in
        legacy-enc|legacy-smime)
            if [[ -n "$verify_only" ]]; then
                ENC_ERR="Legacy 2.x files carry no authentication tag and cannot be verified."; return "$EX_UNSUPPORTED"
            fi
            # Never fall back to an unauthenticated format on the file's say-so:
            # otherwise replacing a v3 file with a 2.x-style one would silently
            # bypass authentication. The caller must opt in explicitly.
            if [[ "$ENC_ALLOW_LEGACY" != "1" ]]; then
                ENC_ERR="This is a legacy Encryptor 2.x file with NO authentication: its content cannot be verified. Decrypt it only if you trust where it came from, with --legacy."
                return "$EX_UNSUPPORTED"
            fi
            if [[ "${ENC_META[format]}" == "legacy-enc" ]]; then _crypto_decrypt_legacy_enc "$in" "$out"; else _crypto_decrypt_legacy_smime "$in" "$out"; fi
            return $? ;;
    esac

    local cipher="${ENC_META[cipher]}" hdr_len="${ENC_META[hdr_len]}" size="${ENC_META[size]}"
    local auth_len=$(( size - ENC_TAG_LEN ))
    if ! crypto_cipher_available "$cipher"; then
        ENC_ERR="Algorithm '$cipher' is not available in this OpenSSL build."; return "$EX_UNSUPPORTED"
    fi

    local master
    if [[ "${ENC_META[mode]}" == "password" ]]; then
        if [[ -z "$ENC_SECRET" ]]; then ENC_ERR="This file is password-protected: a password is required."; return "$EX_USAGE"; fi
        crypto_check_secret "$ENC_SECRET" "Password" || return "$EX_USAGE"
        if [[ "${ENC_META[kdf]}" == "scrypt" ]]; then
            if ! crypto_scrypt_available; then
                ENC_ERR="This file uses scrypt, which this OpenSSL build does not support."; return "$EX_UNSUPPORTED"
            fi
            _crypto_phase kdf "scrypt ${ENC_META[scrypt]}"
            master=$(_crypto_unseal_master "${ENC_META[sealed]}" "$ENC_SECRET") || {
                ENC_ERR="Authentication failed: wrong password, or the file has been modified or corrupted."
                return "$EX_AUTH"
            }
        else
            _crypto_phase kdf "PBKDF2-HMAC-SHA256, ${ENC_META[iter]} iterations"
            master=$(_crypto_pbkdf2 "$ENC_SECRET" "${ENC_META[salt]}" "${ENC_META[iter]}") || {
                ENC_ERR="Key derivation failed."; return "$EX_FAIL"
            }
        fi
    else
        if [[ -z "$ENC_KEY_FILE" ]]; then ENC_ERR="This file is encrypted for certificate recipients: a private key (--key) is required."; return "$EX_USAGE"; fi
        if [[ ! -f "$ENC_KEY_FILE" || ! -r "$ENC_KEY_FILE" ]]; then ENC_ERR="Private key not found or not readable: $ENC_KEY_FILE"; return "$EX_NOINPUT"; fi
        if [[ -n "$ENC_CERT_FILE" && ! -f "$ENC_CERT_FILE" ]]; then ENC_ERR="Certificate not found: $ENC_CERT_FILE"; return "$EX_NOINPUT"; fi
        if [[ -n "$ENC_KEY_SECRET" ]]; then crypto_check_secret "$ENC_KEY_SECRET" "Key passphrase" || return "$EX_USAGE"; fi
        _crypto_phase unwrap
        master=$(_crypto_unwrap_master "${ENC_META[wrapped]}" "$ENC_KEY_FILE" "$ENC_CERT_FILE" "$ENC_KEY_SECRET") || {
            ENC_ERR="Could not unwrap the file key: this private key is not a recipient of the file, or its passphrase is wrong."
            return "$EX_AUTH"
        }
    fi

    local enc_key mac_key
    enc_key=$(_crypto_subkey "$master" "encryptor/3 body-encryption") &&
    mac_key=$(_crypto_subkey "$master" "encryptor/3 authentication") || {
        ENC_ERR="Subkey derivation failed."; return "$EX_FAIL"
    }
    master=""

    local auth_fail="Authentication failed: the file has been modified or corrupted."
    [[ "${ENC_META[mode]}" == "password" ]] && auth_fail="Authentication failed: wrong password, or the file has been modified or corrupted."
    local errf="$TEMP_DIR/dec.err" tag_stored tag_calc rc
    local -a st

    # --- Verify only, or output to a pipe -----------------------------------
    # Plaintext sent to stdout cannot be taken back, so the tag must be
    # checked first. To make the bytes that are verified and the bytes that
    # are decrypted provably the same, the two passes run over a copy in the
    # private temp dir (ciphertext only) that nobody else can modify.
    if [[ -n "$verify_only" || "$out" == "-" ]]; then
        if [[ -z "$verify_only" && $private_input -eq 0 ]]; then
            _crypto_phase verify
            local copy="$TEMP_DIR/input.copy"
            if ! head -c "$size" -- "$in" > "$copy"; then
                rm -f -- "$copy"; ENC_ERR="Not enough temporary space to stage the input (set TMPDIR, or decrypt to a file instead of '-')."; return "$EX_FAIL"
            fi
            in="$copy"
            if [[ "$(get_file_size "$in")" != "$size" ]]; then rm -f -- "$copy"; ENC_ERR="$auth_fail"; return "$EX_AUTH"; fi
        fi
        _crypto_phase verify
        tag_calc=$(head -c "$auth_len" -- "$in" | _crypto_hmac "$mac_key")
        tag_stored=$(tail -c "$ENC_TAG_LEN" -- "$in" | tr -d '\000')
        mac_key=""
        if [[ ! "$tag_calc" =~ ^[0-9a-f]{64}$ ]]; then enc_key=""; ENC_ERR="Could not compute the authentication tag."; return "$EX_FAIL"; fi
        if [[ "$tag_stored" != "$tag_calc" ]]; then enc_key=""; ENC_ERR="$auth_fail"; return "$EX_AUTH"; fi
        if [[ -n "$verify_only" ]]; then enc_key=""; return 0; fi

        _crypto_phase decrypt "" 0
        head -c "$auth_len" -- "$in" | _crypto_skip "$hdr_len" \
            | openssl enc -d "-$cipher" -pbkdf2 -iter "$ENC_BODY_ITER" -md sha256 \
                -pass fd:3 3< <(printf '%s\n' "$enc_key") 2>"$errf"
        st=("${PIPESTATUS[@]}"); rc=${st[2]}
        enc_key=""
        rm -f -- "$TEMP_DIR/input.copy"
        if (( rc != 0 )); then ENC_ERR="OpenSSL decryption failed: $(head -n 2 "$errf" | tr '\n' ' ')"; rm -f "$errf"; return "$EX_FAIL"; fi
        rm -f "$errf"
        return 0
    fi

    # --- Output to a file: one pass ------------------------------------------
    # The input is read exactly once. The same byte stream feeds the HMAC and,
    # through a FIFO, the decryption, which writes to a private in-progress
    # file. That file is renamed to the requested output only if the tag over
    # the bytes that were actually decrypted is correct; otherwise it is
    # deleted. A file modified while we work can therefore never yield output.
    local part fifo="$TEMP_DIR/dec.fifo" dec_pid dec_rc
    part=$(crypto_part_path "$out")
    if ! _crypto_part_create "$part"; then
        ENC_ERR="Cannot write output: $out"; return "$EX_CANTCREAT"
    fi
    rm -f -- "$fifo"
    if ! mkfifo -m 600 "$fifo" 2>/dev/null; then
        rm -f -- "$part"; core_cleanup_forget "$part"
        ENC_ERR="Cannot create a FIFO in the temporary directory."; return "$EX_FAIL"
    fi
    _crypto_phase decrypt "$part" "${ENC_META[body_len]}"
    (
        _crypto_skip "$hdr_len" < "$fifo" \
            | openssl enc -d "-$cipher" -pbkdf2 -iter "$ENC_BODY_ITER" -md sha256 \
                -pass fd:3 3< <(printf '%s\n' "$enc_key") > "$part" 2>"$errf"
        exit "${PIPESTATUS[1]}"
    ) &
    dec_pid=$!
    # SIGPIPE is ignored for tee so that a failing decryption (e.g. disk full)
    # cannot cut the HMAC input short and be misreported as tampering.
    tag_calc=$(head -c "$auth_len" -- "$in" | { trap '' PIPE; tee -- "$fifo" 2>/dev/null; } | _crypto_hmac "$mac_key")
    wait "$dec_pid"; dec_rc=$?
    rm -f -- "$fifo"
    enc_key=""; mac_key=""
    tag_stored=$(tail -c "$ENC_TAG_LEN" -- "$in" | tr -d '\000')

    if [[ ! "$tag_calc" =~ ^[0-9a-f]{64}$ || "$tag_stored" != "$tag_calc" ]]; then
        rm -f -- "$part" "$errf"; core_cleanup_forget "$part"
        ENC_ERR="$auth_fail"; return "$EX_AUTH"
    fi
    if (( dec_rc != 0 )); then
        ENC_ERR="Decryption failed after successful authentication: $(head -n 2 "$errf" 2>/dev/null | tr '\n' ' ')(is the disk full?)"
        rm -f -- "$part" "$errf"; core_cleanup_forget "$part"
        return "$EX_FAIL"
    fi
    rm -f "$errf"
    ENC_RESULT_BYTES_OUT=$(get_file_size "$part")
    if ! mv -f -- "$part" "$out" 2>/dev/null; then
        rm -f -- "$part"; core_cleanup_forget "$part"
        ENC_ERR="Cannot write output: $out"; return "$EX_CANTCREAT"
    fi
    core_cleanup_forget "$part"
    return 0
}

crypto_verify() { crypto_decrypt "$1" "" verify; }

# --- Legacy formats (read-only) ---------------------------------------------
# Encryptor 2.x wrote raw `openssl enc` output: no algorithm metadata and no
# authentication. We can still decrypt it, but cannot prove it is unmodified.
# A `.sha256` sidecar, when present, is checked — it detects accidental
# corruption only (anyone who can modify the file can recompute the hash).
_crypto_decrypt_legacy_enc() {
    local in="$1" out="$2"
    local algo="$ENC_LEGACY_ALGO" iter="$ENC_LEGACY_ITER"
    if ! crypto_is_cipher "$algo"; then
        ENC_ERR="Unknown legacy algorithm '$algo'. Valid: ${ENC_CIPHER_IDS[*]}"; return "$EX_USAGE"
    fi
    if [[ ! "$iter" =~ ^[0-9]{1,9}$ ]] || (( 10#$iter < 1 || 10#$iter > ENC_ITER_MAX )); then
        ENC_ERR="Invalid iteration count."; return "$EX_USAGE"
    fi
    iter=$(( 10#$iter ))
    crypto_check_secret "$ENC_SECRET" "Password" || return "$EX_USAGE"

    local sidecar="${in}.sha256"
    if [[ -f "$sidecar" ]]; then
        local want have
        IFS=$' \t' read -r want _ < "$sidecar" || true
        want=${want,,}
        have=$(sha256_file "$in")
        if [[ -n "$want" && "$want" != "$have" ]]; then
            ENC_ERR="Checksum mismatch against ${sidecar}: the file is corrupted or was modified."
            return "$EX_AUTH"
        fi
    fi

    core_tmpdir
    local errf="$TEMP_DIR/dec.err" rc part
    _crypto_phase kdf "PBKDF2-HMAC-SHA256, ${iter} iterations"
    if [[ "$out" == "-" ]]; then
        openssl enc -d "-$algo" -pbkdf2 -iter "$iter" -md sha256 -in "$in" \
            -pass fd:3 3< <(printf '%s\n' "$ENC_SECRET") 2>"$errf"
        rc=$?
    else
        part=$(crypto_part_path "$out")
        _crypto_part_create "$part" || { ENC_ERR="Cannot write output: $out"; return "$EX_CANTCREAT"; }
        openssl enc -d "-$algo" -pbkdf2 -iter "$iter" -md sha256 -in "$in" \
            -pass fd:3 3< <(printf '%s\n' "$ENC_SECRET") > "$part" 2>"$errf"
        rc=$?
    fi
    rm -f "$errf"
    if (( rc != 0 )); then
        [[ -n "${part:-}" ]] && { rm -f -- "$part"; core_cleanup_forget "$part"; }
        ENC_ERR="Legacy decryption failed: wrong password, wrong algorithm/iteration count, or corrupted file."
        return "$EX_AUTH"
    fi
    if [[ -n "${part:-}" ]]; then
        ENC_RESULT_BYTES_OUT=$(get_file_size "$part")
        mv -f -- "$part" "$out" 2>/dev/null || { rm -f -- "$part"; core_cleanup_forget "$part"; ENC_ERR="Cannot write output: $out"; return "$EX_CANTCREAT"; }
        core_cleanup_forget "$part"
    fi
    return 0
}

# Encryptor 2.x "S/MIME" files: PEM PKCS#7 written by `openssl smime -encrypt`.
_crypto_decrypt_legacy_smime() {
    local in="$1" out="$2"
    if [[ -z "$ENC_KEY_FILE" || ! -f "$ENC_KEY_FILE" ]]; then
        ENC_ERR="A private key (--key) is required to decrypt this S/MIME file."; return "$EX_USAGE"
    fi
    if [[ -n "$ENC_KEY_SECRET" ]]; then crypto_check_secret "$ENC_KEY_SECRET" "Key passphrase" || return "$EX_USAGE"; fi
    local -a args=(-decrypt -in "$in" -inform PEM -inkey "$ENC_KEY_FILE")
    [[ -n "$ENC_CERT_FILE" ]] && args+=(-recip "$ENC_CERT_FILE")
    core_tmpdir
    local errf="$TEMP_DIR/dec.err" rc part target
    if [[ "$out" == "-" ]]; then target="/dev/stdout"
    else
        part=$(crypto_part_path "$out")
        _crypto_part_create "$part" || { ENC_ERR="Cannot write output: $out"; return "$EX_CANTCREAT"; }
        target="$part"
    fi
    if [[ -n "$ENC_KEY_SECRET" ]]; then
        openssl smime "${args[@]}" -passin fd:4 4< <(printf '%s\n' "$ENC_KEY_SECRET") > "$target" 2>"$errf"; rc=$?
    else
        openssl smime "${args[@]}" > "$target" 2>"$errf"; rc=$?
    fi
    rm -f "$errf"
    if (( rc != 0 )); then
        [[ -n "${part:-}" ]] && { rm -f -- "$part"; core_cleanup_forget "$part"; }
        ENC_ERR="Legacy S/MIME decryption failed: the private key does not match, or the file is corrupted."
        return "$EX_AUTH"
    fi
    if [[ -n "${part:-}" ]]; then
        ENC_RESULT_BYTES_OUT=$(get_file_size "$part")
        mv -f -- "$part" "$out" 2>/dev/null || { rm -f -- "$part"; core_cleanup_forget "$part"; ENC_ERR="Cannot write output: $out"; return "$EX_CANTCREAT"; }
        core_cleanup_forget "$part"
    fi
    return 0
}

# --- Secure deletion (best effort) -----------------------------------------
# Overwrites then unlinks. On SSDs, copy-on-write or journaling filesystems,
# snapshots and network storage the old blocks may survive: this is a
# mitigation, not a guarantee. Full-disk encryption is the real answer.
SECURE_DELETE_METHOD=""
secure_delete() {
    local file="$1"
    if [[ -L "$file" ]]; then
        ENC_ERR="$file is a symbolic link; refusing to overwrite its target. Delete the target explicitly."
        return "$EX_FAIL"
    fi
    [[ -f "$file" ]] || { ENC_ERR="Not a regular file: $file"; return "$EX_NOINPUT"; }
    if have shred; then
        if shred -u -z -n 2 -- "$file" 2>/dev/null; then SECURE_DELETE_METHOD="shred (2 random passes + zero pass)"; return 0; fi
    fi
    local sz blocks
    sz=$(get_file_size "$file")
    blocks=$(( (sz + 1048575) / 1048576 ))
    if (( blocks > 0 )); then
        dd if=/dev/urandom of="$file" bs=1048576 count="$blocks" conv=notrunc 2>/dev/null
        sync 2>/dev/null || true
    fi
    rm -f -- "$file" || { ENC_ERR="Could not remove $file"; return "$EX_FAIL"; }
    SECURE_DELETE_METHOD="random overwrite + unlink"
    return 0
}

# --- Password utilities -----------------------------------------------------
# Generate a random passphrase of N characters from [A-Za-z0-9] (~5.95 bits each).
crypto_generate_password() {
    local len="${1:-24}" out="" chunk
    while (( ${#out} < len )); do
        chunk=$(openssl rand -base64 48 2>/dev/null | tr -d '+/=\n') || return 1
        [[ -n "$chunk" ]] || return 1
        out+="$chunk"
    done
    printf '%s' "${out:0:len}"
}

# Rough strength estimate in bits (length × log2 of the character pool).
# This is an upper bound for human-chosen passwords: it is a guide, not a proof.
crypto_password_bits() {
    local pw="$1" pool=0 LC_ALL=C
    [[ "$pw" =~ [a-z] ]] && pool=$(( pool + 26 ))
    [[ "$pw" =~ [A-Z] ]] && pool=$(( pool + 26 ))
    [[ "$pw" =~ [0-9] ]] && pool=$(( pool + 10 ))
    [[ "$pw" =~ [^a-zA-Z0-9] ]] && pool=$(( pool + 32 ))
    (( pool == 0 )) && { printf '0'; return; }
    # log2(pool) in tenths of a bit, integer arithmetic.
    local l2
    if   (( pool <= 10 )); then l2=33
    elif (( pool <= 26 )); then l2=47
    elif (( pool <= 36 )); then l2=51
    elif (( pool <= 52 )); then l2=57
    elif (( pool <= 62 )); then l2=59
    else                        l2=65; fi
    printf '%d' $(( ${#pw} * l2 / 10 ))
}

# --- Self-test (known-answer tests + round trip) ----------------------------
# Proves that this machine's OpenSSL produces the standard results the format
# depends on. Returns 0 when everything matches.
crypto_selftest() {
    ENC_ERR=""
    # RFC 4231 test case 2 (HMAC-SHA-256, key "Jefe").
    local got
    got=$(printf '%s' "what do ya want for nothing?" | _crypto_hmac "4a656665")
    if [[ "$got" != "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843" ]]; then
        ENC_ERR="HMAC-SHA256 known-answer test failed."; return 1
    fi
    # PBKDF2-HMAC-SHA256("encryptor-selftest", 0001020304050607, 1000 iterations, 32 bytes).
    got=$(_crypto_pbkdf2 "encryptor-selftest" "0001020304050607" 1000)
    if [[ "$got" != "$CRYPTO_KAT_PBKDF2" ]]; then
        ENC_ERR="PBKDF2-HMAC-SHA256 known-answer test failed."; return 1
    fi
    # scrypt envelope: a fixed blob sealed by OpenSSL 3.0 must open to the same
    # key everywhere (proves cross-version interoperability of the container).
    if crypto_scrypt_available; then
        got=$(_crypto_sealed_params "$CRYPTO_KAT_SCRYPT_SEALED")
        if [[ "$got" != "1024:8:1" ]]; then ENC_ERR="scrypt envelope parameter parsing failed."; return 1; fi
        got=$(_crypto_unseal_master "$CRYPTO_KAT_SCRYPT_SEALED" "encryptor-selftest")
        if [[ "$got" != "$CRYPTO_KAT_SCRYPT_MASTER" ]]; then ENC_ERR="scrypt known-answer test failed."; return 1; fi
        if _crypto_unseal_master "$CRYPTO_KAT_SCRYPT_SEALED" "wrong-password" >/dev/null; then
            ENC_ERR="scrypt envelope accepted a wrong password."; return 1
        fi
    fi
    # Round trip + tamper detection with the default cipher (both KDFs).
    core_tmpdir
    local d="$TEMP_DIR/selftest"; mkdir -p "$d" || return 1
    local saved_secret="$ENC_SECRET"; local -a saved_rcpt=("${ENC_RECIPIENTS[@]:-}")
    ENC_RECIPIENTS=(); ENC_SECRET="selftest-password"
    printf 'encryptor self-test payload\n' > "$d/plain"
    local rc=0
    crypto_encrypt "$d/plain" "$d/enc" "$ENC_DEFAULT_CIPHER" "$ENC_ITER_MIN" pbkdf2 || rc=1
    (( rc == 0 )) && { crypto_decrypt "$d/enc" "$d/back" || rc=1; }
    (( rc == 0 )) && { cmp -s "$d/plain" "$d/back" || rc=1; }
    if (( rc == 0 )) && crypto_scrypt_available; then
        crypto_encrypt "$d/plain" "$d/enc2" "$ENC_DEFAULT_CIPHER" "$ENC_ITER_MIN" scrypt || rc=1
        (( rc == 0 )) && { crypto_decrypt "$d/enc2" "$d/back2" || rc=1; }
        (( rc == 0 )) && { cmp -s "$d/plain" "$d/back2" || rc=1; }
    fi
    if (( rc == 0 )); then
        # Change one ciphertext byte (to a value guaranteed to differ):
        # authentication must fail.
        local size old new="X"; size=$(get_file_size "$d/enc")
        old=$(head -c $(( size - 69 )) "$d/enc" | tail -c 1 | od -An -v -tx1 | tr -d ' \n')
        [[ "$old" == "58" ]] && new="Y"
        { head -c $(( size - 70 )) "$d/enc"; printf '%s' "$new"; tail -c 69 "$d/enc"; } > "$d/bad"
        if crypto_decrypt "$d/bad" "$d/bad.out" 2>/dev/null; then rc=1; fi
        [[ -e "$d/bad.out" ]] && rc=1
    fi
    rm -rf "$d"
    ENC_SECRET="$saved_secret"; ENC_RECIPIENTS=()
    local c; for c in "${saved_rcpt[@]:-}"; do [[ -n "$c" ]] && ENC_RECIPIENTS+=("$c"); done
    if (( rc != 0 )); then ENC_ERR="Encrypt/decrypt round-trip self-test failed."; return 1; fi
    ENC_ERR=""
    return 0
}
