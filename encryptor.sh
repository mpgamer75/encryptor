#!/usr/bin/env bash
# ==============================================================================
# ENCRYPTOR — authenticated file encryption and X.509 toolkit (Bash + OpenSSL)
#
# License: MIT  |  https://github.com/mpgamer75/encryptor
#
# Entry point: locates and loads the modules in lib/, then dispatches to the
# interactive UI (no arguments) or the command-line interface.
#
#   lib/core.sh    runtime foundation (exit codes, temp files, traps, logging)
#   lib/ui.sh      terminal UI toolkit
#   lib/crypto.sh  encryption engine (ENCRYPTOR/3 container, legacy readers)
#   lib/certs.sh   X.509 / PKI engine and screens
#   lib/audit.sh   security audit
#   lib/tui.sh     interactive application
#   lib/cli.sh     non-interactive commands
# ==============================================================================

set -uo pipefail

readonly ENCRYPTOR_VERSION="3.0.0"

if [[ -z "${BASH_VERSINFO:-}" ]] || (( BASH_VERSINFO[0] < 4 || ( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] < 4 ) )); then
    printf 'encryptor: Bash 4.4 or newer is required (found %s).\n' "${BASH_VERSION:-unknown}" >&2
    printf 'On macOS: brew install bash\n' >&2
    exit 1
fi

# Everything this program creates (keys, logs, decrypted files, temp files)
# is private to the invoking user unless explicitly relaxed afterwards.
umask 077

# Predictable tool behaviour regardless of the caller's environment.
unset CDPATH GREP_OPTIONS
IFS=$' \t\n'

# --- Locate lib/ -------------------------------------------------------------
# Resolve symlinks so that a link in ~/bin or /usr/local/bin still finds the
# modules. Supported layouts:
#   <dir>/encryptor.sh + <dir>/lib/                 (source checkout)
#   <prefix>/bin/encryptor + <prefix>/lib/encryptor/ (installed)
_enc_self="${BASH_SOURCE[0]}"
while [[ -L "$_enc_self" ]]; do
    _enc_dir="$(cd -P "$(dirname "$_enc_self")" && pwd)"
    _enc_self="$(readlink "$_enc_self")"
    [[ "$_enc_self" != /* ]] && _enc_self="$_enc_dir/$_enc_self"
done
SCRIPT_DIR="$(cd -P "$(dirname "$_enc_self")" && pwd)"
LIB_DIR=""
for _enc_dir in "$SCRIPT_DIR/lib" "$SCRIPT_DIR/../lib/encryptor"; do
    if [[ -f "$_enc_dir/core.sh" ]]; then LIB_DIR="$(cd -P "$_enc_dir" && pwd)"; break; fi
done
if [[ -z "$LIB_DIR" ]]; then
    printf 'encryptor: cannot find the lib/ modules next to %s. Please re-install.\n' "$SCRIPT_DIR" >&2
    exit 1
fi
unset _enc_self _enc_dir

if ! command -v openssl >/dev/null 2>&1; then
    printf 'encryptor: OpenSSL is not installed (required).\n' >&2
    printf 'Install it with your package manager, e.g.: sudo apt install openssl\n' >&2
    exit 1
fi

for _enc_mod in core ui crypto certs audit tui cli; do
    if [[ ! -f "$LIB_DIR/$_enc_mod.sh" ]]; then
        printf 'encryptor: missing module %s/%s.sh. Please re-install.\n' "$LIB_DIR" "$_enc_mod" >&2
        exit 1
    fi
    # shellcheck source=/dev/null
    source "$LIB_DIR/$_enc_mod.sh"
done
unset _enc_mod

core_install_traps

# --- Dispatch ----------------------------------------------------------------
# --no-color may appear anywhere among the options (never after "--", where
# everything is a file name).
_enc_args=(); _enc_opts=1
for _enc_a in "$@"; do
    if (( _enc_opts )) && [[ "$_enc_a" == "--no-color" ]]; then export NO_COLOR=1; continue; fi
    [[ "$_enc_a" == "--" ]] && _enc_opts=0
    _enc_args+=("$_enc_a")
done
set -- "${_enc_args[@]+"${_enc_args[@]}"}"
unset _enc_args _enc_a _enc_opts

ui_init

if [[ $# -eq 0 ]]; then
    if [[ ! -t 0 || ! -t 1 ]] && [[ -z "${ENCRYPTOR_ALLOW_PIPED_UI:-}" ]]; then
        printf 'encryptor: the interactive menu needs a terminal.\n' >&2
        printf 'For scripts use the commands, e.g.: encryptor encrypt --pass-file FILE INPUT   (see: encryptor help)\n' >&2
        exit 2
    fi
    tui_main
    exit 0
fi

cli_main "$@"
