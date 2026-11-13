#!/usr/bin/env bash
# ==============================================================================
# Encryptor installer
#
#   From a checkout:   ./install.sh
#   From the network:  curl -fsSL https://raw.githubusercontent.com/mpgamer75/encryptor/main/install.sh | bash
#
# Environment:
#   PREFIX            install prefix (default: /usr/local as root, ~/.local otherwise)
#   ENCRYPTOR_REF     git tag / branch / commit to download (default: main).
#                     Pin a release tag for reproducible installs, e.g. v3.0.0
#   ENCRYPTOR_SHA256  expected SHA-256 of the downloaded tarball (optional but
#                     recommended with a pinned ENCRYPTOR_REF)
#
# Layout:  $PREFIX/bin/encryptor
#          $PREFIX/lib/encryptor/*.sh
#          $PREFIX/share/man/man1/encryptor.1
#          $PREFIX/share/bash-completion/completions/encryptor
#
# The installer never edits your shell start-up files and never uses sudo.
# ==============================================================================
set -euo pipefail

REPO="mpgamer75/encryptor"
REF="${ENCRYPTOR_REF:-main}"
MODULES=(core ui crypto certs audit tui cli)

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; C=$'\e[36m'; N=$'\e[0m'
else
    B=""; G=""; Y=""; R=""; C=""; N=""
fi
say()  { printf '%s\n' "$*"; }
ok()   { printf '%s✓%s %s\n' "$G" "$N" "$*"; }
warn() { printf '%s!%s %s\n' "$Y" "$N" "$*" >&2; }
die()  { printf '%serror:%s %s\n' "$R" "$N" "$*" >&2; exit 1; }

usage() {
    cat <<EOF
Encryptor installer

Usage: install.sh [--prefix DIR] [--help]

  --prefix DIR   Install under DIR (same as PREFIX=DIR)
  --help         Show this help

Environment: PREFIX, ENCRYPTOR_REF, ENCRYPTOR_SHA256 (see the header of this script).
EOF
}

PREFIX="${PREFIX:-}"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)   [[ $# -ge 2 ]] || die "--prefix requires a directory"; PREFIX="$2"; shift 2 ;;
        --help|-h)  usage; exit 0 ;;
        *)          die "unknown option: $1 (try --help)" ;;
    esac
done
if [[ -z "$PREFIX" ]]; then
    if [[ ${EUID:-$(id -u)} -eq 0 ]]; then PREFIX="/usr/local"; else PREFIX="${HOME}/.local"; fi
fi

say "${C}${B}Encryptor installer${N}"
say "Prefix: ${B}${PREFIX}${N}"
say

# --- Requirements -------------------------------------------------------------
(( BASH_VERSINFO[0] > 4 || ( BASH_VERSINFO[0] == 4 && BASH_VERSINFO[1] >= 4 ) )) || die "Bash 4.4+ is required (found ${BASH_VERSION}). On macOS: brew install bash"
ok "Bash ${BASH_VERSION}"
command -v openssl >/dev/null 2>&1 || die "OpenSSL is required. Install it with your package manager (e.g. apt install openssl)."
if ! openssl enc -aes-256-ctr -pbkdf2 -iter 1 -md sha256 -pass pass:probe </dev/null >/dev/null 2>&1; then
    die "$(openssl version) does not support PBKDF2 key derivation. OpenSSL 1.1.1 or newer is required (3.x recommended)."
fi
ok "$(openssl version | awk '{print $1, $2}')"
for tool in head tail od tr sed awk mktemp stat; do
    command -v "$tool" >/dev/null 2>&1 || die "required tool not found: $tool"
done

# --- Locate the sources -------------------------------------------------------
# Only a real checkout next to this script is trusted as a local source. When
# the script is piped from the network there is no script path, so files that
# merely happen to exist in the current directory are never installed.
SRC=""
WORK=""
cleanup() { [[ -n "$WORK" && -d "$WORK" ]] && rm -rf -- "$WORK"; return 0; }
trap cleanup EXIT

self="${BASH_SOURCE[0]:-}"
if [[ -n "$self" && -f "$self" ]]; then
    self_dir="$(cd -P "$(dirname "$self")" && pwd)"
    if [[ -f "$self_dir/encryptor.sh" && -f "$self_dir/lib/core.sh" ]]; then SRC="$self_dir"; fi
fi

if [[ -n "$SRC" ]]; then
    ok "Installing from local checkout: $SRC"
else
    WORK="$(mktemp -d "${TMPDIR:-/tmp}/encryptor-install.XXXXXXXX")"
    url="https://github.com/${REPO}/archive/${REF}.tar.gz"
    say "Downloading ${url}"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --proto '=https' --tlsv1.2 "$url" -o "$WORK/src.tar.gz" || die "download failed"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --https-only "$url" -O "$WORK/src.tar.gz" || die "download failed"
    else
        die "curl or wget is required to download Encryptor"
    fi
    [[ -s "$WORK/src.tar.gz" ]] || die "downloaded archive is empty"
    actual="$(openssl dgst -sha256 -r "$WORK/src.tar.gz" | awk '{print $1}')"
    if [[ -n "${ENCRYPTOR_SHA256:-}" ]]; then
        [[ "${ENCRYPTOR_SHA256,,}" == "$actual" ]] || die "checksum mismatch: expected ${ENCRYPTOR_SHA256}, got ${actual}"
        ok "Checksum verified"
    else
        warn "No ENCRYPTOR_SHA256 given: integrity relies on HTTPS only. Archive SHA-256: ${actual}"
    fi
    mkdir -p "$WORK/src"
    tar -xzf "$WORK/src.tar.gz" -C "$WORK/src" --strip-components=1 || die "could not unpack the archive"
    SRC="$WORK/src"
    [[ -f "$SRC/encryptor.sh" && -f "$SRC/lib/core.sh" ]] || die "the archive does not contain Encryptor"
    ok "Downloaded ${REF}"
fi

for m in "${MODULES[@]}"; do
    [[ -f "$SRC/lib/$m.sh" ]] || die "missing module in source: lib/$m.sh"
    bash -n "$SRC/lib/$m.sh" || die "syntax check failed: lib/$m.sh"
done
bash -n "$SRC/encryptor.sh" || die "syntax check failed: encryptor.sh"

# --- Install ------------------------------------------------------------------
BIN_DIR="$PREFIX/bin"
LIB_DIR="$PREFIX/lib/encryptor"
MAN_DIR="$PREFIX/share/man/man1"
COMP_DIR="$PREFIX/share/bash-completion/completions"

mkdir -p "$BIN_DIR" "$LIB_DIR" 2>/dev/null || die "cannot write to $PREFIX (set PREFIX, or run as a user who can)"
[[ -w "$BIN_DIR" && -w "$LIB_DIR" ]] || die "cannot write to $PREFIX (set PREFIX, or run as a user who can)"

# Remove modules from previous versions that no longer exist.
for old in "$LIB_DIR"/*.sh; do
    [[ -f "$old" ]] || continue
    keep=0
    for m in "${MODULES[@]}"; do [[ "$(basename "$old")" == "$m.sh" ]] && keep=1; done
    (( keep )) || rm -f -- "$old"
done
for m in "${MODULES[@]}"; do
    install -m 644 "$SRC/lib/$m.sh" "$LIB_DIR/$m.sh"
done
install -m 755 "$SRC/encryptor.sh" "$BIN_DIR/encryptor"
ok "Installed $BIN_DIR/encryptor and ${#MODULES[@]} modules in $LIB_DIR"

if [[ -f "$SRC/man/encryptor.1" ]] && mkdir -p "$MAN_DIR" 2>/dev/null; then
    install -m 644 "$SRC/man/encryptor.1" "$MAN_DIR/encryptor.1" && ok "Installed man page"
fi
if mkdir -p "$COMP_DIR" 2>/dev/null && "$BIN_DIR/encryptor" completion bash > "$COMP_DIR/encryptor" 2>/dev/null; then
    chmod 644 "$COMP_DIR/encryptor"; ok "Installed bash completion"
fi

# --- Verify -------------------------------------------------------------------
say
if "$BIN_DIR/encryptor" selftest; then :; else
    die "the self-test failed on this system; Encryptor was installed but must not be used until this is resolved"
fi

say
say "${G}${B}Encryptor $("$BIN_DIR/encryptor" version | awk '{print $2}') is installed.${N}"
case ":${PATH}:" in
    *":${BIN_DIR}:"*) say "Run: ${B}encryptor${N}" ;;
    *)
        say "${Y}${BIN_DIR} is not in your PATH.${N} Add this line to your shell profile:"
        say "  ${B}export PATH=\"${BIN_DIR}:\$PATH\"${N}"
        say "or run it directly: ${B}${BIN_DIR}/encryptor${N}" ;;
esac
