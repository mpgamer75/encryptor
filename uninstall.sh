#!/usr/bin/env bash
# ==============================================================================
# Encryptor uninstaller
#
#   ./uninstall.sh [--prefix DIR] [--purge]
#
# Removes the program files installed by install.sh from /usr/local and
# ~/.local (or the given prefix). Your certificates, private keys and log in
# ~/.config/encryptor are kept unless you confirm their removal (or --purge).
# Never uses sudo: run it as the user who installed Encryptor.
# ==============================================================================
set -uo pipefail

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
    B=$'\e[1m'; G=$'\e[32m'; Y=$'\e[33m'; R=$'\e[31m'; N=$'\e[0m'
else
    B=""; G=""; Y=""; R=""; N=""
fi

PREFIXES=()
PURGE=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix) [[ $# -ge 2 ]] || { echo "--prefix requires a directory" >&2; exit 2; }; PREFIXES+=("$2"); shift 2 ;;
        --purge)  PURGE=1; shift ;;
        --help|-h) sed -n '2,12p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) echo "unknown option: $1" >&2; exit 2 ;;
    esac
done
(( ${#PREFIXES[@]} > 0 )) || PREFIXES=("/usr/local" "${HOME}/.local")

CONFIG_DIR="${ENCRYPTOR_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/encryptor}"
removed=0; failed=0

remove() {
    local target="$1"
    [[ -e "$target" ]] || return 0
    if rm -rf -- "$target" 2>/dev/null; then
        printf '%s✓%s removed %s\n' "$G" "$N" "$target"; removed=1
    else
        printf '%s!%s could not remove %s (permission denied — re-run as the installing user)\n' "$Y" "$N" "$target" >&2; failed=1
    fi
}

for prefix in "${PREFIXES[@]}"; do
    remove "$prefix/bin/encryptor"
    remove "$prefix/lib/encryptor"
    remove "$prefix/share/man/man1/encryptor.1"
    remove "$prefix/share/man/man1/encryptor.1.gz"
    remove "$prefix/share/bash-completion/completions/encryptor"
done
(( removed )) || printf '%sNo Encryptor installation found under: %s%s\n' "$Y" "${PREFIXES[*]}" "$N"

if [[ -d "$CONFIG_DIR" ]]; then
    printf '\n%sUser data: %s%s\n' "$B" "$CONFIG_DIR" "$N"
    printf '  certificates and PRIVATE KEYS, the operation log, downloaded tools\n'
    answer="n"
    if (( PURGE )); then
        answer="y"
    elif [[ -t 0 ]]; then
        printf '%sDeleting it permanently destroys your private keys. Files encrypted for them become unreadable.%s\n' "$R" "$N"
        printf 'Type %sDELETE%s to remove it, anything else to keep it: ' "$B" "$N"
        read -r reply
        [[ "$reply" == "DELETE" ]] && answer="y"
    fi
    if [[ "$answer" == "y" ]]; then remove "$CONFIG_DIR"; else printf 'Kept %s\n' "$CONFIG_DIR"; fi
fi

# Stale temporary directories owned by this user (normally none).
find "${TMPDIR:-/tmp}" -maxdepth 1 -type d \( -name 'encryptor.*' -o -name 'encryptor_*' \) -user "$(id -un)" -exec rm -rf -- {} + 2>/dev/null || true

(( failed )) && exit 1
printf '\n%sDone.%s\n' "$G" "$N"
