#!/usr/bin/env bash
# ==============================================================================
# lib/ui.sh — Terminal UI toolkit: theme, glyphs, panels, key/value rows,
#             arrow-key menus with type-to-filter, file browser, prompts,
#             spinner / progress bar, pager.
#
# Degrades gracefully:
#   * no TTY            → numbered line-mode menus (scriptable, testable)
#   * NO_COLOR / dumb   → no ANSI colors                 (https://no-color.org)
#   * non-UTF-8 locale  → ASCII glyphs
# ==============================================================================

UI_COLOR=0; UI_UNICODE=0; UI_TTY=0; UI_W=78; UI_H=24
UI_ALT_SCREEN=0; UI_CURSOR_HIDDEN=0
_UI_SPINNER_PID=""

# Colors / attributes (empty strings when colors are off).
RESET=""; BOLD=""; DIM=""; UNDERLINE=""; REVERSE=""
C_ACCENT=""; C_OK=""; C_WARN=""; C_ERR=""; C_INFO=""; C_MUTED=""; C_TITLE=""; C_KEY=""
declare -a C_GRADIENT=()

# Glyphs.
G_OK="+"; G_ERR="x"; G_WARN="!"; G_INFO="i"; G_SEL=">"; G_BULLET="*"; G_ARROW="->"
G_H="-"; G_V="|"; G_TL="+"; G_TR="+"; G_BL="+"; G_BR="+"; G_DOT="."; G_UP="^"; G_DOWN="v"
G_BAR_FULL="#"; G_BAR_EMPTY="-"; G_ELLIPSIS="..."; G_CHECK_ON="[x]"; G_CHECK_OFF="[ ]"
declare -a G_SPIN=('|' '/' '-' '\')

# ui_init [force-plain]
ui_init() {
    local plain="${1:-}"
    [[ -t 0 && -t 1 ]] && UI_TTY=1 || UI_TTY=0

    UI_COLOR=0
    if [[ -t 1 && -z "${NO_COLOR:-}" && "${TERM:-dumb}" != "dumb" && -z "$plain" ]]; then UI_COLOR=1; fi
    [[ -n "${ENCRYPTOR_FORCE_COLOR:-}" && -z "$plain" ]] && UI_COLOR=1

    local loc="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    UI_UNICODE=0
    if [[ "${loc,,}" == *utf-8* || "${loc,,}" == *utf8* ]] && [[ -z "${ENCRYPTOR_ASCII:-}" ]]; then UI_UNICODE=1; fi

    if (( UI_COLOR )); then
        RESET=$'\e[0m'; BOLD=$'\e[1m'; DIM=$'\e[2m'; UNDERLINE=$'\e[4m'; REVERSE=$'\e[7m'
        if [[ "${TERM:-}" == *256color* || -n "${COLORTERM:-}" ]]; then
            C_ACCENT=$'\e[38;5;44m'; C_OK=$'\e[38;5;78m'; C_WARN=$'\e[38;5;214m'; C_ERR=$'\e[38;5;203m'
            C_INFO=$'\e[38;5;75m'; C_MUTED=$'\e[38;5;245m'; C_TITLE=$'\e[38;5;231m'; C_KEY=$'\e[38;5;221m'
            C_GRADIENT=($'\e[38;5;48m' $'\e[38;5;49m' $'\e[38;5;50m' $'\e[38;5;51m' $'\e[38;5;45m' $'\e[38;5;39m')
        else
            C_ACCENT=$'\e[36m'; C_OK=$'\e[32m'; C_WARN=$'\e[33m'; C_ERR=$'\e[31m'
            C_INFO=$'\e[34m'; C_MUTED=$'\e[2m'; C_TITLE=$'\e[97m'; C_KEY=$'\e[33m'
            C_GRADIENT=($'\e[32m' $'\e[32m' $'\e[36m' $'\e[36m' $'\e[34m' $'\e[34m')
        fi
    else
        RESET=""; BOLD=""; DIM=""; UNDERLINE=""; REVERSE=""
        C_ACCENT=""; C_OK=""; C_WARN=""; C_ERR=""; C_INFO=""; C_MUTED=""; C_TITLE=""; C_KEY=""
        C_GRADIENT=("" "" "" "" "" "")
    fi

    if (( UI_UNICODE )); then
        G_OK="✓"; G_ERR="✗"; G_WARN="▲"; G_INFO="●"; G_SEL="❯"; G_BULLET="•"; G_ARROW="→"
        G_H="─"; G_V="│"; G_TL="╭"; G_TR="╮"; G_BL="╰"; G_BR="╯"; G_DOT="·"; G_UP="↑"; G_DOWN="↓"
        G_BAR_FULL="█"; G_BAR_EMPTY="░"; G_ELLIPSIS="…"; G_CHECK_ON="◉"; G_CHECK_OFF="○"
        G_SPIN=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    fi
    ui_measure
}

ui_measure() {
    local size cols="" rows=""
    if (( UI_TTY )); then
        size=$(stty size 2>/dev/null </dev/tty) && { rows=${size% *}; cols=${size#* }; }
    fi
    [[ "$cols" =~ ^[0-9]+$ ]] || cols=${COLUMNS:-80}
    [[ "$rows" =~ ^[0-9]+$ ]] || rows=${LINES:-24}
    (( cols < 40 )) && cols=40
    UI_H=$rows
    UI_W=$(( cols - 2 ))
    (( UI_W > 92 )) && UI_W=92
}

# --- Screen management -------------------------------------------------------
ui_screen_enter() {
    (( UI_TTY )) || return 0
    printf '\e[?1049h\e[H\e[2J'
    UI_ALT_SCREEN=1
}
ui_screen_leave() {
    if (( UI_ALT_SCREEN )); then printf '\e[?1049l'; UI_ALT_SCREEN=0; fi
}
ui_clear() { (( UI_TTY )) && printf '\e[H\e[2J\e[3J'; return 0; }
ui_cursor_hide() { if (( UI_TTY )); then printf '\e[?25l'; UI_CURSOR_HIDDEN=1; fi; }
ui_cursor_show() { if (( UI_CURSOR_HIDDEN )); then printf '\e[?25h'; UI_CURSOR_HIDDEN=0; fi; }

# Called from the EXIT trap: always leave the terminal usable.
ui_teardown() {
    ui_spinner_stop
    ui_cursor_show
    ui_screen_leave
    (( UI_COLOR )) && [[ -t 1 ]] && printf '%s' "$RESET"
    return 0
}

# --- Text helpers ------------------------------------------------------------
ui_repeat() {
    local ch="$1" n="$2" out=""
    (( n > 0 )) || return 0
    printf -v out '%*s' "$n" ''
    printf '%s' "${out// /$ch}"
}

# Visible length of a string that may contain SGR color sequences.
ui_vlen() {
    local s="$1"
    while [[ "$s" == *$'\e['* ]]; do
        local pre="${s%%$'\e['*}" rest="${s#*$'\e['}"
        s="${pre}${rest#*m}"
    done
    UI_VLEN=${#s}
}

# Truncate plain text to N columns with an ellipsis.
ui_fit() {
    local s="$1" n="$2"
    if (( ${#s} > n )); then
        if (( n > ${#G_ELLIPSIS} )); then s="${s:0:n-${#G_ELLIPSIS}}${G_ELLIPSIS}"; else s="${s:0:n}"; fi
    fi
    printf '%s' "$s"
}

# Truncate from the left (keeps the end of a path visible).
ui_fit_left() {
    local s="$1" n="$2"
    if (( ${#s} > n )); then
        if (( n > ${#G_ELLIPSIS} )); then s="${G_ELLIPSIS}${s: -$(( n - ${#G_ELLIPSIS} ))}"; else s="${s: -n}"; fi
    fi
    printf '%s' "$s"
}

# Shorten $HOME to ~ for display.
ui_path() { local p="$1"; [[ -n "${HOME:-}" && "$p" == "$HOME"* ]] && p="~${p#"$HOME"}"; printf '%s' "$p"; }

# Path for display: ~ for $HOME, truncated from the left to fit panels.
ui_pathfit() {
    local n="${2:-$(( UI_W - 34 ))}"
    (( n < 16 )) && n=16
    ui_fit_left "$(ui_path "$1")" "$n"
}

ui_rule() { printf '%s%s%s\n' "$C_MUTED" "$(ui_repeat "$G_H" "$UI_W")" "$RESET"; }

# Section title:  ── Title ─────────
ui_title() {
    local t="$1" sub="${2:-}"
    local left="${G_H}${G_H} " n
    n=$(( UI_W - ${#left} - ${#t} - 1 ))
    printf '\n%s%s%s%s%s %s%s%s\n' "$C_ACCENT" "$left" "$BOLD" "$t" "$RESET" "$C_MUTED" "$(ui_repeat "$G_H" "$n")" "$RESET"
    [[ -n "$sub" ]] && printf '%s%s%s\n' "$C_MUTED" "$sub" "$RESET"
    return 0
}

# Breadcrumb for wizards:  Encrypt › File › Method
ui_steps() {
    local current="$1"; shift
    local i=1 out="" s sep=" ${G_SEL} "
    for s in "$@"; do
        if (( i == current )); then out+="${C_ACCENT}${BOLD}${s}${RESET}"
        elif (( i < current )); then out+="${C_OK}${s}${RESET}"
        else out+="${C_MUTED}${s}${RESET}"; fi
        (( i < $# )) && out+="${C_MUTED}${sep}${RESET}"
        (( i++ ))
    done
    printf '  %s\n' "$out"
}

ui_ok()   { printf '  %s%s%s %s\n' "$C_OK"   "$G_OK"   "$RESET" "$*"; }
ui_err()  { printf '  %s%s%s %s\n' "$C_ERR"  "$G_ERR"  "$RESET" "$*"; }
ui_warn() { printf '  %s%s%s %s\n' "$C_WARN" "$G_WARN" "$RESET" "$*"; }
ui_info() { printf '  %s%s%s %s\n' "$C_INFO" "$G_INFO" "$RESET" "$*"; }
ui_note() { printf '  %s%s%s\n' "$C_MUTED" "$*" "$RESET"; }

# Aligned key/value row.
ui_kv() {
    local k="$1" v="$2" w="${3:-16}" pad
    pad=$(( w - ${#k} )); (( pad < 1 )) && pad=1
    printf '  %s%s%s%*s%s\n' "$C_MUTED" "$k" "$RESET" "$pad" '' "$v"
}

# Panel: a titled box around pre-formatted lines.
#   ui_panel "Title" "line 1" "line 2" ...
#   Optional border color via UI_PANEL_COLOR (defaults to the accent color).
UI_PANEL_COLOR=""
ui_panel() {
    local title="$1"; shift
    local col="${UI_PANEL_COLOR:-$C_ACCENT}" inner=$(( UI_W - 4 )) line n
    UI_PANEL_COLOR=""
    n=$(( UI_W - 5 - ${#title} )); (( n < 0 )) && n=0
    printf ' %s%s%s %s%s%s%s %s%s%s\n' "$col" "$G_TL" "$G_H" "$RESET" "$BOLD" "$title" "$RESET" "$col" "$(ui_repeat "$G_H" "$n")$G_TR" "$RESET"
    for line in "$@"; do
        ui_vlen "$line"
        n=$(( inner - UI_VLEN ))
        if (( n < 0 )); then
            # Overlong line: keep the content readable, drop the right border.
            printf ' %s%s%s %s\n' "$col" "$G_V" "$RESET" "$line"
        else
            printf ' %s%s%s %s%*s %s%s%s\n' "$col" "$G_V" "$RESET" "$line" "$n" '' "$col" "$G_V" "$RESET"
        fi
    done
    printf ' %s%s%s%s\n' "$col" "$G_BL" "$(ui_repeat "$G_H" $(( UI_W - 2 )))$G_BR" "$RESET"
}

# Row for use inside ui_panel: "key   value".
ui_row() {
    local k="$1" v="$2" w="${3:-14}" pad
    pad=$(( w - ${#k} )); (( pad < 1 )) && pad=1
    printf '%s%s%s%*s%s' "$C_MUTED" "$k" "$RESET" "$pad" '' "$v"
}

# Horizontal meter:  ui_meter VALUE MAX WIDTH [COLOR]
ui_meter() {
    local v="$1" max="$2" w="${3:-20}" col="${4:-$C_ACCENT}" fill
    (( max <= 0 )) && max=1
    (( v > max )) && v=$max
    (( v < 0 )) && v=0
    fill=$(( v * w / max ))
    printf '%s%s%s%s%s' "$col" "$(ui_repeat "$G_BAR_FULL" "$fill")" "$C_MUTED" "$(ui_repeat "$G_BAR_EMPTY" $(( w - fill )))" "$RESET"
}

# --- Prompts -----------------------------------------------------------------
ui_pause() {
    local msg="${1:-Press Enter to continue}"
    printf '\n  %s%s%s ' "$C_MUTED" "$msg" "$RESET"
    local _; IFS= read -r _ || true
}

# ui_confirm "Question" [y|n]  → 0 = yes
ui_confirm() {
    local q="$1" def="${2:-n}" hint ans
    [[ "$def" == "y" ]] && hint="Y/n" || hint="y/N"
    printf '  %s%s%s %s[%s]%s ' "$BOLD" "$q" "$RESET" "$C_MUTED" "$hint" "$RESET"
    IFS= read -r ans || ans=""
    ans=$(trim "$ans"); ans=${ans,,}
    [[ -z "$ans" ]] && ans="$def"
    [[ "$ans" == "y" || "$ans" == "yes" ]]
}

# ui_prompt "Label" [default] → UI_REPLY (returns 1 on EOF)
UI_REPLY=""
ui_prompt() {
    local label="$1" def="${2:-}" ans
    if [[ -n "$def" ]]; then printf '  %s%s%s %s[%s]%s: ' "$BOLD" "$label" "$RESET" "$C_MUTED" "$def" "$RESET"
    else printf '  %s%s%s: ' "$BOLD" "$label" "$RESET"; fi
    IFS= read -r ans || { UI_REPLY="$def"; echo; return 1; }
    ans=$(trim "$ans")
    UI_REPLY="${ans:-$def}"
}

# Path prompt with readline TAB completion when attached to a terminal.
ui_prompt_path() {
    local label="$1" ans
    if (( UI_TTY )); then
        ui_cursor_show
        IFS= read -e -r -p "  ${label}: " ans || { UI_REPLY=""; return 1; }
    else
        printf '  %s: ' "$label"
        IFS= read -r ans || { UI_REPLY=""; return 1; }
    fi
    ans=$(trim "$ans")
    # Expand a leading ~ (no other expansion is performed on user input).
    [[ "$ans" == "~" ]] && ans="$HOME"
    [[ "$ans" == "~/"* ]] && ans="$HOME/${ans:2}"
    UI_REPLY="$ans"
}

# Secret prompt (no echo). Reads from the terminal when available.
ui_prompt_secret() {
    local label="$1" ans=""
    printf '  %s%s%s: ' "$BOLD" "$label" "$RESET"
    if (( UI_TTY )); then
        IFS= read -rs ans || { echo; UI_REPLY=""; return 1; }
        echo
    else
        IFS= read -r ans || { UI_REPLY=""; return 1; }
    fi
    UI_REPLY="$ans"
}

# --- Keyboard ----------------------------------------------------------------
UI_KEY=""
ui_read_key() {
    local k seq=""
    UI_KEY=""
    IFS= read -rsn1 k || { UI_KEY="EOF"; return 1; }
    case "$k" in
        '') UI_KEY="ENTER" ;;
        $'\e')
            while IFS= read -rsn1 -t 0.03 k; do
                seq+="$k"
                [[ "$seq" == "O" || "$seq" == "[" ]] && continue
                [[ "$k" =~ [A-Za-z~] ]] && break
                (( ${#seq} >= 6 )) && break
            done
            case "$seq" in
                '')            UI_KEY="ESC" ;;
                '[A'|'OA')     UI_KEY="UP" ;;
                '[B'|'OB')     UI_KEY="DOWN" ;;
                '[C'|'OC')     UI_KEY="RIGHT" ;;
                '[D'|'OD')     UI_KEY="LEFT" ;;
                '[5~')         UI_KEY="PGUP" ;;
                '[6~')         UI_KEY="PGDN" ;;
                '[H'|'[1~'|'OH') UI_KEY="HOME" ;;
                '[F'|'[4~'|'OF') UI_KEY="END" ;;
                *)             UI_KEY="OTHER" ;;
            esac ;;
        $'\177'|$'\b') UI_KEY="BACKSPACE" ;;
        $'\t')         UI_KEY="TAB" ;;
        *)             UI_KEY="$k" ;;
    esac
    return 0
}

# --- Select menu -------------------------------------------------------------
# Low-level interface (parallel arrays; labels may contain any character):
#   UI_SEL_KINDS[i]  = item | sep | head
#   UI_SEL_KEYS[i]   = value returned in UI_CHOICE
#   UI_SEL_LABELS[i] = text          UI_SEL_HINTS[i] = dim trailing text
# Options (reset after each call):
#   UI_SEL_HEADER  = text printed above the menu (already formatted)
#   UI_SEL_HOTKEYS = 1 → single-character keys select immediately
#   UI_SEL_FILTER  = 1 → typing filters the list (Esc clears / cancels)
#   UI_SEL_START   = key to pre-select
#   UI_SEL_FOOTER  = extra hint text
# Returns 0 with UI_CHOICE set, 1 on cancel, 2 on end of input.
declare -a UI_SEL_KINDS=() UI_SEL_KEYS=() UI_SEL_LABELS=() UI_SEL_HINTS=()
UI_SEL_HEADER=""; UI_SEL_HOTKEYS=1; UI_SEL_FILTER=0; UI_SEL_START=""; UI_SEL_FOOTER=""
UI_CHOICE=""

ui_sel_reset() {
    UI_SEL_KINDS=(); UI_SEL_KEYS=(); UI_SEL_LABELS=(); UI_SEL_HINTS=()
}
ui_sel_add()  { UI_SEL_KINDS+=(item); UI_SEL_KEYS+=("$1"); UI_SEL_LABELS+=("$2"); UI_SEL_HINTS+=("${3:-}"); }
ui_sel_sep()  { UI_SEL_KINDS+=(sep);  UI_SEL_KEYS+=("");   UI_SEL_LABELS+=("");   UI_SEL_HINTS+=(""); }
ui_sel_head() { UI_SEL_KINDS+=(head); UI_SEL_KEYS+=("");   UI_SEL_LABELS+=("$1"); UI_SEL_HINTS+=(""); }

_ui_sel_finish() {
    UI_SEL_HEADER=""; UI_SEL_HOTKEYS=1; UI_SEL_FILTER=0; UI_SEL_START=""; UI_SEL_FOOTER=""
}

# Convenience wrapper: ui_select "Title" "key|Label|hint" "-" "#Heading" ...
ui_select() {
    local title="$1"; shift
    local it k l h
    ui_sel_reset
    for it in "$@"; do
        case "$it" in
            -)   ui_sel_sep ;;
            \#*) ui_sel_head "${it:1}" ;;
            *)   IFS='|' read -r k l h <<<"$it"; ui_sel_add "$k" "$l" "${h:-}" ;;
        esac
    done
    ui_sel_run "$title"
}

ui_sel_run() {
    local title="$1"
    local total=${#UI_SEL_KINDS[@]} rc
    if (( UI_TTY )); then _ui_sel_tty "$title"; rc=$?
    else _ui_sel_lines "$title"; rc=$?; fi
    _ui_sel_finish
    return $rc
}

# Line mode: numbered list on stdout, answer read from stdin.
_ui_sel_lines() {
    local title="$1" i n=0 ans
    local -a map=()
    [[ -n "$UI_SEL_HEADER" ]] && printf '%s\n' "$UI_SEL_HEADER"
    [[ -n "$title" ]] && printf '\n%s%s%s\n' "$BOLD" "$title" "$RESET"
    for (( i = 0; i < ${#UI_SEL_KINDS[@]}; i++ )); do
        case "${UI_SEL_KINDS[$i]}" in
            sep)  echo ;;
            head) printf '  %s%s%s\n' "$C_MUTED" "${UI_SEL_LABELS[$i]}" "$RESET" ;;
            item)
                (( n++ )); map[n]=$i
                if [[ -n "${UI_SEL_HINTS[$i]}" ]]; then
                    printf '  [%d] %s  %s%s%s\n' "$n" "${UI_SEL_LABELS[$i]}" "$C_MUTED" "${UI_SEL_HINTS[$i]}" "$RESET"
                else
                    printf '  [%d] %s\n' "$n" "${UI_SEL_LABELS[$i]}"
                fi ;;
        esac
    done
    while true; do
        printf '\n%sChoice (number, q to cancel):%s ' "$BOLD" "$RESET"
        IFS= read -r ans || { echo; return 2; }
        ans=$(trim "$ans")
        if [[ "$ans" =~ ^[0-9]+$ ]] && (( ans >= 1 && ans <= n )); then
            UI_CHOICE="${UI_SEL_KEYS[${map[$ans]}]}"; return 0
        fi
        # Also accept an item's key or its exact label (e.g. a file name).
        for (( i = 0; i < ${#UI_SEL_KINDS[@]}; i++ )); do
            if [[ "${UI_SEL_KINDS[$i]}" == item && -n "$ans" ]] &&
               [[ "${UI_SEL_KEYS[$i]}" == "$ans" || "${UI_SEL_LABELS[$i]}" == "$ans" ]]; then
                UI_CHOICE="${UI_SEL_KEYS[$i]}"; return 0
            fi
        done
        [[ "${ans,,}" == "q" ]] && return 1
        printf '%sInvalid choice.%s\n' "$C_ERR" "$RESET"
    done
}

# Full-screen mode: arrow keys, hotkeys, incremental filter, scrolling.
_ui_sel_tty() {
    local title="$1"
    local hotkeys=$UI_SEL_HOTKEYS filtering=$UI_SEL_FILTER header="$UI_SEL_HEADER" footer="$UI_SEL_FOOTER"
    local total=${#UI_SEL_KINDS[@]} i filter="" cur=0 top=0
    local -a vis=()      # indexes of visible entries
    local -a selpos=()   # positions in vis[] that are selectable

    local header_lines=0 tmp="$header"
    if [[ -n "$header" ]]; then
        tmp="${header//[!$'\n']/}"; header_lines=$(( ${#tmp} + 1 ))
    fi

    local labw=0
    for (( i = 0; i < total; i++ )); do
        [[ "${UI_SEL_KINDS[$i]}" == item ]] && (( ${#UI_SEL_LABELS[$i]} > labw )) && labw=${#UI_SEL_LABELS[$i]}
    done
    (( labw > 46 )) && labw=46
    (( labw > UI_W - 12 )) && labw=$(( UI_W - 12 ))

    _ui_sel_rebuild() {
        vis=(); selpos=()
        local j lab f="${filter,,}"
        for (( j = 0; j < total; j++ )); do
            if [[ -n "$f" ]]; then
                [[ "${UI_SEL_KINDS[$j]}" == item ]] || continue
                lab="${UI_SEL_LABELS[$j],,}"
                [[ "${UI_SEL_KEYS[$j]}" == @* || "$lab" == *"$f"* ]] || continue
            fi
            vis+=("$j")
            [[ "${UI_SEL_KINDS[$j]}" == item ]] && selpos+=("$(( ${#vis[@]} - 1 ))")
        done
    }
    _ui_sel_rebuild

    # After filtering, land on the first real match rather than a pinned entry.
    _ui_sel_first_match() {
        local q
        cur=0; top=0
        for (( q = 0; q < ${#selpos[@]}; q++ )); do
            if [[ "${UI_SEL_KEYS[${vis[${selpos[$q]}]}]}" != @* ]]; then cur=$q; return; fi
        done
    }

    # Initial selection.
    local p
    if [[ -n "$UI_SEL_START" ]]; then
        for (( p = 0; p < ${#selpos[@]}; p++ )); do
            [[ "${UI_SEL_KEYS[${vis[${selpos[$p]}]}]}" == "$UI_SEL_START" ]] && cur=$p
        done
    fi

    ui_cursor_hide
    while true; do
        ui_measure
        local room=$(( UI_H - header_lines - 6 ))
        (( filtering )) && room=$(( room - 1 ))
        (( room < 4 )) && room=4
        local nvis=${#vis[@]} nsel=${#selpos[@]}
        (( cur >= nsel )) && cur=$(( nsel - 1 ))
        (( cur < 0 )) && cur=0
        local curpos=-1
        (( nsel > 0 )) && curpos=${selpos[$cur]}
        # Keep the selection inside the window.
        (( curpos >= 0 && curpos < top )) && top=$curpos
        (( curpos >= top + room )) && top=$(( curpos - room + 1 ))
        (( top > nvis - room )) && top=$(( nvis - room ))
        (( top < 0 )) && top=0
        (( curpos >= 0 && curpos - top < 2 && top > 0 )) && { top=$(( curpos - 1 )); (( top < 0 )) && top=0; }

        local frame="" EL=$'\e[K' row idx lab hint key keycol
        [[ -n "$header" ]] && frame+="${header//$'\n'/${EL}$'\n'}${EL}"$'\n'
        frame+="${EL}"$'\n'"  ${BOLD}${title}${RESET}${EL}"$'\n'
        if (( filtering )); then
            if [[ -n "$filter" ]]; then frame+="  ${C_MUTED}filter:${RESET} ${C_KEY}${filter}${RESET}${EL}"$'\n'
            else frame+="  ${C_MUTED}type to filter${RESET}${EL}"$'\n'; fi
        fi
        if (( top > 0 )); then frame+="  ${C_MUTED}${G_UP} more${RESET}${EL}"$'\n'; else frame+="${EL}"$'\n'; fi
        for (( row = top; row < top + room && row < nvis; row++ )); do
            idx=${vis[$row]}
            case "${UI_SEL_KINDS[$idx]}" in
                sep)  frame+="${EL}"$'\n' ;;
                head) frame+="  ${C_MUTED}${UI_SEL_LABELS[$idx]}${RESET}${EL}"$'\n' ;;
                item)
                    lab=$(ui_fit "${UI_SEL_LABELS[$idx]}" "$labw")
                    hint="${UI_SEL_HINTS[$idx]}"
                    key="${UI_SEL_KEYS[$idx]}"
                    keycol=""
                    if (( hotkeys )) && [[ ${#key} -eq 1 ]]; then keycol="${C_MUTED}${key}${RESET} "; elif (( hotkeys )); then keycol="  "; fi
                    local pad=$(( labw - ${#lab} )); (( pad < 0 )) && pad=0
                    local hroom=$(( UI_W - labw - 10 ))
                    (( hroom < 0 )) && hroom=0
                    hint=$(ui_fit "$hint" "$hroom")
                    if (( row == curpos )); then
                        frame+=" ${C_ACCENT}${BOLD}${G_SEL}${RESET} ${keycol}${C_ACCENT}${BOLD}${lab}${RESET}$(printf '%*s' "$pad" '')  ${C_TITLE}${hint}${RESET}${EL}"$'\n'
                    else
                        frame+="   ${keycol}${lab}$(printf '%*s' "$pad" '')  ${C_MUTED}${hint}${RESET}${EL}"$'\n'
                    fi ;;
            esac
        done
        if (( nvis == 0 )); then frame+="  ${C_MUTED}(nothing matches)${RESET}${EL}"$'\n'; fi
        if (( top + room < nvis )); then frame+="  ${C_MUTED}${G_DOWN} more${RESET}${EL}"$'\n'; else frame+="${EL}"$'\n'; fi
        local help="${G_UP}/${G_DOWN} move ${G_DOT} Enter select"
        if (( filtering )); then help+=" ${G_DOT} Esc back"; else help+=" ${G_DOT} q back"; fi
        [[ -n "$footer" ]] && help+=" ${G_DOT} ${footer}"
        frame+="  ${C_MUTED}${help}${RESET}${EL}"
        printf '\e[H%s\e[J' "$frame"

        ui_read_key || { ui_cursor_show; echo; return 2; }
        case "$UI_KEY" in
            UP)    (( cur > 0 )) && (( cur-- )) ;;
            DOWN)  (( cur < nsel - 1 )) && (( cur++ )) ;;
            PGUP)  cur=$(( cur - room + 1 )); (( cur < 0 )) && cur=0 ;;
            PGDN)  cur=$(( cur + room - 1 )); (( cur > nsel - 1 )) && cur=$(( nsel - 1 )) ;;
            HOME)  cur=0 ;;
            END)   cur=$(( nsel - 1 )) ;;
            ENTER|RIGHT)
                if (( nsel > 0 )); then
                    UI_CHOICE="${UI_SEL_KEYS[${vis[${selpos[$cur]}]}]}"
                    ui_cursor_show; printf '\n'; return 0
                fi ;;
            ESC)
                if (( filtering )) && [[ -n "$filter" ]]; then filter=""; _ui_sel_rebuild; cur=0; top=0
                else ui_cursor_show; printf '\n'; return 1; fi ;;
            LEFT)
                if ! (( filtering )) || [[ -z "$filter" ]]; then ui_cursor_show; printf '\n'; return 1; fi ;;
            BACKSPACE)
                if (( filtering )) && [[ -n "$filter" ]]; then filter="${filter%?}"; _ui_sel_rebuild; _ui_sel_first_match; fi ;;
            OTHER|TAB|EOF) ;;
            *)
                if (( filtering )); then
                    if [[ "$UI_KEY" =~ ^[[:print:]]$ ]]; then filter+="$UI_KEY"; _ui_sel_rebuild; _ui_sel_first_match; fi
                else
                    local hit=0
                    if (( hotkeys )); then
                        for (( p = 0; p < nsel; p++ )); do
                            if [[ "${UI_SEL_KEYS[${vis[${selpos[$p]}]}]}" == "$UI_KEY" ]]; then
                                UI_CHOICE="$UI_KEY"; ui_cursor_show; printf '\n'; return 0
                            fi
                        done
                    fi
                    case "$UI_KEY" in
                        j) (( cur < nsel - 1 )) && (( cur++ )); hit=1 ;;
                        k) (( cur > 0 )) && (( cur-- )); hit=1 ;;
                        q|Q) ui_cursor_show; printf '\n'; return 1 ;;
                    esac
                    : "$hit"
                fi ;;
        esac
    done
}

# --- File browser ------------------------------------------------------------
# ui_pick_file "Title" [start-dir] → UI_CHOICE = path; returns 1 on cancel.
# Navigates directories; typing filters; "Type a path" offers TAB completion.
ui_pick_file() {
    local title="$1" dir="${2:-.}" header="${3:-}"
    local entry rc
    while true; do
        local -a dirs=() files=()
        for entry in "$dir"/*; do
            [[ -e "$entry" ]] || continue
            if [[ -d "$entry" ]]; then dirs+=("${entry##*/}"); elif [[ -f "$entry" ]]; then files+=("${entry##*/}"); fi
        done
        # Batch size lookup (one stat call instead of one per file).
        local -a sizes=()
        if (( ${#files[@]} > 0 && ${#files[@]} <= 2000 )); then
            local -a paths=() ; for entry in "${files[@]}"; do paths+=("$dir/$entry"); done
            mapfile -t sizes < <(stat -c%s -- "${paths[@]}" 2>/dev/null || stat -f%z -- "${paths[@]}" 2>/dev/null)
        fi

        ui_sel_reset
        ui_sel_add "@path" "Type a path${G_ELLIPSIS}" "TAB completion"
        ui_sel_add "@up" "../" "parent directory"
        local i
        for entry in "${dirs[@]:-}"; do [[ -n "$entry" ]] && ui_sel_add "d:$entry" "$entry/" "directory"; done
        i=0
        for entry in "${files[@]:-}"; do
            [[ -n "$entry" ]] || continue
            local hint=""
            [[ -n "${sizes[$i]:-}" ]] && hint=$(human_size "${sizes[$i]}")
            case "$entry" in
                *.enc)             hint+="  ${G_DOT} encrypted" ;;
                *.pem|*.crt|*.cer) hint+="  ${G_DOT} certificate" ;;
                *.key)             hint+="  ${G_DOT} private key" ;;
            esac
            ui_sel_add "f:$entry" "$entry" "$hint"
            (( i++ ))
        done

        local shown; shown=$(cd "$dir" 2>/dev/null && pwd)
        UI_SEL_HEADER="${header}"
        UI_SEL_FILTER=1; UI_SEL_HOTKEYS=0
        (( ${#files[@]} > 0 )) && UI_SEL_START="f:${files[0]}"
        local room=$(( UI_W - ${#title} - 6 )); (( room < 12 )) && room=12
        ui_sel_run "${title}  ${C_MUTED}$(ui_fit_left "$(ui_path "${shown:-$dir}")" "$room")${RESET}"; rc=$?
        (( rc != 0 )) && return $rc
        case "$UI_CHOICE" in
            @path)
                ui_clear; [[ -n "$header" ]] && printf '%s\n\n' "$header"
                ui_note "Enter a file or directory path (TAB completes). Empty to go back."
                ui_prompt_path "Path" || return 1
                [[ -z "$UI_REPLY" ]] && continue
                if [[ -d "$UI_REPLY" ]]; then dir="$UI_REPLY"; continue; fi
                if [[ -f "$UI_REPLY" ]]; then UI_CHOICE="$UI_REPLY"; return 0; fi
                ui_err "No such file: $UI_REPLY"; ui_pause ;;
            @up)   dir="$dir/.." ;;
            d:*)   dir="$dir/${UI_CHOICE:2}" ;;
            f:*)
                local picked="$dir/${UI_CHOICE:2}"
                picked="${picked#./}"
                UI_CHOICE="$picked"; return 0 ;;
        esac
    done
}

# --- Spinner / progress ------------------------------------------------------
# ui_spinner_start "Message" [FILE TOTAL_BYTES]
#   With FILE and TOTAL the spinner becomes a progress bar that follows the
#   size of FILE (the in-progress output).
ui_spinner_start() {
    ui_spinner_stop
    (( UI_TTY )) || return 0
    local msg="$1" file="${2:-}" total="${3:-0}"
    ui_cursor_hide
    (
        trap 'exit 0' TERM INT
        i=0; n=${#G_SPIN[@]}
        while true; do
            frame="${G_SPIN[$(( i % n ))]}"
            if [[ -n "$file" && "$total" -gt 0 ]]; then
                cur=$(stat -c%s -- "$file" 2>/dev/null || stat -f%z -- "$file" 2>/dev/null || echo 0)
                (( cur > total )) && cur=$total
                pct=$(( cur * 100 / total ))
                printf '\r  %s%s%s %s %s %3d%%  %s%s%s\e[K' "$C_ACCENT" "$frame" "$RESET" "$msg" \
                    "$(ui_meter "$cur" "$total" 24)" "$pct" "$C_MUTED" "$(human_size "$cur")" "$RESET" >&2
            else
                printf '\r  %s%s%s %s\e[K' "$C_ACCENT" "$frame" "$RESET" "$msg" >&2
            fi
            sleep 0.1
            (( i++ ))
        done
    ) &
    _UI_SPINNER_PID=$!
}

ui_spinner_stop() {
    if [[ -n "$_UI_SPINNER_PID" ]]; then
        # Reap the spinner before clearing its line, so no late frame can appear.
        { kill "$_UI_SPINNER_PID" && wait "$_UI_SPINNER_PID"; } 2>/dev/null || true
        _UI_SPINNER_PID=""
        printf '\r\e[K' >&2
        ui_cursor_show
    fi
    return 0
}

# --- Pager -------------------------------------------------------------------
# Reads stdin; uses less (raw colors, quit-if-one-screen disabled) when present.
ui_pager() {
    if (( UI_TTY )) && have less; then
        less -R 2>/dev/null || true
    else
        cat
    fi
}

# --- Banner ------------------------------------------------------------------
ui_banner() {
    local -a art=(
'    ______                             __'
'   / ____/___  ____________  ______  / /_____  _____'
'  / __/ / __ \/ ___/ ___/ / / / __ \/ __/ __ \/ ___/'
' / /___/ / / / /__/ /  / /_/ / /_/ / /_/ /_/ / /'
'/_____/_/ /_/\___/_/   \__, / .___/\__/\____/_/'
'                      /____/_/'
    )
    local i
    for (( i = 0; i < ${#art[@]}; i++ )); do
        printf '  %s%s%s%s\n' "${C_GRADIENT[$i]:-}" "$BOLD" "${art[$i]}" "$RESET"
    done
}
