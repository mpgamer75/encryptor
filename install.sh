#!/usr/bin/env bash
# ==============================================================================
# Encryptor installer
#
#   From a checkout:   ./install.sh
#   From the network:  curl -fsSL https://raw.githubusercontent.com/mpgamer75/encryptor/main/install.sh | bash
#
# Options:
#   --prefix DIR      install prefix (same as PREFIX=DIR)
#   --local           install from the directory containing this script
#   --download        always download, even when run from a checkout
#
# Environment:
#   PREFIX            install prefix (default: /usr/local as root, ~/.local otherwise)
#   ENCRYPTOR_REF     release tag, branch or commit to download (default: main).
#                     For a release tag (vX.Y.Z) the release tarball is fetched
#                     and checked against the release's SHA256SUMS.
#   ENCRYPTOR_SHA256  expected SHA-256 of the downloaded tarball. When set, the
#                     download must match it (take it from a source you trust,
#                     e.g. the SHA256SUMS of the release page).
#
# Setting ENCRYPTOR_REF or ENCRYPTOR_SHA256 always forces a verified download.
#
# Layout:  $PREFIX/bin/encryptor
#          $PREFIX/lib/encryptor/*.sh
#          $PREFIX/share/man/man1/encryptor.1
#          $PREFIX/share/bash-completion/completions/encryptor
#
# The installer never edits your shell start-up files and never uses sudo.
# ==============================================================================
set -euo pipefail
umask 022      # installed files must be readable by all users of the prefix

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

Usage: install.sh [--prefix DIR] [--local | --download] [--help]

  --prefix DIR   Install under DIR (same as PREFIX=DIR)
  --local        Install from the directory containing this script
  --download     Always download, even when run from a checkout
  --help         Show this help

Environment: PREFIX, ENCRYPTOR_REF, ENCRYPTOR_SHA256 (see the header of this script).
EOF
}

PREFIX="${PREFIX:-}"
SOURCE_MODE="auto"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix)   [[ $# -ge 2 ]] || die "--prefix requires a directory"; PREFIX="$2"; shift 2 ;;
        --local)    SOURCE_MODE="local"; shift ;;
        --download) SOURCE_MODE="download"; shift ;;
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
# A directory is used as a local source only when it is clearly a checkout the
# invoking user controls: the complete file set is present, and neither the
# directory nor lib/ is owned by someone else, writable by others, or writable
# by a group other than the user's own.
# This keeps "sudo bash /tmp/install.sh" from installing files another user
# planted next to it. When the script is piped from the network there is no
# script path at all. A pinned ref or checksum always forces a download.
SRC=""
WORK=""
cleanup() { [[ -n "$WORK" && -d "$WORK" ]] && rm -rf -- "$WORK"; return 0; }
trap cleanup EXIT

dir_is_private() {      # not modifiable by anyone but the current user (or root)
    local d="$1" owner group mode
    owner=$(stat -c%u -- "$d" 2>/dev/null) || owner=$(stat -f%u -- "$d" 2>/dev/null) || return 1
    group=$(stat -c%g -- "$d" 2>/dev/null) || group=$(stat -f%g -- "$d" 2>/dev/null) || return 1
    mode=$(stat -c%a -- "$d" 2>/dev/null) || mode=$(stat -f%Lp -- "$d" 2>/dev/null) || return 1
    [[ "$owner" == "${EUID:-$(id -u)}" || "$owner" == "0" ]] || return 1
    mode="${mode: -3}"
    # Writable by others: never. Writable by group: only the user's own
    # primary group (the usual result of "umask 002" or of unpacking a tarball).
    case "${mode:2:1}" in 2|3|6|7) return 1 ;; esac
    case "${mode:1:1}" in 2|3|6|7) [[ "$group" == "$(id -g)" ]] || return 1 ;; esac
    return 0
}

has_sources() {
    local d="$1" m
    [[ -f "$d/encryptor.sh" && -f "$d/tests/run.sh" && -f "$d/man/encryptor.1" && -d "$d/lib" ]] || return 1
    for m in "${MODULES[@]}"; do [[ -f "$d/lib/$m.sh" ]] || return 1; done
}
is_checkout() { has_sources "$1" && dir_is_private "$1" && dir_is_private "$1/lib"; }

self="${BASH_SOURCE[0]:-}"
self_dir=""
if [[ -n "$self" && -f "$self" ]]; then self_dir="$(cd -P "$(dirname "$self")" && pwd)"; fi

if [[ -n "${ENCRYPTOR_REF:-}" || -n "${ENCRYPTOR_SHA256:-}" ]]; then
    [[ "$SOURCE_MODE" == "local" ]] && die "--local cannot be combined with ENCRYPTOR_REF / ENCRYPTOR_SHA256"
    SOURCE_MODE="download"
fi
case "$SOURCE_MODE" in
    local)
        [[ -n "$self_dir" ]] && is_checkout "$self_dir" || die "--local: $self_dir is not a complete Encryptor checkout that only you can modify"
        SRC="$self_dir" ;;
    auto)
        if [[ -n "$self_dir" ]] && has_sources "$self_dir"; then
            is_checkout "$self_dir" || die "$self_dir looks like a checkout but is owned by another user or writable by others, so its files cannot be trusted. Fix its permissions (chmod -R go-w), or re-run with --download."
            SRC="$self_dir"
        fi ;;
esac

fetch() {       # fetch URL DEST — HTTPS only, including redirects
    local url="$1" dest="$2"
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL --proto '=https' --proto-redir '=https' --tlsv1.2 "$url" -o "$dest"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --https-only --max-redirect=5 "$url" -O "$dest"
    else
        die "curl or wget is required to download Encryptor"
    fi
}

if [[ -n "$SRC" ]]; then
    ok "Installing from local checkout: $SRC"
else
    [[ "$REF" =~ ^[A-Za-z0-9][A-Za-z0-9._/-]{0,99}$ && "$REF" != *..* ]] || die "invalid ENCRYPTOR_REF: $REF"
    WORK="$(mktemp -d "${TMPDIR:-/tmp}/encryptor-install.XXXXXXXX")"
    expected="${ENCRYPTOR_SHA256:-}"
    if [[ "$REF" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        # A release: fetch the published tarball, the file SHA256SUMS describes.
        asset="encryptor-${REF#v}.tar.gz"
        base="https://github.com/${REPO}/releases/download/${REF}"
        say "Downloading release ${REF}"
        fetch "$base/$asset" "$WORK/src.tar.gz" || die "could not download $base/$asset (is ${REF} a published release?)"
        if [[ -z "$expected" ]]; then
            fetch "$base/SHA256SUMS" "$WORK/SHA256SUMS" || die "could not download $base/SHA256SUMS"
            expected="$(awk -v f="$asset" '$2 == f || $2 == "*" f { print $1; exit }' "$WORK/SHA256SUMS")"
            [[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || die "SHA256SUMS of ${REF} has no entry for $asset"
            warn "Checksum taken from the release itself: this detects corruption, not a compromised release."
            warn "For an independent check pass ENCRYPTOR_SHA256=<value you obtained separately>."
        fi
    else
        url="https://github.com/${REPO}/archive/${REF}.tar.gz"
        say "Downloading ${url}"
        fetch "$url" "$WORK/src.tar.gz" || die "download failed"
    fi
    [[ -s "$WORK/src.tar.gz" ]] || die "downloaded archive is empty"
    actual="$(openssl dgst -sha256 -r "$WORK/src.tar.gz" | awk '{print $1}')"
    if [[ -n "$expected" ]]; then
        [[ "${expected,,}" == "$actual" ]] || die "checksum mismatch: expected ${expected}, got ${actual}"
        ok "Checksum verified (${actual})"
    else
        warn "Unpinned install of '${REF}': integrity relies on HTTPS only. Archive SHA-256: ${actual}"
        warn "For a verified install use a release:  ENCRYPTOR_REF=vX.Y.Z"
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

install -d -m 755 "$BIN_DIR" "$LIB_DIR" 2>/dev/null || die "cannot write to $PREFIX (set PREFIX, or run as a user who can)"
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

if [[ -f "$SRC/man/encryptor.1" ]] && install -d -m 755 "$MAN_DIR" 2>/dev/null; then
    install -m 644 "$SRC/man/encryptor.1" "$MAN_DIR/encryptor.1" && ok "Installed man page"
fi
# Generate the completion script into a temporary file first, so a failure
# never leaves an empty file behind.
comp_tmp="$(mktemp)"
if "$BIN_DIR/encryptor" completion bash > "$comp_tmp" 2>/dev/null && [[ -s "$comp_tmp" ]] &&
   install -d -m 755 "$COMP_DIR" 2>/dev/null && install -m 644 "$comp_tmp" "$COMP_DIR/encryptor"; then
    ok "Installed bash completion"
fi
rm -f -- "$comp_tmp"

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

# An older copy earlier in PATH (2.x installed to /usr/local/bin) would keep
# being run instead of this one.
first="$(command -v encryptor 2>/dev/null || true)"
if [[ -n "$first" && "$first" != "$BIN_DIR/encryptor" ]]; then
    warn "Another encryptor comes first in your PATH: $first"
    warn "Remove it (./uninstall.sh --prefix \"$(dirname "$(dirname "$first")")\") or adjust PATH, otherwise it will run instead of $BIN_DIR/encryptor."
fi
