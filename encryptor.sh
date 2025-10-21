#!/bin/bash

# ==============================================================================
# ENCRYPTOR v2.0.0
# Advanced CLI Encryption Tool
# ==============================================================================

# --- Configuration and Constants ---
VERSION="2.0.0"
CONFIG_DIR="$HOME/.config/encryptor"
CERT_DIR="$CONFIG_DIR/certs"
TOOLS_DIR="$CONFIG_DIR/tools"
TESTSSL_PATH="$TOOLS_DIR/testssl.sh/testssl.sh"
TEMP_DIR="/tmp/encryptor_$$"
LOG_FILE="$CONFIG_DIR/encryptor.log"

# Ensure directories exist
mkdir -p "$CONFIG_DIR" "$CERT_DIR" "$TOOLS_DIR" "$TEMP_DIR"
trap 'rm -rf "$TEMP_DIR" 2>/dev/null' EXIT

# ---Colors ---

if command -v tput >/dev/null 2>&1; then
    BOLD=$(tput bold)
    UNDERLINE=$(tput smul)
    RESET=$(tput sgr0)
    # "Matrix" Green
    GREEN=$(tput setaf 2)
    # Electric Blue
    BLUE=$(tput setaf 4)
    # "Alert" Red
    RED=$(tput setaf 1)
    # "Warning" Yellow
    YELLOW=$(tput setaf 3)
    # Cyan for titles
    CYAN=$(tput setaf 6)
    # Magenta for inputs
    MAGENTA=$(tput setaf 5)
    # Bright White
    WHITE=$(tput setaf 7)
    # "Dim" Gray
    DIM=$(tput dim)
else
    # Fallback if tput is not available
    BOLD="\e[1m"
    UNDERLINE="\e[4m"
    RESET="\e[0m"
    GREEN="\e[32m"
    BLUE="\e[34m"
    RED="\e[31m"
    YELLOW="\e[33m"
    CYAN="\e[36m"
    MAGENTA="\e[35m"
    WHITE="\e[97m"
    DIM="\e[2m"
fi

# --- Logging ---
log_operation() {
    local level="$1"
    local message="$2"
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# --- UI Utility Functions ---

# Print main header
print_header() {
    clear
    echo -e "${GREEN}${BOLD}"
    cat << 'EOF'
 ███████╗███╗   ██╗ ██████╗██████╗ ██╗   ██╗██████╗ ████████╗ ██████╗ ██████╗ 
 ██╔════╝████╗  ██║██╔════╝██╔══██╗╚██╗ ██╔╝██╔══██╗╚══██╔══╝██╔═══██╗██╔══██╗
 █████╗  ██╔██╗ ██║██║     ██████╔╝ ╚████╔╝ ██████╔╝   ██║   ██║   ██║██████╔╝
 ██╔══╝  ██║╚██╗██║██║     ██╔══██╗  ╚██╔╝  ██╔═══╝    ██║   ██║   ██║██╔══██╗
 ███████╗██║ ╚████║╚██████╗██║  ██║   ██║   ██║        ██║   ╚██████╔╝██║  ██║
 ╚══════╝╚═╝  ╚═══╝ ╚═════╝╚═╝  ╚═╝   ╚═╝   ╚═╝        ╚═╝    ╚═════╝ ╚═╝  ╚═╝
EOF
    echo -e "${RESET}"
    echo -e "${CYAN}${BOLD}                   Advanced Encryption Tool v$VERSION${RESET}"
    echo -e "${DIM}                        Config: $CONFIG_DIR${RESET}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${RESET}"
}

# Print section header
print_section_header() {
    local title="$1"
    echo -e "\n${CYAN}${BOLD}:: $title ::${RESET}"
    echo -e "${CYAN}───────────────────────────────────────────────────────────────${RESET}"
}

# Prompt user for input
prompt_input() {
    local prompt_text="$1"
    local default_value="$2"
    local input_var
    
    echo -en "${MAGENTA}${BOLD}$prompt_text${RESET}"
    if [[ -n "$default_value" ]]; then
        echo -en " ${DIM}[$default_value]${RESET} "
    fi
    
    read -r input_var
    
    # Trim whitespace
    input_var=$(echo "$input_var" | xargs)
    
    if [[ -z "$input_var" && -n "$default_value" ]]; then
        echo "$default_value"
    else
        echo "$input_var"
    fi
}

# Pause for user to press Enter
press_enter_to_continue() {
    echo -e "\n${DIM}Press [Enter] to continue...${RESET}"
    read -r
}

# --- Simple File Lister ---
list_files_simple() {
    print_section_header "File Explorer"
    echo -e "${DIM}Current directory: $(pwd)${RESET}\n"
    
    local i=0
    local files=()
    local dirs=()
    
    # Separate files and directories
    for item in *; do
        if [[ -d "$item" ]]; then
            dirs+=("$item")
        elif [[ -f "$item" ]]; then
            files+=("$item")
        fi
    done
    
    # Display directories
    echo -e "${BLUE}${BOLD}Directories:${RESET}"
    if [[ ${#dirs[@]} -eq 0 ]]; then
        echo -e "${DIM}  (no directories)${RESET}"
    else
        for dir in "${dirs[@]}"; do
            echo -e "  ${BLUE}📁 ${dir}/${RESET}"
        done
    fi
    
    echo -e "\n${GREEN}${BOLD}Files:${RESET}"
    if [[ ${#files[@]} -eq 0 ]]; then
        echo -e "${DIM}  (no files)${RESET}"
    else
        # Calculate padding
        local max_len=0
        for file in "${files[@]}"; do
            [[ ${#file} -gt $max_len ]] && max_len=${#file}
        done
        
        for file in "${files[@]}"; do
            local icon="📄"
            case "${file##*.}" in
                enc|gpg|pgp) icon="🔒" ;;
                key|pem|crt) icon="🔑" ;;
                zip|tar|gz) icon="📦" ;;
                txt|md) icon="📝" ;;
                png|jpg|gif) icon="🖼️" ;;
                sh|bash|py) icon="💻" ;;
            esac
            
            # Get readable file size
            local size_str=""
            if command -v stat >/dev/null 2>&1; then
                if [[ $(uname) == "Darwin" ]]; then
                    size_str=$(stat -f "%z" "$file" 2>/dev/null) # macOS
                else
                    size_str=$(stat -c "%s" "$file" 2>/dev/null) # Linux
                fi
            fi
            
            if [[ -n "$size_str" ]]; then
                size_str="($(numfmt --to=iec --suffix=B "$size_str" 2>/dev/null || echo "${size_str}B"))"
            fi

            printf "  ${GREEN}%s %-${max_len}s${RESET}  ${DIM}%s${RESET}\n" "$icon" "$file" "$size_str"
        done
    fi
    
    press_enter_to_continue
}

# ---  Assisted File Selection ---
select_file_interactive() {
    local prompt_text="$1"
    local files=()
    local i=1
    
    print_section_header "File Selector"
    
    # Load only files into the array
    for item in *; do
        [[ -f "$item" ]] && files+=("$item")
    done

    if [[ ${#files[@]} -eq 0 ]]; then
        echo -e "${YELLOW}No files found in this directory.${RESET}"
        return 1
    fi
    
    # Display numbered files
    for file in "${files[@]}"; do
        echo -e "  ${YELLOW}${BOLD}[$i]${RESET} $file"
        ((i++))
    done
    
    echo -e "\n${DIM}Type a number, a file name, or 'q' to quit.${RESET}"
    
    while true; do
        echo -en "\n${MAGENTA}${BOLD}$prompt_text${RESET}"
        read -r choice
        choice=$(echo "$choice" | xargs)  # Trim whitespace but keep spaces in filenames
        
        if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
            return 1
        # Check if it's a number
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#files[@]} ]]; then
            echo "${files[$((choice-1))]}"
            return 0
        # Check if the file exists
        elif [[ -f "$choice" ]]; then
            echo "$choice"
            return 0
        else
            echo -e "${RED}Invalid choice or file does not exist. Try again.${RESET}"
            sleep 1
        fi
    done
}

# ---  Algorithm Selection ---

# Structure: "UI Name:openssl_cipher:type:description"
# type: sym (symmetric, password), smime (asymmetric, certificate)
declare -A ALGORITHMS
ALGORITHMS=(
    ["AES-256-GCM"]="aes-256-gcm:sym:AEAD standard. Fast, hardware-accelerated (Recommended)."
    ["ChaCha20-Poly1305"]="chacha20-poly1305:sym:Modern AEAD standard. Excellent performance, no hardware bias."
    ["S/MIME (Certificate)"]="smime:smime:Asymmetric (X.509). Encrypts for a recipient's certificate."
)

select_algorithm_menu() {
    print_section_header "Select Encryption Algorithm"
    echo -e "${DIM}Only modern, secure AEAD (Authenticated Encryption) ciphers are listed.${RESET}"
    
    local i=1
    local options=()
    local descriptions=()
    
    # Sort keys for consistent display
    local sorted_keys
    IFS=$'\n' sorted_keys=($(sort <<<"${!ALGORITHMS[*]}"))
    unset IFS

    for key in "${sorted_keys[@]}"; do
        local value="${ALGORITHMS[$key]}"
        local type=$(echo "$value" | cut -d: -f3)
        local desc=$(echo "$value" | cut -d: -f4)
        
        local type_label="(Symmetric, Password-based)"
        if [[ "$type" == "smime" ]]; then
            type_label="(Asymmetric, Certificate-based)"
        fi
        
        echo -e "\n  ${YELLOW}${BOLD}[$i]${RESET} ${WHITE}${BOLD}$key${RESET}"
        echo -e "      ${DIM}Type: $type_label${RESET}"
        echo -e "      ${DIM}Desc: $desc${RESET}"
        
        options+=("$key")
        ((i++))
    done

    echo -e "\n${DIM}Type a number or 'q' to quit.${RESET}"
    
    while true; do
        echo -en "\n${MAGENTA}${BOLD}Your algorithm choice: ${RESET}"
        read -r choice
        choice=$(echo "$choice" | tr -d '[:space:]')
        
        if [[ "$choice" == "q" || "$choice" == "Q" ]]; then
            return 1
        elif [[ "$choice" =~ ^[0-9]+$ ]] && [[ "$choice" -ge 1 ]] && [[ "$choice" -le ${#options[@]} ]]; then
            local selected_key="${options[$((choice-1))]}"
            # Return the openssl "key" (e.g., aes-256-gcm)
            echo "${ALGORITHMS[$selected_key]}" | cut -d: -f1
            return 0
        else
            echo -e "${RED}Invalid choice. Try again.${RESET}"
            sleep 1
        fi
    done
}

# ---  Encryption Report ---
show_encryption_report() {
    local status="$1"
    local input_file="$2"
    local output_file="$3"
    local algo="$4"
    local key_info="$5"
    local start_time="$6"
    
    local end_time
    end_time=$(date +%s%N)
    local duration_ns=$((end_time - start_time))
    local duration_ms=$((duration_ns / 1000000))

    print_section_header "Encryption Report"
    
    if [[ "$status" == "SUCCESS" ]]; then
        echo -e "${GREEN}${BOLD}            --- OPERATION SUCCESSFUL ---${RESET}"
        log_operation "SUCCESS" "Encryption of $input_file to $output_file"
    else
        echo -e "${RED}${BOLD}            --- OPERATION FAILED ---${RESET}"
        log_operation "ERROR" "Failed encryption of $input_file"
        echo -e "${RED}Error details: $key_info${RESET}" # $key_info contains the error here
        press_enter_to_continue
        return
    fi
    
    echo -e "\n${WHITE}${BOLD}Source File:${RESET}       $input_file"
    echo -e "${WHITE}${BOLD}Encrypted File:${RESET}    ${GREEN}$output_file${RESET}"
    echo -e "${WHITE}${BOLD}Source Size:${RESET}        $(numfmt --to=iec --suffix=B "$(stat -c%s "$input_file" 2>/dev/null || stat -f%z "$input_file")")"
    echo -e "${WHITE}${BOLD}Encrypted Size:${RESET}    $(numfmt --to=iec --suffix=B "$(stat -c%s "$output_file" 2>/dev/null || stat -f%z "$output_file")")"
    
    echo -e "\n${CYAN}---------- Encryption Parameters ----------${RESET}"
    echo -e "${WHITE}${BOLD}Algorithm:${RESET}           $algo"
    echo -e "${WHITE}${BOLD}Mode:${RESET}                (Integrated AEAD)"
    echo -e "${WHITE}${BOLD}Operation Time:${RESET}      ${duration_ms} ms"

    echo -e "\n${YELLOW}---------- Decryption Instructions ----------${RESET}"
    echo -e "${BOLD}To decrypt this file, you will need:${RESET}"
    echo -e " 1. Run ${BOLD}Encryptor${RESET} and choose \"Decrypt File\"."
    echo -e " 2. Select the algorithm: ${BOLD}$algo${RESET}"
    
    case "$algo" in
        aes-256-gcm|chacha20-poly1305)
            echo -e " 3. Provide the exact ${BOLD}password${RESET} used for encryption."
            ;;
        smime)
            echo -e " 3. Provide the recipient's ${BOLD}private key${RESET} and ${BOLD}certificate${RESET}."
            echo -e "    ${DIM}(Certificate used for encryption: $key_info)${RESET}"
            ;;
    esac
    
    press_enter_to_continue
}

# --- Decryption Report ---
show_decryption_report() {
    local status="$1"
    local input_file="$2"
    local output_file="$3"
    local algo="$4"
    local error_msg="$5"
    local start_time="$6"
    
    local end_time
    end_time=$(date +%s%N)
    local duration_ns=$((end_time - start_time))
    local duration_ms=$((duration_ns / 1000000))
    
    print_section_header "Decryption Report"

    if [[ "$status" == "SUCCESS" ]]; then
        echo -e "${GREEN}${BOLD}            --- OPERATION SUCCESSFUL ---${RESET}"
        log_operation "SUCCESS" "Decryption of $input_file to $output_file"
        echo -e "\n${WHITE}${BOLD}Encrypted File:${RESET}    $input_file"
        echo -e "${WHITE}${BOLD}Decrypted File:${RESET}    ${GREEN}$output_file${RESET}"
        echo -e "${WHITE}${BOLD}Encrypted Size:${RESET}    $(numfmt --to=iec --suffix=B "$(stat -c%s "$input_file" 2>/dev/null || stat -f%z "$input_file")")"
        echo -e "${WHITE}${BOLD}Decrypted Size:${RESET}    $(numfmt --to=iec --suffix=B "$(stat -c%s "$output_file" 2>/dev/null || stat -f%z "$output_file")")"
        
        echo -e "\n${CYAN}---------- Parameters Used ----------${RESET}"
        echo -e "${WHITE}${BOLD}Algorithm:${RESET}           $algo"
        echo -e "${WHITE}${BOLD}Mode:${RESET}                (Integrated AEAD)"
        echo -e "${WHITE}${BOLD}Operation Time:${RESET}      ${duration_ms} ms"
        
    else
        echo -e "${RED}${BOLD}            --- OPERATION FAILED ---${RESET}"
        log_operation "ERROR" "Failed decryption of $input_file. Reason: $error_msg"
        echo -e "\n${RED}${BOLD}The operation failed.${RESET}"
        echo -e "${YELLOW}Probable Reason: ${BOLD}$error_msg${RESET}"
        echo -e "\n${DIM}Please check the following:${RESET}"
        echo -e "${DIM}- The password or key is correct.${RESET}"
        echo -e "${DIM}- The algorithm ($algo) is correct.${RESET}"
        echo -e "${DIM}- The file is not corrupted.${RESET}"
    fi

    press_enter_to_continue
}

# --- Encryption Process ---
process_encryption() {
    local file_to_encrypt
    file_to_encrypt=$(select_file_interactive "File to encrypt: ")
    [[ $? -ne 0 ]] && return # User cancelled
    
    local algo
    algo=$(select_algorithm_menu)
    [[ $? -ne 0 ]] && return # User cancelled
    
    # Note: Mode selection is removed as we only use AEAD ciphers
    local mode="(integrated)"
    
    local output_file="$file_to_encrypt.enc"
    local key_info=""
    local cmd_status=0
    local error_msg=""
    
    # Avoid overwriting
    if [[ -f "$output_file" ]]; then
        local new_name
        new_name="${output_file%.enc}-$(date +%s).enc"
        echo -e "${YELLOW}File '$output_file' already exists.${RESET}"
        echo -e "${YELLOW}Using new filename: ${BOLD}$new_name${RESET}"
        output_file="$new_name"
    fi
    
    local start_time
    start_time=$(date +%s%N)
    
    # Handle encryption by type
    case "$algo" in
        aes-256-gcm|chacha20-poly1305)
            local password
            echo -en "${MAGENTA}${BOLD}Enter encryption password: ${RESET}"
            read -rs password
            echo
            echo -en "${MAGENTA}${BOLD}Confirm password: ${RESET}"
            read -rs password_conf
            echo
            
            if [[ "$password" != "$password_conf" ]] || [[ -z "$password" ]]; then
                error_msg="Passwords do not match or are empty."
                cmd_status=1
            else
                # -pbkdf2 -iter 100000 are modern standards
                openssl enc "-$algo" -salt -pbkdf2 -iter 100000 \
                    -in "$file_to_encrypt" -out "$output_file" \
                    -pass "pass:$password" 2> "$TEMP_DIR/openssl.err"
                cmd_status=$?
                [[ $cmd_status -ne 0 ]] && error_msg=$(cat "$TEMP_DIR/openssl.err")
                key_info="[Password Protected]"
            fi
            ;;
            
        "smime")
            echo -e "\n${CYAN}${BOLD}S/MIME Certificate-Based Encryption${RESET}"
            echo -e "${DIM}You need the recipient's certificate (.pem or .crt file)${RESET}\n"
            
            # List available certificates
            if [[ -d "$CERT_DIR" ]] && [[ -n "$(ls -A "$CERT_DIR"/*.pem 2>/dev/null)" ]]; then
                echo -e "${BLUE}Available certificates in $CERT_DIR:${RESET}"
                local cert_num=1
                for cert in "$CERT_DIR"/*.pem; do
                    [[ -f "$cert" ]] && echo -e "  ${YELLOW}[$cert_num]${RESET} $(basename "$cert")"
                    ((cert_num++))
                done
                echo -e "${DIM}Or type the full path to another certificate${RESET}"
            fi
            
            echo -en "\n${MAGENTA}${BOLD}Path to recipient's certificate: ${RESET}"
            read -r cert_file
            cert_file=$(echo "$cert_file" | xargs)
            
            if [[ ! -f "$cert_file" ]]; then
                error_msg="Recipient certificate file not found: $cert_file"
                cmd_status=1
            else
                # S/MIME using AES-256-GCM
                echo -e "${CYAN}Encrypting with S/MIME...${RESET}"
                openssl smime -encrypt -aes256-gcm -in "$file_to_encrypt" -out "$output_file" \
                    -outform PEM "$cert_file" 2> "$TEMP_DIR/openssl.err"
                cmd_status=$?
                [[ $cmd_status -ne 0 ]] && error_msg=$(cat "$TEMP_DIR/openssl.err")
                key_info="$cert_file"
            fi
            ;;
            
        *)
            error_msg="Algorithm not implemented."
            cmd_status=1
            ;;
    esac
    
    if [[ $cmd_status -eq 0 ]]; then
        show_encryption_report "SUCCESS" "$file_to_encrypt" "$output_file" "$algo" "$key_info" "$start_time"
    else
        show_encryption_report "FAILED" "$file_to_encrypt" "$output_file" "$algo" "$error_msg" "$start_time"
    fi
}

# --- Decryption Process ---
process_decryption() {
    # a) File name
    local file_to_decrypt
    file_to_decrypt=$(select_file_interactive "File to decrypt: ")
    [[ $? -ne 0 ]] && return # User cancelled
    
    # b) Questionnaire
    echo -e "${YELLOW}Note:${RESET} Automatic algorithm detection is not possible."
    echo -e "Please provide the parameters used during encryption."
    
    local algo
    algo=$(select_algorithm_menu)
    [[ $? -ne 0 ]] && return # User cancelled
    
    local output_file="${file_to_decrypt%.enc}.dec"
    # Handle non-.enc files
    if [[ "$file_to_decrypt" != *.enc ]]; then
        output_file="$file_to_decrypt.dec"
    fi
    
    local cmd_status=0
    local error_msg=""
    
    # Avoid overwriting
    if [[ -f "$output_file" ]]; then
        local new_name
        new_name="${output_file%.dec}-$(date +%s).dec"
        echo -e "${YELLOW}File '$output_file' already exists.${RESET}"
        echo -e "${YELLOW}Using new filename: ${BOLD}$new_name${RESET}"
        output_file="$new_name"
    fi
    
    local start_time
    start_time=$(date +%s%N)
    
    case "$algo" in
        aes-256-gcm|chacha20-poly1305)
            local password
            echo -en "${MAGENTA}${BOLD}Enter decryption password: ${RESET}"
            read -rs password
            echo
            
            if [[ -z "$password" ]]; then
                error_msg="Password cannot be empty."
                cmd_status=1
            else
                openssl enc "-d" "-$algo" -pbkdf2 -iter 100000 \
                    -in "$file_to_decrypt" -out "$output_file" \
                    -pass "pass:$password" 2> "$TEMP_DIR/openssl.err"
                cmd_status=$?
                [[ $cmd_status -ne 0 ]] && error_msg=$(cat "$TEMP_DIR/openssl.err")
                if [[ -z "$error_msg" ]]; then error_msg="Bad decrypt (wrong password or corrupt file)."; fi
            fi
            ;;
            
        "smime")
            echo -e "\n${CYAN}${BOLD}S/MIME Certificate-Based Decryption${RESET}"
            echo -e "${DIM}You need YOUR private key and certificate${RESET}\n"
            
            # List available keys and certificates
            if [[ -d "$CERT_DIR" ]] && [[ -n "$(ls -A "$CERT_DIR"/*.key 2>/dev/null)" ]]; then
                echo -e "${BLUE}Available keys in $CERT_DIR:${RESET}"
                for key in "$CERT_DIR"/*.key; do
                    [[ -f "$key" ]] && echo -e "  ${YELLOW}→${RESET} $(basename "$key")"
                done
                echo
                echo -e "${BLUE}Available certificates in $CERT_DIR:${RESET}"
                for cert in "$CERT_DIR"/*.pem; do
                    [[ -f "$cert" ]] && echo -e "  ${YELLOW}→${RESET} $(basename "$cert")"
                done
                echo -e "${DIM}You can type the filename or full path${RESET}"
            fi
            
            echo -en "\n${MAGENTA}${BOLD}Path to your private key (.key): ${RESET}"
            read -r priv_key_file
            priv_key_file=$(echo "$priv_key_file" | xargs)
            
            # Auto-complete path if just filename provided
            if [[ ! -f "$priv_key_file" ]] && [[ -f "$CERT_DIR/$priv_key_file" ]]; then
                priv_key_file="$CERT_DIR/$priv_key_file"
            fi
            
            echo -en "${MAGENTA}${BOLD}Path to your certificate (.pem): ${RESET}"
            read -r cert_file
            cert_file=$(echo "$cert_file" | xargs)
            
            # Auto-complete path if just filename provided
            if [[ ! -f "$cert_file" ]] && [[ -f "$CERT_DIR/$cert_file" ]]; then
                cert_file="$CERT_DIR/$cert_file"
            fi
            
            if [[ ! -f "$priv_key_file" ]] || [[ ! -f "$cert_file" ]]; then
                error_msg="Private key or certificate file not found."
                echo -e "${RED}Error: Could not find files${RESET}"
                [[ ! -f "$priv_key_file" ]] && echo -e "${RED}  Private key: $priv_key_file${RESET}"
                [[ ! -f "$cert_file" ]] && echo -e "${RED}  Certificate: $cert_file${RESET}"
                cmd_status=1
            else
                echo -e "${CYAN}Decrypting with S/MIME...${RESET}"
                openssl smime -decrypt -in "$file_to_decrypt" -out "$output_file" \
                    -inform PEM -recip "$cert_file" -inkey "$priv_key_file" 2> "$TEMP_DIR/openssl.err"
                cmd_status=$?
                [[ $cmd_status -ne 0 ]] && error_msg=$(cat "$TEMP_DIR/openssl.err")
                if [[ -z "$error_msg" ]]; then error_msg="Incorrect key/certificate or corrupt file."; fi
            fi
            ;;
            
        *)
            error_msg="Algorithm not implemented."
            cmd_status=1
            ;;
    esac
    
    if [[ $cmd_status -eq 0 ]]; then
        show_decryption_report "SUCCESS" "$file_to_decrypt" "$output_file" "$algo" "" "$start_time"
    else
        # If decryption fails, remove the empty output file
        rm -f "$output_file" 2>/dev/null
        show_decryption_report "FAILED" "$file_to_decrypt" "$output_file" "$algo" "$error_msg" "$start_time"
    fi
}

# --- Certificate Management ---
manage_certificates() {
    while true; do
        print_section_header "Certificate Manager (X.509)"
        echo -e "  ${YELLOW}${BOLD}[1]${RESET} ${WHITE}Create Root Certificate Authority (CA)${RESET}"
        echo -e "  ${YELLOW}${BOLD}[2]${RESET} ${WHITE}Generate Private Key and CSR${RESET}"
        echo -e "  ${YELLOW}${BOLD}[3]${RESET} ${WHITE}Sign Certificate Signing Request (CSR)${RESET}"
        echo -e "  ${YELLOW}${BOLD}[4]${RESET} ${WHITE}Inspect a Certificate or CSR${RESET}"
        echo -e "  ${YELLOW}${BOLD}[5]${RESET} ${WHITE}List managed certificates and keys${RESET}"
        echo -e "  ${YELLOW}${BOLD}[q]${RESET} ${WHITE}Return to Main Menu${RESET}"
        
        echo -en "\n${MAGENTA}${BOLD}Your choice: ${RESET}"
        read -r choice
        choice=$(echo "$choice" | tr -d '[:space:]')

        case "$choice" in
            1) # Create CA
                print_section_header "Create Root Certificate Authority (CA)"
                echo -e "${CYAN}${BOLD}What is a Root CA?${RESET}"
                echo -e "${DIM}A Certificate Authority is used to sign and issue other certificates.${RESET}"
                echo -e "${DIM}This creates a self-signed root certificate for your own PKI.${RESET}\n"
                
                echo -e "${YELLOW}Generated files:${RESET}"
                echo -e "  ${WHITE}→${RESET} CA private key (.key) - ${RED}Keep this secret!${RESET}"
                echo -e "  ${WHITE}→${RESET} CA certificate (.pem) - Can share publicly\n"
                
                echo -en "${MAGENTA}${BOLD}Name for your CA (e.g., MyRootCA) [default: MyRootCA]: ${RESET}"
                read -r ca_name
                ca_name=$(echo "$ca_name" | xargs)
                [[ -z "$ca_name" ]] && ca_name="MyRootCA"
                
                local ca_key="$CERT_DIR/${ca_name}.key"
                local ca_cert="$CERT_DIR/${ca_name}.pem"
                
                if [[ -f "$ca_key" ]] || [[ -f "$ca_cert" ]]; then
                    echo -e "\n${RED}${BOLD}Error:${RESET} Files for CA '$ca_name' already exist!"
                    echo -e "${YELLOW}Existing files:${RESET}"
                    [[ -f "$ca_key" ]] && echo -e "  ${WHITE}→${RESET} $ca_key"
                    [[ -f "$ca_cert" ]] && echo -e "  ${WHITE}→${RESET} $ca_cert"
                    echo -e "\n${DIM}Tip: Choose a different name or delete existing files first${RESET}"
                else
                    echo -e "\n${CYAN}Generating 4096-bit RSA CA (this may take a moment)...${RESET}"
                    openssl req -x509 -newkey rsa:4096 -sha256 -days 3650 \
                        -nodes -keyout "$ca_key" -out "$ca_cert" \
                        -subj "/C=US/ST=California/L=Local/O=Encryptor/OU=CA/CN=$ca_name" 2>/dev/null
                    chmod 400 "$ca_key"
                    
                    echo -e "\n${GREEN}${BOLD}✓ Root CA created successfully!${RESET}\n"
                    echo -e "${WHITE}${BOLD}Files created:${RESET}"
                    echo -e "  ${YELLOW}Private Key:${RESET}  $ca_key ${RED}(Permissions: 400)${RESET}"
                    echo -e "  ${YELLOW}Certificate:${RESET}  $ca_cert ${GREEN}(Valid: 10 years)${RESET}\n"
                    echo -e "${CYAN}${BOLD}Next steps:${RESET}"
                    echo -e "  ${WHITE}→${RESET} Use option ${BOLD}[3]${RESET} to sign certificate requests with this CA"
                    echo -e "  ${WHITE}→${RESET} Keep the .key file ${RED}secure${RESET} - anyone with it can forge certificates!"
                fi
                press_enter_to_continue
                ;;
            2) # Generate Key + CSR
                print_section_header "Generate Private Key and Certificate Request"
                echo -e "${CYAN}${BOLD}What is this?${RESET}"
                echo -e "${DIM}Creates a private key and CSR (Certificate Signing Request).${RESET}"
                echo -e "${DIM}The CSR can then be signed by a CA to get a valid certificate.${RESET}\n"
                
                echo -e "${YELLOW}Generated files:${RESET}"
                echo -e "  ${WHITE}→${RESET} Private key (.key) - ${RED}Keep this secret!${RESET}"
                echo -e "  ${WHITE}→${RESET} Certificate request (.csr) - Send this to CA for signing\n"
                
                echo -en "${MAGENTA}${BOLD}Name for this key (e.g., server1, user_john) [default: my_key]: ${RESET}"
                read -r key_name
                key_name=$(echo "$key_name" | xargs)
                [[ -z "$key_name" ]] && key_name="my_key"
                
                local priv_key="$CERT_DIR/${key_name}.key"
                local csr_file="$CERT_DIR/${key_name}.csr"
                
                if [[ -f "$priv_key" ]]; then
                    echo -e "\n${RED}${BOLD}Error:${RESET} Key '$key_name.key' already exists!"
                    echo -e "${YELLOW}Existing file:${RESET} $priv_key"
                    echo -e "${DIM}Tip: Choose a different name or delete existing file first${RESET}"
                else
                    echo -e "\n${CYAN}Generating 2048-bit RSA key pair...${RESET}"
                    openssl req -new -newkey rsa:2048 -sha256 \
                        -nodes -keyout "$priv_key" -out "$csr_file" \
                        -subj "/C=US/ST=California/L=Local/O=Encryptor/OU=User/CN=$key_name" 2>/dev/null
                    chmod 400 "$priv_key"
                    
                    echo -e "\n${GREEN}${BOLD}✓ Key and CSR created successfully!${RESET}\n"
                    echo -e "${WHITE}${BOLD}Files created:${RESET}"
                    echo -e "  ${YELLOW}Private Key:${RESET}  $priv_key ${RED}(Permissions: 400)${RESET}"
                    echo -e "  ${YELLOW}CSR Request:${RESET}  $csr_file\n"
                    echo -e "${CYAN}${BOLD}Next steps:${RESET}"
                    echo -e "  ${WHITE}→${RESET} Use option ${BOLD}[3]${RESET} to sign this CSR with your CA"
                    echo -e "  ${WHITE}→${RESET} Or send the .csr file to an external CA for signing"
                fi
                press_enter_to_continue
                ;;
            3) # Sign CSR
                print_section_header "Sign Certificate Signing Request with CA"
                echo -e "${CYAN}${BOLD}What does this do?${RESET}"
                echo -e "${DIM}Signs a CSR with your CA to create a valid certificate.${RESET}"
                echo -e "${DIM}You need: CSR file, CA certificate, and CA private key.${RESET}\n"
                
                # List available CSRs
                echo -e "${BLUE}${BOLD}Available CSRs in $CERT_DIR:${RESET}"
                local csr_found=0
                for csr in "$CERT_DIR"/*.csr; do
                    if [[ -f "$csr" ]]; then
                        echo -e "  ${YELLOW}→${RESET} $(basename "$csr")"
                        csr_found=1
                    fi
                done
                [[ $csr_found -eq 0 ]] && echo -e "  ${DIM}(No .csr files found)${RESET}"
                
                echo -en "\n${MAGENTA}${BOLD}Path to CSR file: ${RESET}"
                read -r csr_file
                csr_file=$(echo "$csr_file" | xargs)
                [[ ! -f "$csr_file" ]] && [[ -f "$CERT_DIR/$csr_file" ]] && csr_file="$CERT_DIR/$csr_file"
                
                # List available CA certificates
                echo -e "\n${BLUE}${BOLD}Available CA certificates in $CERT_DIR:${RESET}"
                local ca_found=0
                for ca in "$CERT_DIR"/*.pem; do
                    if [[ -f "$ca" ]]; then
                        echo -e "  ${YELLOW}→${RESET} $(basename "$ca")"
                        ca_found=1
                    fi
                done
                [[ $ca_found -eq 0 ]] && echo -e "  ${DIM}(No .pem files found - create a CA first!)${RESET}"
                
                echo -en "\n${MAGENTA}${BOLD}Path to CA certificate (.pem): ${RESET}"
                read -r ca_cert
                ca_cert=$(echo "$ca_cert" | xargs)
                [[ ! -f "$ca_cert" ]] && [[ -f "$CERT_DIR/$ca_cert" ]] && ca_cert="$CERT_DIR/$ca_cert"
                
                echo -en "${MAGENTA}${BOLD}Path to CA private key (.key): ${RESET}"
                read -r ca_key
                ca_key=$(echo "$ca_key" | xargs)
                [[ ! -f "$ca_key" ]] && [[ -f "$CERT_DIR/$ca_key" ]] && ca_key="$CERT_DIR/$ca_key"
                
                local cert_out="$CERT_DIR/$(basename "${csr_file%.csr}").pem"
                
                if [[ ! -f "$csr_file" ]] || [[ ! -f "$ca_cert" ]] || [[ ! -f "$ca_key" ]]; then
                    echo -e "\n${RED}${BOLD}Error: Required files not found!${RESET}"
                    [[ ! -f "$csr_file" ]] && echo -e "${RED}  CSR file: $csr_file${RESET}"
                    [[ ! -f "$ca_cert" ]] && echo -e "${RED}  CA certificate: $ca_cert${RESET}"
                    [[ ! -f "$ca_key" ]] && echo -e "${RED}  CA private key: $ca_key${RESET}"
                else
                    echo -e "\n${CYAN}Signing certificate (valid for 1 year)...${RESET}"
                    openssl x509 -req -in "$csr_file" -CA "$ca_cert" -CAkey "$ca_key" \
                        -CAcreateserial -out "$cert_out" -days 365 -sha256 2>/dev/null
                    
                    echo -e "\n${GREEN}${BOLD}✓ Certificate signed successfully!${RESET}\n"
                    echo -e "${WHITE}${BOLD}Output file:${RESET}"
                    echo -e "  ${YELLOW}Signed Certificate:${RESET}  $cert_out ${GREEN}(Valid: 1 year)${RESET}\n"
                    echo -e "${CYAN}${BOLD}Next steps:${RESET}"
                    echo -e "  ${WHITE}→${RESET} Use option ${BOLD}[4]${RESET} to inspect the certificate"
                    echo -e "  ${WHITE}→${RESET} Distribute this certificate to users/servers"
                fi
                press_enter_to_continue
                ;;
            4) # Inspect
                print_section_header "Inspect Certificate or CSR"
                echo -e "${CYAN}${BOLD}View detailed information about certificates or CSRs${RESET}\n"
                
                echo -e "${BLUE}${BOLD}Available files in $CERT_DIR:${RESET}"
                echo -e "${YELLOW}Certificates (.pem):${RESET}"
                local has_pem=0
                for cert in "$CERT_DIR"/*.pem; do
                    if [[ -f "$cert" ]]; then
                        echo -e "  ${WHITE}→${RESET} $(basename "$cert")"
                        has_pem=1
                    fi
                done
                [[ $has_pem -eq 0 ]] && echo -e "  ${DIM}(none)${RESET}"
                
                echo -e "\n${YELLOW}Certificate Requests (.csr):${RESET}"
                local has_csr=0
                for csr in "$CERT_DIR"/*.csr; do
                    if [[ -f "$csr" ]]; then
                        echo -e "  ${WHITE}→${RESET} $(basename "$csr")"
                        has_csr=1
                    fi
                done
                [[ $has_csr -eq 0 ]] && echo -e "  ${DIM}(none)${RESET}"
                
                echo -en "\n${MAGENTA}${BOLD}File to inspect (filename or path): ${RESET}"
                read -r file_to_inspect
                file_to_inspect=$(echo "$file_to_inspect" | xargs)
                
                # Auto-complete path
                if [[ ! -f "$file_to_inspect" ]] && [[ -f "$CERT_DIR/$file_to_inspect" ]]; then
                    file_to_inspect="$CERT_DIR/$file_to_inspect"
                fi
                
                if [[ ! -f "$file_to_inspect" ]]; then
                    echo -e "\n${RED}${BOLD}Error:${RESET} File not found: $file_to_inspect"
                    echo -e "${DIM}Tip: You can type just the filename if it's in $CERT_DIR${RESET}"
                elif [[ "$file_to_inspect" == *.csr ]]; then
                    echo -e "\n${CYAN}Displaying CSR details...${RESET}\n"
                    openssl req -in "$file_to_inspect" -noout -text | less
                else
                    echo -e "\n${CYAN}Displaying certificate details...${RESET}\n"
                    openssl x509 -in "$file_to_inspect" -noout -text | less
                fi
                ;;
            5) # List
                print_section_header "Managed Certificates & Keys"
                echo -e "${DIM}Location: $CERT_DIR${RESET}\n"
                
                if [[ ! -d "$CERT_DIR" ]] || [[ -z "$(ls -A "$CERT_DIR" 2>/dev/null)" ]]; then
                    echo -e "${YELLOW}No managed files found yet.${RESET}"
                    echo -e "${DIM}Use options [1] or [2] to create certificates.${RESET}"
                else
                    # CA Certificates
                    echo -e "${GREEN}${BOLD}Root CA Certificates (.pem):${RESET}"
                    local has_ca=0
                    for cert in "$CERT_DIR"/*.pem; do
                        if [[ -f "$cert" ]]; then
                            local size=$(stat -c%s "$cert" 2>/dev/null || stat -f%z "$cert" 2>/dev/null)
                            local size_kb=$((size / 1024))
                            echo -e "  ${YELLOW}→${RESET} $(basename "$cert") ${DIM}(${size_kb}KB)${RESET}"
                            has_ca=1
                        fi
                    done
                    [[ $has_ca -eq 0 ]] && echo -e "  ${DIM}(none)${RESET}"
                    
                    # Private Keys
                    echo -e "\n${RED}${BOLD}Private Keys (.key):${RESET} ${DIM}[Keep these secure!]${RESET}"
                    local has_key=0
                    for key in "$CERT_DIR"/*.key; do
                        if [[ -f "$key" ]]; then
                            local perms=$(stat -c "%a" "$key" 2>/dev/null || stat -f "%Lp" "$key" 2>/dev/null)
                            local perm_status="${GREEN}✓${RESET}"
                            [[ "$perms" != "400" && "$perms" != "600" ]] && perm_status="${RED}⚠${RESET}"
                            echo -e "  ${YELLOW}→${RESET} $(basename "$key") ${DIM}(Perms: $perms) $perm_status${RESET}"
                            has_key=1
                        fi
                    done
                    [[ $has_key -eq 0 ]] && echo -e "  ${DIM}(none)${RESET}"
                    
                    # CSRs
                    echo -e "\n${BLUE}${BOLD}Certificate Requests (.csr):${RESET}"
                    local has_csr=0
                    for csr in "$CERT_DIR"/*.csr; do
                        if [[ -f "$csr" ]]; then
                            echo -e "  ${YELLOW}→${RESET} $(basename "$csr")"
                            has_csr=1
                        fi
                    done
                    [[ $has_csr -eq 0 ]] && echo -e "  ${DIM}(none)${RESET}"
                    
                    # Other files
                    echo -e "\n${CYAN}${BOLD}Other Files:${RESET}"
                    local has_other=0
                    for file in "$CERT_DIR"/*; do
                        if [[ -f "$file" ]] && [[ ! "$file" =~ \.(pem|key|csr)$ ]]; then
                            echo -e "  ${YELLOW}→${RESET} $(basename "$file")"
                            has_other=1
                        fi
                    done
                    [[ $has_other -eq 0 ]] && echo -e "  ${DIM}(none)${RESET}"
                    
                    echo -e "\n${WHITE}${BOLD}Total files:${RESET} $(ls -1 "$CERT_DIR" | wc -l)"
                fi
                press_enter_to_continue
                ;;
            q|Q)
                break
                ;;
            *)
                echo -e "${RED}Invalid choice. Try again.${RESET}"
                sleep 1
                ;;
        esac
    done
}

# --- Security Audit (with testssl) ---

install_testssl() {
    print_section_header "Install testssl.sh"
    if ! command -v git >/dev/null 2>&1; then
        echo -e "${RED}Error: 'git' is required to install testssl.sh.${RESET}"
        echo -e "${YELLOW}Please install git (e.g., ${BOLD}sudo apt install git${RESET}) and try again.${RESET}"
        press_enter_to_continue
        return
    fi
    
    echo -e "${BLUE}Cloning testssl.sh into $TOOLS_DIR/testssl.sh...${RESET}"
    rm -rf "$TOOLS_DIR/testssl.sh" 2>/dev/null
    if git clone --depth 1 https://github.com/drwetter/testssl.sh.git "$TOOLS_DIR/testssl.sh"; then
        echo -e "${GREEN}testssl.sh installed successfully.${RESET}"
    else
        echo -e "${RED}Failed to clone testssl.sh repository.${RESET}"
    fi
    press_enter_to_continue
}

run_testssl() {
    if [[ ! -f "$TESTSSL_PATH" ]]; then
        echo -e "${RED}Error: testssl.sh not found.${RESET}"
        echo -e "${YELLOW}Please install it first using the Security Audit menu.${RESET}"
        press_enter_to_continue
        return
    fi
    
    print_section_header "Run testssl.sh Server Audit"
    local domain
    domain=$(prompt_input "Enter domain/IP to scan (e.g., google.com): ")
    if [[ -z "$domain" ]]; then
        echo -e "${RED}No domain provided.${RESET}"
        return
    fi
    
    echo -e "${CYAN}Starting scan on $domain... (This may take several minutes)${RESET}"
    # Run testssl.sh
    "$TESTSSL_PATH" -p "$domain"
    
    echo -e "${GREEN}Scan complete.${RESET}"
    press_enter_to_continue
}

security_audit_menu() {
    while true; do
        print_section_header "Security Audit Menu"
        echo -e "  ${YELLOW}${BOLD}[1]${RESET} ${WHITE}Run Local System Audit${RESET}"
        echo -e "  ${YELLOW}${BOLD}[2]${RESET} ${WHITE}Run testssl.sh (Server Scan)${RESET}"
        echo -e "  ${YELLOW}${BOLD}[3]${RESET} ${WHITE}Install / Update testssl.sh${RESET}"
        echo -e "  ${YELLOW}${BOLD}[q]${RESET} ${WHITE}Return to Main Menu${RESET}"
        
        echo -en "\n${MAGENTA}${BOLD}Your choice: ${RESET}"
        read -r choice
        choice=$(echo "$choice" | tr -d '[:space:]')

        case "$choice" in
            1)  # Local Audit
                print_section_header "Local System Audit"
                echo -e "${DIM}Checking local security configuration...${RESET}\n"
                local score=0
                
                # 1. OpenSSL Version
                echo -e "${CYAN}${BOLD}1. OpenSSL Check...${RESET}"
                local version
                version=$(openssl version | cut -d' ' -f2)
                echo -e "  ${GREEN}✅ ${BOLD}Installed:${RESET} $version"
                if [[ "$(echo "$version" | cut -d. -f1)" -ge 3 ]] || \
                   [[ "$(echo "$version" | cut -d. -f1)" -eq 1 && "$(echo "$version" | cut -d. -f2)" -eq 1 && "$(echo "$version" | cut -d. -f3 | tr -d 'a-z')" -ge 1 ]]; then
                    echo -e "  ${GREEN}✅ ${BOLD}Status:${RESET} Modern version (1.1.1+ or 3.x.x+)."
                    ((score++))
                else
                    echo -e "  ${YELLOW}⚠️ ${BOLD}Warning:${RESET} Old version. Please consider upgrading OpenSSL."
                fi
                
                # 2. Private Key Permissions
                echo -e "\n${CYAN}${BOLD}2. Private Key Permissions Check...${RESET}"
                if [[ ! -d "$CERT_DIR" ]] || [[ -z "$(ls -A "$CERT_DIR")" ]]; then
                    echo -e "  ${DIM}ℹ️ ${BOLD}Info:${RESET} No managed certificates or keys found.${RESET}"
                else
                    local insecure_keys=0
                    for key in "$CERT_DIR"/*.key; do
                        if [[ -f "$key" ]]; then
                            local perms
                            perms=$(stat -c "%a" "$key" 2>/dev/null || stat -f "%Lp" "$key") # Linux / macOS
                            if [[ "$perms" != "400" && "$perms" != "600" ]]; then
                                echo -e "  ${RED}❌ ${BOLD}Vulnerable:${RESET} $key has weak permissions ($perms). Group/other can read."
                                echo -e "     ${DIM}Fix: ${BOLD}chmod 400 $key${RESET}"
                                ((insecure_keys++))
                            fi
                        fi
                    done
                    
                    if [[ $insecure_keys -eq 0 ]]; then
                        echo -e "  ${GREEN}✅ ${BOLD}Status:${RESET} Private key permissions are secure (400 or 600)."
                        ((score++))
                    fi
                fi
                
                echo -e "\n${GREEN}───────────────────────────────────────────────────────────────${RESET}"
                echo -e "${WHITE}${BOLD}Local Security Score: $score / 2${RESET}"
                press_enter_to_continue
                ;;
            2) run_testssl ;;
            3) install_testssl ;;
            q|Q) break ;;
            *)
                echo -e "${RED}Invalid choice. Try again.${RESET}"
                sleep 1
                ;;
        esac
    done
}


# --- Main Menu ---
main_menu() {
    while true; do
        print_header
        echo -e "  ${YELLOW}${BOLD}[1]${RESET} ${WHITE}List Files${RESET} ${DIM}(Simple ls)${RESET}"
        echo -e "  ${YELLOW}${BOLD}[2]${RESET} ${GREEN}Encrypt a File${RESET}"
        echo -e "  ${YELLOW}${BOLD}[3]${RESET} ${RED}Decrypt a File${RESET}"
        echo -e "\n  ${BLUE}${BOLD}[4]${RESET} ${WHITE}Certificate Manager${RESET} ${DIM}(X.509 / S/MIME)${RESET}"
        echo -e "  ${BLUE}${BOLD}[5]${RESET} ${WHITE}Security Audit${RESET} ${DIM}(Local & testssl.sh)${RESET}"
        echo -e "\n  ${CYAN}${BOLD}[h]${RESET} ${WHITE}Help${RESET}"
        echo -e "  ${CYAN}${BOLD}[l]${RESET} ${WHITE}View Logs${RESET}"
        echo -e "  ${CYAN}${BOLD}[q]${RESET} ${WHITE}Quit${RESET}"
        echo -e "${GREEN}═══════════════════════════════════════════════════════════════════${RESET}"
        
        echo -en "\n${MAGENTA}${BOLD}Your choice: ${RESET}"
        read -r choice
        
        # Trim whitespace and normalize input
        choice=$(echo "$choice" | tr -d '[:space:]')

        case "$choice" in
            1) list_files_simple ;;
            2) process_encryption ;;
            3) process_decryption ;;
            4) manage_certificates ;;
            5) security_audit_menu ;;
            h|H)
                print_section_header "Help"
                echo -e "Use 'man encryptor' in your terminal for detailed help."
                echo -e "The .deb package must be installed for the man page to be available."
                press_enter_to_continue
                ;;
            l|L)
                print_section_header "Logs ($LOG_FILE)"
                if [[ -f "$LOG_FILE" ]]; then
                    less "$LOG_FILE"
                else
                    echo -e "${DIM}(No logs found)${RESET}"
                    press_enter_to_continue
                fi
                ;;
            q|Q)
                echo -e "${GREEN}Shutting down. ${DIM}Cleaning $TEMP_DIR...${RESET}"
                log_operation "INFO" "Encryptor session ended."
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Try again.${RESET}"
                sleep 1
                ;;
        esac
    done
}

# --- Entry Point ---

# Check OpenSSL
if ! command -v openssl >/dev/null 2>&1; then
    echo -e "\e[31m${BOLD}Critical Error:${RESET} OpenSSL is not installed." >&2
    echo -e "Please install it (e.g., ${BOLD}sudo apt install openssl${RESET}) and try again." >&2
    exit 1
fi

# Simple CLI argument handling
if [[ "$1" == "--help" || "$1" == "-h" ]]; then
    echo "Usage: encryptor"
    echo "Launches the interactive user interface."
    echo "For full help, install the .deb package and type: man encryptor"
    exit 0
elif [[ "$1" == "--version" || "$1" == "-v" ]]; then
    echo "Encryptor v$VERSION"
    exit 0
fi

log_operation "INFO" "Encryptor v$VERSION session started."
main_menu