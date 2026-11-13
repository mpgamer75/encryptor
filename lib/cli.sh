#!/usr/bin/env bash
# ==============================================================================
# lib/cli.sh — Non-interactive command-line interface.
#
#   encryptor <command> [options] [FILE...]
#
# Designed for scripts and CI: no prompts unless a terminal is attached, stable
# exit codes, --json output, stdin/stdout via "-", secrets only from files,
# environment variables, stdin or the terminal — never from arguments.
# ==============================================================================

cli_help_text() {
    cat <<EOF
${BOLD}ENCRYPTOR ${ENCRYPTOR_VERSION}${RESET} — authenticated file encryption and X.509 toolkit (Bash + OpenSSL)

${BOLD}USAGE${RESET}
  encryptor                               Interactive menu
  encryptor encrypt [options] FILE...     Encrypt (FILE → FILE.enc)
  encryptor decrypt [options] FILE...     Decrypt (FILE.enc → FILE); format auto-detected
  encryptor inspect [--json] FILE         Show container metadata (no secrets needed)
  encryptor verify  [options] FILE        Check password/key and integrity; writes nothing
  encryptor certs   [--json] [--warn-days N]   Certificate store report (exit 1 if expiring)
  encryptor audit   [--json]              Local security audit (exit 1 if a check fails)
  encryptor selftest                      Known-answer tests of the crypto engine
  encryptor passgen [LENGTH]              Print a random password (default 24 characters)
  encryptor completion bash|zsh           Print a shell completion script
  encryptor help | version

${BOLD}ENCRYPT / DECRYPT OPTIONS${RESET}
  -o, --output PATH        Output file ("-" = stdout). Single input only.
  -p, --pass-file FILE     Read the password from the first line of FILE
      --pass-env VAR       Read the password from environment variable VAR
      --pass-stdin         Read the password from the first line of stdin
  -r, --recipient CERT     Encrypt for an X.509 certificate (repeatable)
  -k, --key KEY            Private key for recipient-mode decryption
  -c, --cert CERT          Certificate matching --key (optional, speeds up lookup)
      --key-pass-file FILE Passphrase of an encrypted private key
  -a, --algo CIPHER        ${ENC_CIPHER_IDS[*]}
                           (default ${ENC_DEFAULT_CIPHER}; for legacy 2.x files: the cipher used)
      --kdf NAME           Password KDF for new files: scrypt (memory-hard, default when
                           supported), pbkdf2 (NIST-approved), auto
      --iter N             PBKDF2 iterations with --kdf pbkdf2 (default ${ENC_DEFAULT_ITER})
      --legacy             Accept an Encryptor 2.x file. Those files have NO
                           authentication: use only for files you trust.
      --legacy-iter N      Iterations of a legacy file (2.1: 600000, 2.0: 100000)
  -f, --force              Overwrite an existing output file
      --shred              After a verified encryption, overwrite and delete the input
                           (with --recipient, also give --key so the result can be verified)
      --json               One JSON object per file on stdout
  -q, --quiet              No informational output
      --no-color           Disable colors (also: NO_COLOR=1)
  FILE may be "-" to read stdin. Without a password option, the password is
  prompted on the terminal.

${BOLD}EXAMPLES${RESET}
  encryptor encrypt report.pdf                         # prompts for a password
  encryptor encrypt -p pass.txt -o backup.enc db.sql   # scripted
  tar cz project/ | encryptor encrypt -p pass.txt -o project.tgz.enc -
  encryptor decrypt -p pass.txt -o - project.tgz.enc | tar xz
  encryptor encrypt -r alice.pem -r bob.pem contract.docx
  encryptor decrypt -k ~/.config/encryptor/certs/alice.key contract.docx.enc
  encryptor certs --json --warn-days 45                # monitoring / cron

${BOLD}FORMAT${RESET}
  New files use the self-describing ENCRYPTOR/3 container: cipher + HMAC-SHA256
  (encrypt-then-MAC). The tag covers the header and all ciphertext and is
  verified before any plaintext is written. Keys: a random file key sealed
  with scrypt (or derived with PBKDF2-HMAC-SHA256) from a password, or wrapped
  for each certificate recipient (CMS, RSA-OAEP or ECDH). Files written by
  Encryptor 2.x are still decrypted.
  Specification and a recovery recipe using only openssl: docs/FORMAT.md

${BOLD}EXIT STATUS${RESET}
  0 success            3 wrong password/key or failed authentication
  1 failure            4 input not found          5 output exists / not writable
  2 usage error        6 unsupported format       130 interrupted

${BOLD}FILES${RESET}
  ${CONFIG_DIR}/certs/           certificates and private keys
  ${CONFIG_DIR}/encryptor.log    operation log (ENCRYPTOR_NO_LOG=1 disables)
  Environment: ENCRYPTOR_CONFIG_DIR, ENCRYPTOR_KDF, ENCRYPTOR_PBKDF2_ITER,
               ENCRYPTOR_NO_LOG, NO_COLOR
EOF
}

# --- Output helpers ----------------------------------------------------------
CLI_JSON=0; CLI_QUIET=0

# Messages may quote file names: they are made terminal-safe here, once.
_cli_err() {
    if [[ -t 2 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" ]]; then
        printf '\e[31mencryptor: error:\e[0m %s\n' "$(ui_safe "$*")" >&2
    else
        printf 'encryptor: error: %s\n' "$(ui_safe "$*")" >&2
    fi
}
_cli_warn() { printf 'encryptor: warning: %s\n' "$(ui_safe "$*")" >&2; }
_cli_usage_error() { _cli_err "$*"; printf 'Run "encryptor help" for usage.\n' >&2; exit "$EX_USAGE"; }
_cli_need_arg() { [[ $# -ge 2 ]] || _cli_usage_error "option $1 requires a value"; }

# --- Secret loading ----------------------------------------------------------
CLI_PASS_FILE=""; CLI_PASS_ENV=""; CLI_PASS_STDIN=0; CLI_KEY_PASS_FILE=""

_cli_read_secret_file() {
    local file="$1" what="$2" line="" mode
    [[ -f "$file" && -r "$file" ]] || { _cli_err "$what file not found or not readable: $file"; exit "$EX_NOINPUT"; }
    mode=$(get_file_mode "$file")
    if [[ -n "$mode" && "${mode: -2}" != "00" ]]; then
        _cli_warn "$file is readable by other users (mode $mode); use chmod 600."
    fi
    IFS= read -r line < "$file" || true
    line=${line%$'\r'}
    [[ -n "$line" ]] || { _cli_err "$what file is empty: $file"; exit "$EX_USAGE"; }
    CLI_SECRET="$line"
}

# _cli_load_password CONFIRM(0|1) → sets CLI_SECRET
CLI_SECRET=""
_cli_load_password() {
    local confirm="$1" pw="" pw2=""
    CLI_SECRET=""
    if [[ -n "$CLI_PASS_FILE" ]]; then
        _cli_read_secret_file "$CLI_PASS_FILE" "Password"
    elif [[ -n "$CLI_PASS_ENV" ]]; then
        [[ "$CLI_PASS_ENV" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || _cli_usage_error "invalid environment variable name: $CLI_PASS_ENV"
        CLI_SECRET="${!CLI_PASS_ENV:-}"
        [[ -n "$CLI_SECRET" ]] || { _cli_err "environment variable $CLI_PASS_ENV is empty or unset"; exit "$EX_USAGE"; }
        # Do not hand the password on to every child process we start.
        unset "$CLI_PASS_ENV"
    elif (( CLI_PASS_STDIN )); then
        IFS= read -r pw || true
        pw=${pw%$'\r'}
        [[ -n "$pw" ]] || { _cli_err "no password received on stdin"; exit "$EX_USAGE"; }
        CLI_SECRET="$pw"
    elif [[ -r /dev/tty && -w /dev/tty ]] && { [[ -t 0 ]] || [[ -t 2 ]]; }; then
        printf 'Password: ' > /dev/tty
        IFS= read -rs pw < /dev/tty || true
        printf '\n' > /dev/tty
        [[ -n "$pw" ]] || { _cli_err "empty password"; exit "$EX_USAGE"; }
        if (( confirm )); then
            printf 'Confirm:  ' > /dev/tty
            IFS= read -rs pw2 < /dev/tty || true
            printf '\n' > /dev/tty
            [[ "$pw" == "$pw2" ]] || { _cli_err "passwords do not match"; exit "$EX_USAGE"; }
        fi
        CLI_SECRET="$pw"
    else
        _cli_usage_error "no password source: use --pass-file, --pass-env or --pass-stdin (or run in a terminal)"
    fi
}

# --- JSON result lines -------------------------------------------------------
_cli_json_ok() {    # op input output format mode algo bytes_in bytes_out ms [kdf] [verified]
    local fields=""
    [[ -n "${10:-}" ]] && fields+=",\"kdf\":\"${10}\""
    [[ -n "${11:-}" ]] && fields+=",\"verified\":${11}"
    printf '{"status":"success","operation":"%s","input":"%s","output":"%s","format":"%s","mode":"%s","algo":"%s"%s,"bytes_in":%d,"bytes_out":%d,"ms":%d}\n' \
        "$1" "$(json_escape "$2")" "$(json_escape "$3")" "$4" "$5" "$6" "$fields" "$7" "$8" "$9"
}
_cli_json_err() {   # op input code message
    printf '{"status":"error","operation":"%s","input":"%s","code":%d,"error":"%s"}\n' \
        "$1" "$(json_escape "$2")" "$3" "$(json_escape "$4")"
}

_cli_format_name() {
    case "${ENC_META[format]:-}" in
        v3) printf 'encryptor/3' ;; legacy-enc) printf 'openssl-enc-legacy' ;;
        legacy-smime) printf 'smime-legacy' ;; *) printf 'unknown' ;;
    esac
}

# --- encrypt -----------------------------------------------------------------
cli_encrypt() {
    local output="" algo="$ENC_DEFAULT_CIPHER" iter="$ENC_DEFAULT_ITER" force=0 shred=0 kdf="" iter_given=0
    local verify_key="" verify_key_secret=""
    CLI_KEY_PASS_FILE=""
    local -a files=() recipients=()
    CLI_PASS_FILE=""; CLI_PASS_ENV=""; CLI_PASS_STDIN=0
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o|--output)     _cli_need_arg "$@"; output="$2"; shift 2 ;;
            -p|--pass-file)  _cli_need_arg "$@"; CLI_PASS_FILE="$2"; shift 2 ;;
            --pass-env)      _cli_need_arg "$@"; CLI_PASS_ENV="$2"; shift 2 ;;
            --pass-stdin)    CLI_PASS_STDIN=1; shift ;;
            -r|--recipient|--cert) _cli_need_arg "$@"; recipients+=("$2"); shift 2 ;;
            -a|--algo)       _cli_need_arg "$@"; algo="${2,,}"; shift 2 ;;
            --iter)          _cli_need_arg "$@"; iter="$2"; iter_given=1; shift 2 ;;
            --kdf)           _cli_need_arg "$@"; kdf="${2,,}"; shift 2 ;;
            -f|--force)      force=1; shift ;;
            --shred)         shred=1; shift ;;
            -k|--key)        _cli_need_arg "$@"; verify_key="$2"; shift 2 ;;
            --key-pass-file) _cli_need_arg "$@"; CLI_KEY_PASS_FILE="$2"; shift 2 ;;
            --json)          CLI_JSON=1; shift ;;
            -q|--quiet)      CLI_QUIET=1; shift ;;
            --)              shift; files+=("$@"); break ;;
            -)               files+=("-"); shift ;;
            -*)              _cli_usage_error "unknown option for encrypt: $1" ;;
            *)               files+=("$1"); shift ;;
        esac
    done
    # v2 compatibility: "--algo smime --cert CERT" meant certificate encryption.
    if [[ "$algo" == "smime" ]]; then
        (( ${#recipients[@]} > 0 )) || _cli_usage_error "--algo smime requires --recipient CERT"
        algo="$ENC_DEFAULT_CIPHER"
    fi
    (( ${#files[@]} > 0 )) || _cli_usage_error "encrypt: no input file"
    crypto_is_cipher "$algo" || _cli_usage_error "unknown algorithm '$algo' (valid: ${ENC_CIPHER_IDS[*]})"
    case "$kdf" in
        "")                 kdf="$ENC_DEFAULT_KDF"; (( iter_given )) && kdf="pbkdf2" ;;   # --iter implies PBKDF2
        scrypt|pbkdf2|auto) ;;
        *)                  _cli_usage_error "unknown KDF '$kdf' (valid: scrypt pbkdf2 auto)" ;;
    esac
    if (( iter_given )) && [[ "$kdf" == "scrypt" ]]; then _cli_usage_error "--iter applies to --kdf pbkdf2 only"; fi
    [[ "$iter" =~ ^[0-9]{1,9}$ ]] && iter=$(( 10#$iter ))      # "0800000" is decimal, not octal
    if (( shred )) && (( ${#recipients[@]} > 0 )); then
        # Without a recipient's private key the result cannot be test-opened,
        # and deleting the only plaintext on faith is how data gets lost.
        [[ -n "$verify_key" ]] || _cli_usage_error "--shred with --recipient requires --key KEY (a recipient's private key) to verify the encrypted file before the original is deleted"
        [[ -f "$verify_key" && -r "$verify_key" ]] || { _cli_err "private key not found: $verify_key"; exit "$EX_NOINPUT"; }
        if [[ -n "$CLI_KEY_PASS_FILE" ]]; then _cli_read_secret_file "$CLI_KEY_PASS_FILE" "Key passphrase"; verify_key_secret="$CLI_SECRET"; CLI_SECRET=""; fi
    fi
    if [[ -n "$output" ]] && (( ${#files[@]} > 1 )); then _cli_usage_error "--output can only be used with a single input"; fi
    if (( CLI_PASS_STDIN )); then
        local f; for f in "${files[@]}"; do [[ "$f" == "-" ]] && _cli_usage_error "--pass-stdin cannot be combined with input from stdin"; done
    fi

    crypto_reset_inputs
    local mode="password" c
    if (( ${#recipients[@]} > 0 )); then
        mode="recipient"
        for c in "${recipients[@]}"; do
            [[ -f "$c" && -r "$c" ]] || { _cli_err "recipient certificate not found: $c"; exit "$EX_NOINPUT"; }
        done
        ENC_RECIPIENTS=("${recipients[@]}")
    else
        _cli_load_password 1
        ENC_SECRET="$CLI_SECRET"
    fi

    local in out rc worst=0 t0 t1
    for in in "${files[@]}"; do
        if [[ -n "$output" ]]; then out="$output"
        elif [[ "$in" == "-" ]]; then out="-"
        else out="${in}.enc"; fi
        if [[ "$in" != "-" && "$out" != "-" ]] && { [[ "$in" == "$out" ]] || same_file "$in" "$out"; }; then
            ENC_ERR="Input and output are the same file: $in"; rc=$EX_USAGE
        elif [[ "$out" != "-" && -d "$out" ]]; then
            ENC_ERR="Output is a directory: $out"; rc=$EX_CANTCREAT
        elif [[ "$in" != "-" && -d "$in" ]]; then
            ENC_ERR="$in is a directory. Archive it first:  tar cz '$in' | encryptor encrypt -o '${in%/}.tgz.enc' -"; rc=$EX_NOINPUT
        elif [[ "$out" != "-" && -e "$out" && $force -eq 0 ]]; then
            ENC_ERR="Output already exists: $out (use --force to overwrite)"; rc=$EX_CANTCREAT
        else
            t0=$(now_ms)
            crypto_encrypt "$in" "$out" "$algo" "$iter" "$kdf"; rc=$?
            t1=$(now_ms)
        fi

        if (( rc == 0 )); then
            log_operation "SUCCESS" "Encrypted: $in → $out (cipher=$algo, mode=$mode)"
            local stream=1; [[ "$out" == "-" ]] && stream=2
            if (( CLI_JSON )); then
                local used_kdf=""; [[ "$mode" == "password" ]] && used_kdf="$ENC_RESULT_KDF"
                _cli_json_ok encrypt "$in" "$out" "encryptor/3" "$mode" "$algo" "$ENC_RESULT_BYTES_IN" "$ENC_RESULT_BYTES_OUT" "$(( t1 - t0 ))" "$used_kdf" >&$stream
            elif (( ! CLI_QUIET )); then
                local how="$mode"; [[ "$mode" == "password" ]] && how="password/$ENC_RESULT_KDF"
                printf 'Encrypted: %s %s %s (%s, %s, %d ms)\n' "$(ui_safe "$in")" "$G_ARROW" "$(ui_safe "$out")" "$algo+hmac-sha256" "$how" "$(( t1 - t0 ))" >&$stream
            fi
            if (( shred )) && [[ "$in" != "-" && "$out" != "-" ]]; then
                local vrc=0
                if [[ "$mode" == "recipient" ]]; then ENC_KEY_FILE="$verify_key"; ENC_KEY_SECRET="$verify_key_secret"; fi
                crypto_verify "$out"; vrc=$?
                # Last line of defence against deleting the only copy: the file
                # about to be shredded must not be the file that was just written.
                if (( vrc == 0 )) && same_file "$in" "$out"; then ENC_ERR="input and output are the same file"; vrc=$EX_FAIL; fi
                if (( vrc != 0 )); then
                    _cli_err "verification of $out failed; $in was NOT deleted ($ENC_ERR)"; worst=$EX_FAIL
                elif secure_delete "$in"; then
                    log_operation "INFO" "Original securely deleted: $in"
                    (( CLI_QUIET || CLI_JSON )) || printf 'Deleted:   %s (%s; best-effort on SSD/CoW storage)\n' "$(ui_safe "$in")" "$SECURE_DELETE_METHOD"
                else
                    _cli_err "$ENC_ERR"; worst=$EX_FAIL
                fi
            fi
        else
            log_operation "ERROR" "Encrypt failed: $in — $ENC_ERR"
            if (( CLI_JSON )); then _cli_json_err encrypt "$in" "$rc" "$ENC_ERR"; fi
            _cli_err "$ENC_ERR"
            (( worst == 0 )) && worst=$rc
        fi
    done
    crypto_reset_inputs
    exit "$worst"
}

# --- decrypt / verify --------------------------------------------------------
cli_decrypt() {
    local op="$1"; shift           # decrypt | verify
    local output="" force=0 legacy_algo="" legacy_iter="" allow_legacy=0
    local -a files=()
    local key="" cert=""
    CLI_PASS_FILE=""; CLI_PASS_ENV=""; CLI_PASS_STDIN=0; CLI_KEY_PASS_FILE=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -o|--output)     _cli_need_arg "$@"; output="$2"; shift 2 ;;
            -p|--pass-file)  _cli_need_arg "$@"; CLI_PASS_FILE="$2"; shift 2 ;;
            --pass-env)      _cli_need_arg "$@"; CLI_PASS_ENV="$2"; shift 2 ;;
            --pass-stdin)    CLI_PASS_STDIN=1; shift ;;
            -k|--key)        _cli_need_arg "$@"; key="$2"; shift 2 ;;
            -c|--cert)       _cli_need_arg "$@"; cert="$2"; shift 2 ;;
            --key-pass-file) _cli_need_arg "$@"; CLI_KEY_PASS_FILE="$2"; shift 2 ;;
            -a|--algo)       _cli_need_arg "$@"; legacy_algo="${2,,}"; shift 2 ;;
            --legacy)        allow_legacy=1; shift ;;
            --legacy-iter|--iter) _cli_need_arg "$@"; legacy_iter="$2"; shift 2 ;;
            -f|--force)      force=1; shift ;;
            --json)          CLI_JSON=1; shift ;;
            -q|--quiet)      CLI_QUIET=1; shift ;;
            --)              shift; files+=("$@"); break ;;
            -)               files+=("-"); shift ;;
            -*)              _cli_usage_error "unknown option for $op: $1" ;;
            *)               files+=("$1"); shift ;;
        esac
    done
    (( ${#files[@]} > 0 )) || _cli_usage_error "$op: no input file"
    if (( CLI_PASS_STDIN )); then
        local f; for f in "${files[@]}"; do [[ "$f" == "-" ]] && _cli_usage_error "--pass-stdin cannot be combined with input from stdin"; done
    fi
    if [[ -n "$output" ]] && (( ${#files[@]} > 1 )); then _cli_usage_error "--output can only be used with a single input"; fi
    # v2 compatibility: "--algo smime --cert CERT --pass-file KEY" (key path in --pass-file).
    if [[ "$legacy_algo" == "smime" ]]; then
        if [[ -z "$key" && -n "$CLI_PASS_FILE" ]]; then key="$CLI_PASS_FILE"; CLI_PASS_FILE=""; fi
        legacy_algo=""
    fi
    if [[ -n "$legacy_algo" ]]; then crypto_is_cipher "$legacy_algo" || _cli_usage_error "unknown algorithm '$legacy_algo' (valid: ${ENC_CIPHER_IDS[*]})"; fi
    if [[ -n "$legacy_iter" ]]; then
        [[ "$legacy_iter" =~ ^[0-9]{1,9}$ ]] || _cli_usage_error "--legacy-iter expects a number"
        legacy_iter=$(( 10#$legacy_iter ))
    fi

    local in out rc worst=0 t0 t1 secret_loaded=0 key_secret=""
    if [[ -n "$CLI_KEY_PASS_FILE" ]]; then
        _cli_read_secret_file "$CLI_KEY_PASS_FILE" "Key passphrase"; key_secret="$CLI_SECRET"; CLI_SECRET=""
    fi

    for in in "${files[@]}"; do
        crypto_reset_inputs
        rc=0; out=""
        local probe="$in"
        if [[ "$in" == "-" ]]; then
            # Spool stdin once so the format can be inspected before asking for secrets.
            core_tmpdir; probe="$TEMP_DIR/cli-stdin.spool"
            cat > "$probe" || { _cli_err "cannot read standard input"; exit "$EX_NOINPUT"; }
        fi
        if crypto_inspect "$probe" && [[ "${ENC_META[format]}" == legacy-* && $allow_legacy -eq 0 && "$op" == "decrypt" ]]; then
            # Refuse before asking for any secret: the file itself must never
            # be able to select an unauthenticated code path.
            ENC_ERR="$in is a legacy Encryptor 2.x file with NO authentication: its content cannot be verified. If you trust its origin, decrypt it with --legacy (and --algo / --legacy-iter as needed), then re-encrypt it."
            rc=$EX_UNSUPPORTED
        elif crypto_inspect "$probe"; then
            ENC_ALLOW_LEGACY=$allow_legacy
            local need="password"
            [[ "${ENC_META[format]}" == "legacy-smime" || "${ENC_META[mode]:-}" == "recipient" ]] && need="key"
            if [[ "$need" == "password" ]]; then
                if (( ! secret_loaded )); then _cli_load_password 0; secret_loaded=1; fi
                ENC_SECRET="$CLI_SECRET"
            else
                [[ -n "$key" ]] || { ENC_ERR="This file is encrypted for certificate recipients: --key KEY is required."; rc=$EX_USAGE; }
                ENC_KEY_FILE="$key"; ENC_CERT_FILE="$cert"; ENC_KEY_SECRET="$key_secret"
                if (( rc == 0 )) && [[ -z "$key_secret" ]] && crypto_key_is_encrypted "$key" && [[ ! -t 0 ]]; then
                    ENC_ERR="The private key is passphrase-protected: use --key-pass-file."; rc=$EX_USAGE
                fi
            fi
            [[ -n "$legacy_algo" ]] && ENC_LEGACY_ALGO="$legacy_algo"
            [[ -n "$legacy_iter" ]] && ENC_LEGACY_ITER="$legacy_iter"
            if [[ "${ENC_META[format]}" == legacy-* && "$op" == "decrypt" ]]; then
                # Deliberately not silenced by --quiet.
                _cli_warn "$in is a legacy 2.x file: its content is NOT authenticated. Re-encrypt it to upgrade."
            fi
        else
            rc=$?
        fi

        if (( rc == 0 )) && [[ "$op" == "decrypt" ]]; then
            if [[ -n "$output" ]]; then out="$output"
            elif [[ "$in" == "-" ]]; then out="-"
            elif [[ "$in" == *.enc ]]; then out="${in%.enc}"
            else out="${in}.dec"; fi
            if [[ "$out" != "-" && -d "$out" ]]; then
                ENC_ERR="Output is a directory: $out"; rc=$EX_CANTCREAT
            elif [[ "$in" != "-" && "$out" != "-" ]] && same_file "$in" "$out"; then
                ENC_ERR="Input and output are the same file: $in"; rc=$EX_USAGE
            elif [[ "$out" != "-" && -e "$out" && $force -eq 0 ]]; then
                ENC_ERR="Output already exists: $out (use --force to overwrite, or --output)"; rc=$EX_CANTCREAT
            fi
        fi

        if (( rc == 0 )); then
            t0=$(now_ms)
            if [[ "$op" == "verify" ]]; then crypto_verify "$probe"; rc=$?
            else crypto_decrypt "$probe" "$out"; rc=$?; fi
            t1=$(now_ms)
        fi

        if (( rc == 0 )); then
            local stream=1; [[ "$out" == "-" ]] && stream=2
            if [[ "$op" == "verify" ]]; then
                log_operation "INFO" "Verified: $in"
                if (( CLI_JSON )); then _cli_json_ok verify "$in" "" "$(_cli_format_name)" "${ENC_META[mode]:-}" "${ENC_META[cipher]:-}" "${ENC_META[size]:-0}" 0 "$(( t1 - t0 ))"
                elif (( ! CLI_QUIET )); then printf 'OK: %s is authentic (%s)\n' "$(ui_safe "$in")" "${ENC_META[cipher]}+hmac-sha256"; fi
            else
                log_operation "SUCCESS" "Decrypted: $in → $out (format=${ENC_META[format]})"
                local algo_name="${ENC_META[cipher]:-$ENC_LEGACY_ALGO}"
                if (( CLI_JSON )); then
                    local verified=true; [[ "${ENC_META[format]}" == v3 ]] || verified=false
                    _cli_json_ok decrypt "$in" "$out" "$(_cli_format_name)" "${ENC_META[mode]:-legacy}" "$algo_name" "${ENC_META[size]:-0}" "$ENC_RESULT_BYTES_OUT" "$(( t1 - t0 ))" "" "$verified" >&$stream
                elif (( ! CLI_QUIET )); then
                    printf 'Decrypted: %s %s %s (%s, %d ms)\n' "$(ui_safe "$in")" "$G_ARROW" "$(ui_safe "$out")" "$algo_name" "$(( t1 - t0 ))" >&$stream
                fi
            fi
        else
            log_operation "ERROR" "${op^} failed: $in — $ENC_ERR"
            if (( CLI_JSON )); then _cli_json_err "$op" "$in" "$rc" "$ENC_ERR"; fi
            _cli_err "$ENC_ERR"
            (( worst == 0 )) && worst=$rc
        fi
    done
    crypto_reset_inputs; CLI_SECRET=""
    exit "$worst"
}

# --- inspect -----------------------------------------------------------------
cli_inspect() {
    local file=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) CLI_JSON=1; shift ;;
            -q|--quiet) CLI_QUIET=1; shift ;;
            --) shift; [[ $# -gt 0 ]] && file="$1"; break ;;
            -*) _cli_usage_error "unknown option for inspect: $1" ;;
            *)  file="$1"; shift ;;
        esac
    done
    [[ -n "$file" ]] || _cli_usage_error "inspect: no input file"
    local rc=0
    crypto_inspect "$file" || rc=$?
    if (( rc != 0 )); then
        if (( CLI_JSON )); then _cli_json_err inspect "$file" "$rc" "$ENC_ERR"; fi
        _cli_err "$ENC_ERR"; exit "$rc"
    fi
    local fmt; fmt=$(_cli_format_name)
    if (( CLI_JSON )); then
        printf '{"status":"success","file":"%s","size":%d,"format":"%s"' "$(json_escape "$file")" "${ENC_META[size]}" "$fmt"
        if [[ "${ENC_META[format]}" == v3 ]]; then
            # "verified" is always false here: inspect reads the header only.
            printf ',"integrity":"hmac-sha256","verified":false,"mode":"%s","cipher":"%s","mac":"%s","payload_bytes":%d' \
                "${ENC_META[mode]}" "${ENC_META[cipher]}" "${ENC_META[mac]}" "${ENC_META[body_len]}"
            if [[ "${ENC_META[mode]}" == password ]]; then
                if [[ "${ENC_META[kdf]}" == "scrypt" ]]; then
                    local sn sr sp; IFS=: read -r sn sr sp <<<"${ENC_META[scrypt]}"
                    printf ',"kdf":"scrypt","scrypt_n":%d,"scrypt_r":%d,"scrypt_p":%d' "$sn" "$sr" "$sp"
                else
                    printf ',"kdf":"%s","iterations":%d' "${ENC_META[kdf]}" "${ENC_META[iter]}"
                fi
            else
                local fp first=1
                printf ',"keywrap":"cms","claimed_recipients":['
                for fp in "${ENC_META_RCPT[@]:-}"; do
                    [[ -n "$fp" ]] || continue
                    (( first )) || printf ','
                    first=0; printf '"%s"' "$fp"
                done
                printf ']'
            fi
        else
            printf ',"integrity":"none","verified":false'
        fi
        printf '}\n'
    else
        printf 'File:        %s (%s)\n' "$(ui_safe "$file")" "$(human_size "${ENC_META[size]}")"
        case "${ENC_META[format]}" in
            v3)
                printf 'Format:      ENCRYPTOR/3 (encrypt-then-MAC with HMAC-SHA256)\n'
                printf 'Verified:    no — inspect only reads the header; run "encryptor verify" to check the tag\n'
                printf 'Cipher:      %s\n' "${ENC_CIPHER_LABEL[${ENC_META[cipher]}]}"
                if [[ "${ENC_META[mode]}" == password ]]; then
                    printf 'Key:         password, %s\n' "$(crypto_meta_kdf_label)"
                else
                    printf 'Key:         %d certificate recipient(s) listed in the header, CMS key wrap\n' "${#ENC_META_RCPT[@]}"
                    local fp; for fp in "${ENC_META_RCPT[@]:-}"; do [[ -n "$fp" ]] && printf '  recipient: sha256:%s\n' "$fp"; done
                fi
                printf 'Payload:     %s\n' "$(human_size "${ENC_META[body_len]}")" ;;
            legacy-enc)
                printf 'Format:      Encryptor 2.x / raw "openssl enc" (NOT authenticated)\n'
                printf 'Key:         password; the cipher is not recorded (try --algo aes-256-cbc)\n' ;;
            legacy-smime)
                printf 'Format:      Encryptor 2.x S/MIME, PEM PKCS#7 (NOT authenticated)\n'
                printf 'Key:         certificate recipient (--key required)\n' ;;
        esac
    fi
    exit 0
}

# --- audit / certs / selftest / passgen --------------------------------------
cli_audit() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) CLI_JSON=1; shift ;;
            *) _cli_usage_error "unknown option for audit: $1" ;;
        esac
    done
    audit_run "."
    if (( CLI_JSON )); then audit_report_json; else audit_report_text; fi
    log_operation "INFO" "Local audit: $(audit_percent)% (${AUDIT_FAILS} failed, ${AUDIT_WARNS} warnings)"
    (( AUDIT_FAILS == 0 )) || exit "$EX_FAIL"
    exit 0
}

cli_certs() {
    local warn_days="$PKI_EXPIRY_WARN_DAYS"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --json) CLI_JSON=1; shift ;;
            --warn-days) _cli_need_arg "$@"; warn_days="$2"; shift 2 ;;
            *) _cli_usage_error "unknown option for certs: $1" ;;
        esac
    done
    [[ "$warn_days" =~ ^[0-9]{1,5}$ ]] || _cli_usage_error "--warn-days expects a number of days"
    warn_days=$(( 10#$warn_days ))      # "030" means thirty, not octal 24
    core_init_state
    local rc=0
    if (( CLI_JSON )); then pki_report_json "$warn_days" || rc=$EX_FAIL
    else pki_report_text "$warn_days" || rc=$EX_FAIL; fi
    exit "$rc"
}

cli_selftest() {
    core_probe_openssl
    if crypto_selftest; then
        printf '%s%s%s Self-test passed (%s): HMAC-SHA256, PBKDF2 and scrypt known answers, round trips, tamper detection.\n' "$C_OK" "$G_OK" "$RESET" "$OPENSSL_VERSION_TEXT"
        exit 0
    fi
    _cli_err "self-test FAILED: $ENC_ERR"
    exit "$EX_FAIL"
}

cli_passgen() {
    local len="${1:-24}"
    [[ "$len" =~ ^[0-9]{1,3}$ ]] && (( 10#$len >= 12 && 10#$len <= 128 )) || _cli_usage_error "passgen: LENGTH must be between 12 and 128"
    len=$(( 10#$len ))
    local pw; pw=$(crypto_generate_password "$len") || { _cli_err "could not obtain random bytes"; exit "$EX_FAIL"; }
    printf '%s\n' "$pw"
    exit 0
}

cli_completion() {
    case "${1:-}" in
        bash) _cli_completion_bash ;;
        zsh)  printf 'autoload -U +X bashcompinit && bashcompinit\n'; _cli_completion_bash ;;
        *)    _cli_usage_error "completion: expected 'bash' or 'zsh'" ;;
    esac
    exit 0
}

_cli_completion_bash() {
    cat <<'EOF'
# encryptor shell completion — load with:  source <(encryptor completion bash)
_encryptor() {
    local cur prev cmd
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    cmd="${COMP_WORDS[1]:-}"
    if [[ $COMP_CWORD -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "encrypt decrypt inspect verify certs audit selftest passgen completion help version" -- "$cur") )
        return
    fi
    case "$prev" in
        -a|--algo) COMPREPLY=( $(compgen -W "aes-256-ctr chacha20 aes-256-cbc camellia-256-cbc aria-256-cbc" -- "$cur") ); return ;;
        --pass-env) COMPREPLY=( $(compgen -v -- "$cur") ); return ;;
        --kdf) COMPREPLY=( $(compgen -W "scrypt pbkdf2 auto" -- "$cur") ); return ;;
        --iter|--legacy-iter|--warn-days) return ;;
    esac
    if [[ "$cur" == -* ]]; then
        case "$cmd" in
            encrypt) COMPREPLY=( $(compgen -W "--output --pass-file --pass-env --pass-stdin --recipient --key --key-pass-file --algo --kdf --iter --force --shred --json --quiet --no-color" -- "$cur") ) ;;
            decrypt|verify) COMPREPLY=( $(compgen -W "--output --pass-file --pass-env --pass-stdin --key --cert --key-pass-file --algo --legacy --legacy-iter --force --json --quiet --no-color" -- "$cur") ) ;;
            inspect|audit) COMPREPLY=( $(compgen -W "--json" -- "$cur") ) ;;
            certs) COMPREPLY=( $(compgen -W "--json --warn-days" -- "$cur") ) ;;
        esac
        return
    fi
    case "$cmd" in
        completion) COMPREPLY=( $(compgen -W "bash zsh" -- "$cur") ) ;;
        *) COMPREPLY=( $(compgen -f -- "$cur") ); compopt -o filenames 2>/dev/null ;;
    esac
}
complete -F _encryptor encryptor
EOF
}

# --- Dispatcher --------------------------------------------------------------
cli_main() {
    local cmd="${1:-}"
    [[ $# -gt 0 ]] && shift
    case "$cmd" in
        encrypt|enc|--encrypt)   cli_encrypt "$@" ;;
        decrypt|dec|--decrypt)   cli_decrypt decrypt "$@" ;;
        verify)                  cli_decrypt verify "$@" ;;
        inspect|info)            cli_inspect "$@" ;;
        audit)                   cli_audit "$@" ;;
        certs)                   cli_certs "$@" ;;
        selftest)                cli_selftest ;;
        passgen)                 cli_passgen "$@" ;;
        completion)              cli_completion "$@" ;;
        help|--help|-h)          cli_help_text; exit 0 ;;
        version|--version|-v|-V) printf 'Encryptor v%s\n' "$ENCRYPTOR_VERSION"; exit 0 ;;
        *)
            _cli_err "unknown command: $cmd"
            printf 'Run "encryptor help" for usage.\n' >&2
            exit "$EX_USAGE" ;;
    esac
}
