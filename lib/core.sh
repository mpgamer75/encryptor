#!/usr/bin/env bash
# ==============================================================================
# lib/core.sh — Runtime foundation: constants, exit codes, state directories,
#               temp-file hygiene, signal handling, logging, small utilities.
#
# This module has no UI and performs no work at source time. Directories and
# the temp dir are created lazily so that `--version` / `--help` have no side
# effects on the filesystem.
# ==============================================================================

# --- Exit codes (stable, documented in `encryptor help` and the man page) ---
# shellcheck disable=SC2034  # documented for completeness
readonly EX_OK=0            # success
readonly EX_FAIL=1          # generic failure
readonly EX_USAGE=2         # bad command line
readonly EX_AUTH=3          # wrong password/key, or data failed authentication
readonly EX_NOINPUT=4       # input missing or unreadable
readonly EX_CANTCREAT=5     # output exists (without --force) or cannot be written
readonly EX_UNSUPPORTED=6   # unknown format / algorithm not available
readonly EX_INTERRUPTED=130 # SIGINT

# --- Paths ---
CONFIG_DIR="${ENCRYPTOR_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/encryptor}"
CERT_DIR="$CONFIG_DIR/certs"
TOOLS_DIR="$CONFIG_DIR/tools"
LOG_FILE="$CONFIG_DIR/encryptor.log"
LOG_MAX_BYTES=1048576       # rotate the operation log at 1 MiB
TEMP_DIR=""                 # created on demand by core_tmpdir
_CORE_MAIN_PID="${BASHPID:-}"   # the shell that owns the EXIT trap

# Files that must not survive an abnormal exit (partial outputs).
declare -a _CORE_CLEANUP_FILES=()

# Last error message set by engine functions (crypto/certs) for the caller
# (CLI or TUI) to present. Engine functions never print errors themselves.
ENC_ERR=""

# --- State directory bootstrap (lazy) ---
_CORE_STATE_READY=0
core_init_state() {
    [[ $_CORE_STATE_READY -eq 1 ]] && return 0
    mkdir -p "$CONFIG_DIR" "$CERT_DIR" "$TOOLS_DIR" 2>/dev/null || return 1
    # Private keys and the log live here: owner-only, always.
    chmod 700 "$CONFIG_DIR" "$CERT_DIR" 2>/dev/null || true
    _CORE_STATE_READY=1
}

# --- Private temp directory (lazy, unpredictable name, mode 700) ---
core_tmpdir() {
    if [[ -z "$TEMP_DIR" || ! -d "$TEMP_DIR" ]]; then
        # Must run in the main shell: a directory created inside $(...) or a
        # pipeline stage would be invisible to the EXIT trap and leak.
        if [[ "${BASHPID:-}" != "$_CORE_MAIN_PID" ]]; then
            printf 'encryptor: internal error: temp dir requested from a subshell\n' >&2
            exit "$EX_FAIL"
        fi
        TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/encryptor.XXXXXXXXXX") || {
            printf 'encryptor: cannot create a temporary directory\n' >&2
            exit "$EX_FAIL"
        }
        chmod 700 "$TEMP_DIR" 2>/dev/null || true
    fi
}

# Register / unregister a file to be removed if we exit before finishing it.
core_cleanup_add() { _CORE_CLEANUP_FILES+=("$1"); }
core_cleanup_forget() {
    local target="$1" f
    local -a keep=()
    for f in "${_CORE_CLEANUP_FILES[@]:-}"; do
        [[ -n "$f" && "$f" != "$target" ]] && keep+=("$f")
    done
    _CORE_CLEANUP_FILES=("${keep[@]:-}")
}

# --- Exit / signal handling ---
_core_on_exit() {
    local rc=$?
    # Ignore further signals while cleaning up: a second SIGHUP/SIGTERM (e.g. the
    # terminal closing) must not interrupt the removal of temporary secrets.
    trap - EXIT
    trap '' INT TERM HUP
    local f
    for f in "${_CORE_CLEANUP_FILES[@]:-}"; do
        [[ -n "$f" ]] && rm -f -- "$f" 2>/dev/null
    done
    [[ -n "$TEMP_DIR" && -d "$TEMP_DIR" ]] && rm -rf -- "$TEMP_DIR" 2>/dev/null
    # UI teardown (spinner, cursor, alternate screen) if the UI module is loaded.
    declare -F ui_teardown >/dev/null 2>&1 && ui_teardown 2>/dev/null
    exit "$rc"
}
_core_on_signal() {
    local sig="$1"
    case "$sig" in
        INT) exit "$EX_INTERRUPTED" ;;
        *)   exit 143 ;;
    esac
}
core_install_traps() {
    trap _core_on_exit EXIT
    trap '_core_on_signal INT' INT
    trap '_core_on_signal TERM' TERM
    trap '_core_on_signal HUP' HUP
}

# --- Logging -----------------------------------------------------------------
# Append-only operation log. Records operation type and file names — never
# passwords, keys or content. Control characters are stripped so that a crafted
# file name cannot forge log lines. Set ENCRYPTOR_NO_LOG=1 to disable.
log_operation() {
    [[ "${ENCRYPTOR_NO_LOG:-0}" == "1" ]] && return 0
    core_init_state || return 0
    local level="$1" message="$2" ts
    message=${message//[$'\001'-$'\037'$'\177']/ }
    ts=$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null)

    if [[ ! -e "$LOG_FILE" ]]; then
        ( umask 077; : >> "$LOG_FILE" ) 2>/dev/null || return 0
    fi
    # Size-based rotation (keep one previous generation).
    local sz; sz=$(get_file_size "$LOG_FILE")
    if [[ "$sz" -gt "$LOG_MAX_BYTES" ]]; then
        mv -f -- "$LOG_FILE" "${LOG_FILE}.1" 2>/dev/null
        ( umask 077; : > "$LOG_FILE" ) 2>/dev/null
    fi
    printf '%s [%s] %s\n' "$ts" "$level" "$message" >> "$LOG_FILE" 2>/dev/null
    chmod 600 "$LOG_FILE" 2>/dev/null || true
}

# --- Small utilities ---------------------------------------------------------
have() { command -v "$1" >/dev/null 2>&1; }

# trim VAR_VALUE → prints value without leading/trailing whitespace (pure bash;
# unlike `xargs` it never interprets quotes, backslashes or option-like input).
trim() {
    local s="$1"
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

# File size in bytes (GNU and BSD stat).
get_file_size() {
    local f="$1" s
    s=$(stat -c%s -- "$f" 2>/dev/null) || s=$(stat -f%z -- "$f" 2>/dev/null) || s=0
    printf '%s' "${s:-0}"
}

# Octal permission bits, e.g. 600 (GNU and BSD stat).
get_file_mode() {
    local f="$1" m
    m=$(stat -c%a -- "$f" 2>/dev/null) || m=$(stat -f%Lp -- "$f" 2>/dev/null) || m=""
    printf '%s' "$m"
}

human_size() {
    local bytes="${1:-0}"
    [[ "$bytes" =~ ^[0-9]+$ ]] || bytes=0
    local -a units=(B KiB MiB GiB TiB)
    local i=0 whole=$bytes frac=0
    while (( whole >= 1024 && i < 4 )); do
        frac=$(( (whole % 1024) * 10 / 1024 ))
        whole=$(( whole / 1024 ))
        ((i++))
    done
    if (( i == 0 )); then printf '%d B' "$whole"; else printf '%d.%d %s' "$whole" "$frac" "${units[$i]}"; fi
}

# Milliseconds since the epoch, portable (bash 5 EPOCHREALTIME, GNU date %N,
# or whole seconds as the last resort on BSD date).
now_ms() {
    if [[ -n "${EPOCHREALTIME:-}" ]]; then
        local t="${EPOCHREALTIME/[.,]/}"
        printf '%s' "${t:0:${#t}-3}"
        return
    fi
    local n; n=$(date +%s%N 2>/dev/null)
    if [[ "$n" =~ ^[0-9]{16,}$ ]]; then printf '%s' "$(( n / 1000000 ))"; else printf '%s' "$(( $(date +%s) * 1000 ))"; fi
}

# JSON string escaping (RFC 8259): quotes, backslashes and control characters.
json_escape() {
    local s="$1"
    s=${s//\\/\\\\}
    s=${s//\"/\\\"}
    s=${s//$'\n'/\\n}
    s=${s//$'\r'/\\r}
    s=${s//$'\t'/\\t}
    s=${s//[$'\001'-$'\037']/?}
    printf '%s' "$s"
}

# SHA-256 of a file as lowercase hex, using only openssl.
sha256_file() {
    local out
    out=$(openssl dgst -sha256 -r -- "$1" 2>/dev/null) || return 1
    printf '%s' "${out%% *}"
}

# First N bytes of a file as lowercase hex (binary-safe "magic number" probe).
file_magic_hex() {
    head -c "${2:-16}" -- "$1" 2>/dev/null | od -An -v -tx1 | tr -d ' \n'
}

# Is the string a safe file-name component for objects we create in CERT_DIR?
is_safe_name() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]{0,63}$ ]] && [[ "$1" != *..* ]]; }

# OpenSSL identity: sets OPENSSL_FLAVOR (openssl|libressl|boringssl|unknown),
# OPENSSL_MAJOR, OPENSSL_VERSION_TEXT. Cached.
_CORE_OPENSSL_PROBED=0
OPENSSL_FLAVOR="unknown"; OPENSSL_MAJOR=0; OPENSSL_VERSION_TEXT=""
core_probe_openssl() {
    [[ $_CORE_OPENSSL_PROBED -eq 1 ]] && return 0
    local v; v=$(openssl version 2>/dev/null)
    OPENSSL_VERSION_TEXT=$(awk '{print $1, $2}' <<<"$v")
    case "$v" in
        OpenSSL*)   OPENSSL_FLAVOR="openssl" ;;
        LibreSSL*)  OPENSSL_FLAVOR="libressl" ;;
        BoringSSL*) OPENSSL_FLAVOR="boringssl" ;;
    esac
    local num; num=$(awk '{print $2}' <<<"$v")
    OPENSSL_MAJOR=${num%%.*}
    [[ "$OPENSSL_MAJOR" =~ ^[0-9]+$ ]] || OPENSSL_MAJOR=0
    _CORE_OPENSSL_PROBED=1
}
