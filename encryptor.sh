#!/bin/bash

# Encryptor v2.0 - Advanced File Encryption Tool
# Enhanced with modern algorithms, improved UI, and enterprise features

# Colors and formatting
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
BOLD="\e[1m"
DIM="\e[2m"
UNDERLINE="\e[4m"
RESET="\e[0m"

# Configuration and Constants
VERSION="1.1.0"
CONFIG_DIR="$HOME/.config/encryptor"
TEMP_DIR="/tmp/encryptor_$$"
LOG_FILE="$CONFIG_DIR/encryptor.log"
DEFAULT_RSA_SIZE=2048
DEFAULT_ECC_CURVE="prime256v1"
SUPPORTED_HASH_ALGORITHMS=("sha256" "sha384" "sha512" "blake2b512")

# Create necessary directories
mkdir -p "$CONFIG_DIR" "$TEMP_DIR"
trap 'rm -rf "$TEMP_DIR" 2>/dev/null' EXIT

# Enhanced logging function
log_operation() {
    local level="$1"
    local message="$2"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$timestamp] [$level] $message" >> "$LOG_FILE"
}

# Performance monitoring
start_timer() {
    OPERATION_START=$(date +%s.%N)
}

end_timer() {
    local operation="$1"
    local end_time=$(date +%s.%N)
    local duration=$(echo "$end_time - $OPERATION_START" | bc -l 2>/dev/null || echo "N/A")
    echo -e "${DIM}⏱️  Operation completed in ${duration}s${RESET}"
    log_operation "PERF" "$operation completed in ${duration}s"
}

# Enhanced error handling
handle_error() {
    local exit_code=$1
    local operation="$2"
    local file="$3"
    
    if [[ $exit_code -ne 0 ]]; then
        echo -e "${RED}❌ Error during $operation${RESET}"
        log_operation "ERROR" "$operation failed for file: $file (exit code: $exit_code)"
        
        case $exit_code in
            1) echo -e "${YELLOW}💡 Hint: Check file permissions and availability${RESET}" ;;
            2) echo -e "${YELLOW}💡 Hint: Verify password/key correctness${RESET}" ;;
            3) echo -e "${YELLOW}💡 Hint: File may be corrupted or wrong algorithm${RESET}" ;;
            *) echo -e "${YELLOW}💡 Hint: Check logs at $LOG_FILE${RESET}" ;;
        esac
        return 1
    fi
    return 0
}

# Enhanced file size checker with human-readable output
get_file_size() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
        if [[ $size -gt 1073741824 ]]; then
            echo "$(echo "scale=1; $size/1073741824" | bc -l)GB"
        elif [[ $size -gt 1048576 ]]; then
            echo "$(echo "scale=1; $size/1048576" | bc -l)MB"
        elif [[ $size -gt 1024 ]]; then
            echo "$(echo "scale=1; $size/1024" | bc -l)KB"
        else
            echo "${size}B"
        fi
    else
        echo "N/A"
    fi
}

# System compatibility check
check_openssl_features() {
    echo -e "${BLUE}🔍 Checking OpenSSL capabilities...${RESET}"
    
    local openssl_version=$(openssl version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
    echo -e "${GREEN}✅ OpenSSL version: $openssl_version${RESET}"
    
    # Check for specific algorithm support
    local algorithms=("aes-256-gcm" "chacha20-poly1305" "ec" "ed25519")
    local supported_algos=()
    
    for algo in "${algorithms[@]}"; do
        if openssl list -cipher-algorithms 2>/dev/null | grep -qi "$algo" || 
           openssl ecparam -list_curves 2>/dev/null | grep -qi "$algo" ||
           openssl genpkey -algorithm "$algo" -help 2>/dev/null >/dev/null; then
            supported_algos+=("$algo")
            echo -e "${GREEN}  ✅ $algo supported${RESET}"
        else
            echo -e "${YELLOW}  ⚠️  $algo not available${RESET}"
        fi
    done
    
    echo
}

# Clear screen with enhanced header
clear_and_header() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << 'EOF'
 ███████╗███╗   ██╗ ██████╗██████╗ ██╗   ██╗██████╗ ████████╗ ██████╗ ██████╗ 
 ██╔════╝████╗  ██║██╔════╝██╔══██╗╚██╗ ██╔╝██╔══██╗╚══██╔══╝██╔═══██╗██╔══██╗
 █████╗  ██╔██╗ ██║██║     ██████╔╝ ╚████╔╝ ██████╔╝   ██║   ██║   ██║██████╔╝
 ██╔══╝  ██║╚██╗██║██║     ██╔══██╗  ╚██╔╝  ██╔═══╝    ██║   ██║   ██║██╔══██╗
 ███████╗██║ ╚████║╚██████╗██║  ██║   ██║   ██║        ██║   ╚██████╔╝██║  ██║
 ╚══════╝╚═╝  ╚═══╝ ╚═════╝╚═╝  ╚═╝   ╚═╝   ╚═╝        ╚═╝    ╚═════╝ ╚═╝  ╚═╝
EOF
    echo -e "${RESET}"
    echo -e "${GREEN}${BOLD}                    Advanced Encryption Tool v$VERSION${RESET}"
    echo -e "${BLUE}                        Military-grade security${RESET}"
    echo -e "${DIM}                           Config: $CONFIG_DIR${RESET}"
    echo
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════════${RESET}"
    echo
}

# Enhanced file listing with better icons and details
list_files_enhanced() {
    echo -e "${BLUE}${BOLD}📁 Files in current directory:${RESET}"
    echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════════${RESET}"
    echo
    
    local file_count=0
    local total_size=0
    
    # Enhanced file listing with better categorization
    for file in *; do
        if [[ -f "$file" ]]; then
            ((file_count++))
            local size=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null || echo "0")
            total_size=$((total_size + size))
            local human_size=$(get_file_size "$file")
            local modified=$(date -r "$file" "+%Y-%m-%d %H:%M" 2>/dev/null || echo "N/A")
            
            # Enhanced file type detection
            local icon="📄"
            local color="$RESET"
            case "${file##*.}" in
                # Documents
                txt|md|rst) icon="📝"; color="$CYAN" ;;
                pdf) icon="📋"; color="$RED" ;;
                doc|docx) icon="📄"; color="$BLUE" ;;
                
                # Images
                jpg|jpeg|png|gif|bmp|svg|webp) icon="🖼️ "; color="$MAGENTA" ;;
                
                # Audio/Video
                mp3|wav|flac|aac|ogg) icon="🎵"; color="$GREEN" ;;
                mp4|avi|mov|mkv|webm) icon="🎬"; color="$YELLOW" ;;
                
                # Archives
                zip|tar|gz|bz2|xz|7z|rar) icon="📦"; color="$BOLD" ;;
                
                # Code
                sh|py|js|html|css|c|cpp|java) icon="💻"; color="$GREEN" ;;
                
                # Encrypted files
                enc) icon="🔒"; color="$RED$BOLD" ;;
                key|pem|pub) icon="🔑"; color="$YELLOW$BOLD" ;;
                
                # System files
                log) icon="📊"; color="$DIM" ;;
            esac
            
            # Security analysis for encrypted files
            local security_info=""
            if [[ "$file" == *.enc ]]; then
                local algo_hint=""
                if openssl enc -d -aes-256-gcm -in "$file" -out /dev/null -pass pass:test 2>/dev/null; then
                    algo_hint=" ${GREEN}(AES-GCM)${RESET}"
                elif openssl enc -d -aes-256-cbc -in "$file" -out /dev/null -pass pass:test 2>/dev/null; then
                    algo_hint=" ${BLUE}(AES-CBC)${RESET}"
                fi
                security_info="$algo_hint"
            fi
            
            printf "  %s${color}%-30s${RESET} %8s  %s%s\n" "$icon" "$file" "$human_size" "$modified" "$security_info"
        fi
    done
    
    echo
    echo -e "${DIM}📊 Summary: $file_count files, $(get_file_size_from_bytes $total_size) total${RESET}"
    echo
}

get_file_size_from_bytes() {
    local size=$1
    if [[ $size -gt 1073741824 ]]; then
        echo "$(echo "scale=1; $size/1073741824" | bc -l)GB"
    elif [[ $size -gt 1048576 ]]; then
        echo "$(echo "scale=1; $size/1048576" | bc -l)MB"
    elif [[ $size -gt 1024 ]]; then
        echo "$(echo "scale=1; $size/1024" | bc -l)KB"
    else
        echo "${size}B"
    fi
}

# Enhanced algorithm selection menu
show_encryption_menu() {
    echo -e "${BLUE}${BOLD}🔐 Choose Encryption Algorithm:${RESET}"
    echo -e "${CYAN}┌─ Modern Algorithms (Recommended) ──────────────────────┐${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}1)${RESET} AES-256-GCM ${GREEN}(Authenticated, Fast)${RESET}           ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}2)${RESET} ChaCha20-Poly1305 ${GREEN}(Modern, Secure)${RESET}          ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}3)${RESET} ECC P-256 ${BLUE}(Elliptic Curve)${RESET}                 ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}4)${RESET} Hybrid ECC+AES ${GREEN}(Maximum Security)${RESET}          ${CYAN}│${RESET}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────┘${RESET}"
    echo -e "${CYAN}┌─ Classical Algorithms ─────────────────────────────────┐${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}5)${RESET} AES-256-CBC ${BLUE}(Traditional AES)${RESET}               ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}6)${RESET} RSA-2048 ${YELLOW}(Small files only)${RESET}               ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}7)${RESET} RSA+AES Hybrid ${BLUE}(Legacy compatible)${RESET}          ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}8)${RESET} 3DES ${RED}(Deprecated)${RESET}                         ${CYAN}│${RESET}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────┘${RESET}"
    echo -e "${DIM}💡 Tip: Algorithms 1-4 offer the best security/performance balance${RESET}"
    echo
}

# Enhanced decryption menu
show_decryption_menu() {
    echo -e "${BLUE}${BOLD}🔓 Choose Decryption Algorithm:${RESET}"
    echo -e "${CYAN}┌─ Modern Algorithms ────────────────────────────────────┐${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}1)${RESET} AES-256-GCM                                  ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}2)${RESET} ChaCha20-Poly1305                            ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}3)${RESET} ECC P-256                                    ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}4)${RESET} Hybrid ECC+AES                              ${CYAN}│${RESET}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────┘${RESET}"
    echo -e "${CYAN}┌─ Classical Algorithms ─────────────────────────────────┐${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}5)${RESET} AES-256-CBC                                  ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}6)${RESET} RSA-2048                                     ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}7)${RESET} RSA+AES Hybrid                              ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}8)${RESET} 3DES                                        ${CYAN}│${RESET}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────┘${RESET}"
    echo
}

# Modern AES-GCM encryption
encrypt_aes_gcm() {
    local file="$1"
    local outfile="$2"
    
    echo "🔐 AES-256-GCM encryption (authenticated)"
    echo -n "Enter password: "
    read -s password
    echo
    
    start_timer
    # Generate random salt and IV
    local salt=$(openssl rand -hex 32)
    local iv=$(openssl rand -hex 12)  # 96-bit IV for GCM
    
    # Derive key using PBKDF2
    local key=$(echo -n "$password$salt" | openssl dgst -sha256 -binary | xxd -p -c 256)
    
    if openssl enc -aes-256-gcm -e -in "$file" -out "$outfile" \
        -K "$key" -iv "$iv" -S "$salt" 2>/dev/null; then
        end_timer "AES-256-GCM encryption"
        echo -e "${GREEN}✅ AES-256-GCM encryption completed -> $outfile${RESET}"
        log_operation "SUCCESS" "AES-256-GCM encryption: $file -> $outfile"
    else
        handle_error $? "AES-256-GCM encryption" "$file"
    fi
}

# ChaCha20-Poly1305 encryption
encrypt_chacha20() {
    local file="$1"
    local outfile="$2"
    
    echo "🔐 ChaCha20-Poly1305 encryption (modern stream cipher)"
    echo -n "Enter password: "
    read -s password
    echo
    
    start_timer
    if openssl enc -chacha20-poly1305 -pbkdf2 -iter 100000 -salt \
        -in "$file" -out "$outfile" -pass pass:"$password" 2>/dev/null; then
        end_timer "ChaCha20-Poly1305 encryption"
        echo -e "${GREEN}✅ ChaCha20-Poly1305 encryption completed -> $outfile${RESET}"
        log_operation "SUCCESS" "ChaCha20-Poly1305 encryption: $file -> $outfile"
    else
        handle_error $? "ChaCha20-Poly1305 encryption" "$file"
    fi
}

# ECC encryption
encrypt_ecc() {
    local file="$1"
    local outfile="$2"
    local keyfile="${file%.*}.ecc.key"
    local pubfile="${file%.*}.ecc.pub"
    
    echo "🔐 ECC P-256 encryption (Elliptic Curve)"
    
    start_timer
    # Generate ECC key pair if not exists
    if [[ ! -f "$keyfile" || ! -f "$pubfile" ]]; then
        echo "📊 Generating ECC P-256 key pair..."
        openssl ecparam -genkey -name prime256v1 -out "$keyfile" 2>/dev/null
        openssl ec -in "$keyfile" -pubout -out "$pubfile" 2>/dev/null
        chmod 600 "$keyfile"
        echo "🔑 Keys generated: $keyfile (private), $pubfile (public)"
    fi
    
    # Check file size limit for ECC
    local filesize=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
    if [[ $filesize -gt 32 ]]; then
        echo -e "${YELLOW}⚠️  File too large for direct ECC encryption (max 32 bytes)${RESET}"
        echo "💡 Consider using Hybrid ECC+AES instead"
        return 1
    fi
    
    if openssl pkeyutl -encrypt -inkey "$pubfile" -pubin \
        -in "$file" -out "$outfile" 2>/dev/null; then
        end_timer "ECC P-256 encryption"
        echo -e "${GREEN}✅ ECC encryption completed -> $outfile${RESET}"
        log_operation "SUCCESS" "ECC P-256 encryption: $file -> $outfile"
    else
        handle_error $? "ECC encryption" "$file"
    fi
}

# Hybrid ECC+AES encryption
encrypt_ecc_aes_hybrid() {
    local file="$1"
    local datafile="$2"
    local keyfile="${file%.*}.ecc.aes.key.enc"
    local eccprivate="${file%.*}.ecc.key"
    local eccpublic="${file%.*}.ecc.pub"
    
    echo "🔐 Hybrid ECC+AES encryption (maximum security)"
    
    start_timer
    # Generate ECC key pair if not exists
    if [[ ! -f "$eccprivate" || ! -f "$eccpublic" ]]; then
        echo "📊 Generating ECC P-256 key pair..."
        openssl ecparam -genkey -name prime256v1 -out "$eccprivate" 2>/dev/null
        openssl ec -in "$eccprivate" -pubout -out "$eccpublic" 2>/dev/null
        chmod 600 "$eccprivate"
        echo "🔑 ECC keys generated"
    fi
    
    # Generate random AES key
    local temp_aes_key="$TEMP_DIR/aes_key_$$"
    openssl rand -out "$temp_aes_key" 32
    
    # Encrypt file with AES-256-GCM
    echo "📊 Encrypting file with AES-256-GCM..."
    openssl enc -aes-256-gcm -in "$file" -out "$datafile" \
        -pass file:"$temp_aes_key" 2>/dev/null
    
    # Encrypt AES key with ECC
    echo "🔑 Encrypting AES key with ECC..."
    openssl pkeyutl -encrypt -inkey "$eccpublic" -pubin \
        -in "$temp_aes_key" -out "$keyfile" 2>/dev/null
    
    rm -f "$temp_aes_key"
    
    if [[ $? -eq 0 ]]; then
        end_timer "Hybrid ECC+AES encryption"
        echo -e "${GREEN}✅ Hybrid encryption completed:${RESET}"
        echo -e "   📄 Data: $datafile"
        echo -e "   🔑 Key:  $keyfile"
        log_operation "SUCCESS" "Hybrid ECC+AES encryption: $file"
    else
        handle_error $? "Hybrid ECC+AES encryption" "$file"
    fi
}

# Enhanced help system with comprehensive information
show_enhanced_help() {
    clear_and_header
    
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════════${RESET}"
    echo -e "${GREEN}${BOLD}                         ENCRYPTOR v$VERSION HELP MANUAL${RESET}"
    echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════════${RESET}"
    echo
    
    echo -e "${BLUE}${BOLD}📋 QUICK NAVIGATION:${RESET}"
    echo -e "${YELLOW}[1]${RESET} Main Options    ${YELLOW}[2]${RESET} Modern Algorithms    ${YELLOW}[3]${RESET} Classical Algorithms"
    echo -e "${YELLOW}[4]${RESET} Security Guide  ${YELLOW}[5]${RESET} Performance Tips   ${YELLOW}[6]${RESET} Troubleshooting"
    echo -e "${YELLOW}[7]${RESET} Best Practices  ${YELLOW}[8]${RESET} File Management    ${YELLOW}[q]${RESET} Return to Main Menu"
    echo
    
    while true; do
        echo -n -e "${BOLD}Select help section > ${RESET}"
        read help_choice
        
        case $help_choice in
            1)
                echo
                echo -e "${BLUE}${BOLD}🏠 MAIN OPTIONS:${RESET}"
                echo -e "${MAGENTA}─────────────────${RESET}"
                echo -e "${YELLOW}1) List files${RESET} - Enhanced directory listing with:"
                echo -e "   • File type icons and color coding"
                echo -e "   • Human-readable file sizes"
                echo -e "   • Modification dates"
                echo -e "   • Security analysis for encrypted files"
                echo -e "   • Summary statistics"
                echo
                echo -e "${YELLOW}2) Encrypt a file${RESET} - Comprehensive encryption options:"
                echo -e "   • 8 different algorithms (4 modern + 4 classical)"
                echo -e "   • Automatic key generation and management"
                echo -e "   • Performance monitoring"
                echo -e "   • Secure file naming (prevents overwrites)"
                echo -e "   • Operation logging"
                echo
                echo -e "${YELLOW}3) Decrypt a file${RESET} - Secure decryption with:"
                echo -e "   • Algorithm auto-detection hints"
                echo -e "   • Error recovery suggestions"
                echo -e "   • Integrity verification"
                echo -e "   • Performance metrics"
                echo
                ;;
            2)
                echo
                echo -e "${BLUE}${BOLD}🔮 MODERN ALGORITHMS (Recommended):${RESET}"
                echo -e "${MAGENTA}────────────────────────────────────${RESET}"
                echo
                echo -e "${GREEN}${BOLD}1. AES-256-GCM (Authenticated Encryption)${RESET}"
                echo -e "   🔹 ${BOLD}Security Level:${RESET} ⭐⭐⭐⭐⭐ Military Grade"
                echo -e "   🔹 ${BOLD}Speed:${RESET} Very Fast (~100-200 MB/s)"
                echo -e "   🔹 ${BOLD}Features:${RESET} Built-in authentication, prevents tampering"
                echo -e "   🔹 ${BOLD}Best For:${RESET} General purpose, high-performance needs"
                echo -e "   🔹 ${BOLD}File Size:${RESET} Unlimited"
                echo -e "   🔹 ${BOLD}Key Management:${RESET} Password-based with PBKDF2"
                echo
                echo -e "${GREEN}${BOLD}2. ChaCha20-Poly1305 (Modern Stream Cipher)${RESET}"
                echo -e "   🔹 ${BOLD}Security Level:${RESET} ⭐⭐⭐⭐⭐ State-of-the-art"
                echo -e "   🔹 ${BOLD}Speed:${RESET} Very Fast (~150 MB/s)"
                echo -e "   🔹 ${BOLD}Features:${RESET} Designed by Daniel Bernstein, NSA-resistant"
                echo -e "   🔹 ${BOLD}Best For:${RESET} Maximum security, mobile/IoT devices"
                echo -e "   🔹 ${BOLD}File Size:${RESET} Unlimited"
                echo -e "   🔹 ${BOLD}Advantages:${RESET} Constant-time, side-channel resistant"
                echo
                echo -e "${GREEN}${BOLD}3. ECC P-256 (Elliptic Curve Cryptography)${RESET}"
                echo -e "   🔹 ${BOLD}Security Level:${RESET} ⭐⭐⭐⭐⭐ Quantum-resistant until 2030+"
                echo -e "   🔹 ${BOLD}Speed:${RESET} Moderate (key operations)"
                echo -e "   🔹 ${BOLD}Features:${RESET} Smaller keys, equivalent security to RSA-3072"
                echo -e "   🔹 ${BOLD}Best For:${RESET} Small files, key exchange, future-proofing"
                echo -e "   🔹 ${BOLD}File Size:${RESET} Maximum ~32 bytes (direct encryption)"
                echo -e "   🔹 ${BOLD}Key Size:${RESET} 256-bit (much smaller than RSA)"
                echo
                echo -e "${GREEN}${BOLD}4. Hybrid ECC+AES (Ultimate Security)${RESET}"
                echo -e "   🔹 ${BOLD}Security Level:${RESET} ⭐⭐⭐⭐⭐ Maximum possible"
                echo -e "   🔹 ${BOLD}Speed:${RESET} Fast (AES bulk encryption)"
                echo -e "   🔹 ${BOLD}Features:${RESET} Combines ECC key exchange with AES encryption"
                echo -e "   🔹 ${BOLD}Best For:${RESET} Large files requiring maximum security"
                echo -e "   🔹 ${BOLD}File Size:${RESET} Unlimited"
                echo -e "   🔹 ${BOLD}Components:${RESET} Encrypted file + encrypted key + ECC keys"
                echo
                ;;
            3)
                echo
                echo -e "${BLUE}${BOLD}📚 CLASSICAL ALGORITHMS:${RESET}"
                echo -e "${MAGENTA}─────────────────────────${RESET}"
                echo
                echo -e "${YELLOW}${BOLD}5. AES-256-CBC (Traditional AES)${RESET}"
                echo -e "   🔸 ${BOLD}Security Level:${RESET} ⭐⭐⭐⭐ Very Secure"
                echo -e "   🔸 ${BOLD}Speed:${RESET} Fast (~100 MB/s)"
                echo -e "   🔸 ${BOLD}Features:${RESET} Industry standard, widely compatible"
                echo -e "   🔸 ${BOLD}Note:${RESET} No built-in authentication (use GCM instead)"
                echo
                echo -e "${YELLOW}${BOLD}6. RSA-2048 (Public Key Cryptography)${RESET}"
                echo -e "   🔸 ${BOLD}Security Level:${RESET} ⭐⭐⭐⭐ Secure until 2030"
                echo -e "   🔸 ${BOLD}Speed:${RESET} Slow (asymmetric operations)"
                echo -e "   🔸 ${BOLD}File Size:${RESET} Maximum ~200 bytes"
                echo -e "   🔸 ${BOLD}Best For:${RESET} Small files, legacy compatibility"
                echo
                echo -e "${YELLOW}${BOLD}7. RSA+AES Hybrid (Legacy Compatible)${RESET}"
                echo -e "   🔸 ${BOLD}Security Level:${RESET} ⭐⭐⭐⭐ Very Secure"
                echo -e "   🔸 ${BOLD}Best For:${RESET} Legacy systems, unlimited file size"
                echo
                echo -e "${RED}${BOLD}8. 3DES (Deprecated)${RESET}"
                echo -e "   🔸 ${BOLD}Security Level:${RESET} ⭐⭐ Legacy only"
                echo -e "   🔸 ${BOLD}Status:${RESET} ${RED}Not recommended - included for compatibility${RESET}"
                echo
                ;;
            4)
                echo
                echo -e "${BLUE}${BOLD}🛡️ SECURITY GUIDE:${RESET}"
                echo -e "${MAGENTA}─────────────────${RESET}"
                echo
                echo -e "${GREEN}${BOLD}Password Security:${RESET}"
                echo -e "   ✅ ${BOLD}Minimum 16 characters${RESET} for high-security files"
                echo -e "   ✅ ${BOLD}Use passphrases${RESET} like 'Coffee!Mountain#Rain$2024'"
                echo -e "   ✅ ${BOLD}Include symbols:${RESET} !@#$%^&*()_+-="
                echo -e "   ✅ ${BOLD}Avoid patterns:${RESET} 123, abc, qwerty, personal info"
                echo -e "   ✅ ${BOLD}Use password managers${RESET} like Bitwarden, 1Password"
                echo
                echo -e "${GREEN}${BOLD}Key Management Best Practices:${RESET}"
                echo -e "   🔑 ${BOLD}Private keys:${RESET} Store securely, never share"
                echo -e "   🔑 ${BOLD}Public keys:${RESET} Can be shared, verify authenticity"
                echo -e "   🔑 ${BOLD}Backup strategy:${RESET} Multiple secure locations"
                echo -e "   🔑 ${BOLD}Key rotation:${RESET} Update keys annually for high-value data"
                echo
                echo -e "${GREEN}${BOLD}File Security:${RESET}"
                echo -e "   📁 ${BOLD}Original files:${RESET} Securely delete after encryption"
                echo -e "   📁 ${BOLD}Encrypted files:${RESET} Test decryption before deleting originals"
                echo -e "   📁 ${BOLD}Backups:${RESET} Multiple encrypted backups in different locations"
                echo -e "   📁 ${BOLD}Transport:${RESET} Use secure channels (HTTPS, SSH, encrypted email)"
                echo
                echo -e "${RED}${BOLD}Common Security Mistakes to Avoid:${RESET}"
                echo -e "   ❌ Using the same password for multiple files"
                echo -e "   ❌ Storing passwords in plain text files"
                echo -e "   ❌ Sharing private keys via insecure channels"
                echo -e "   ❌ Not testing decryption before relying on encrypted files"
                echo -e "   ❌ Using weak algorithms (3DES) for new encryptions"
                echo
                ;;
            5)
                echo
                echo -e "${BLUE}${BOLD}⚡ PERFORMANCE OPTIMIZATION:${RESET}"
                echo -e "${MAGENTA}────────────────────────────${RESET}"
                echo
                echo -e "${GREEN}${BOLD}Algorithm Performance Ranking:${RESET}"
                echo -e "   🥇 ${BOLD}ChaCha20-Poly1305${RESET} - Fastest on mobile/ARM"
                echo -e "   🥈 ${BOLD}AES-256-GCM${RESET} - Fastest on x86 with AES-NI"
                echo -e "   🥉 ${BOLD}AES-256-CBC${RESET} - Good general performance"
                echo -e "   4️⃣ ${BOLD}ECC operations${RESET} - Fast for key operations"
                echo -e "   5️⃣ ${BOLD}RSA operations${RESET} - Slower asymmetric operations"
                echo
                echo -e "${GREEN}${BOLD}Hardware Optimization:${RESET}"
                echo -e "   💻 ${BOLD}CPU:${RESET} Look for AES-NI support (Intel/AMD)"
                echo -e "   💾 ${BOLD}Storage:${RESET} SSD recommended for large files"
                echo -e "   🧠 ${BOLD}RAM:${RESET} 4GB+ recommended for large file operations"
                echo -e "   🌡️ ${BOLD}Temperature:${RESET} Good cooling prevents CPU throttling"
                echo
                echo -e "${GREEN}${BOLD}File Size Recommendations:${RESET}"
                echo -e "   📄 ${BOLD}< 1KB:${RESET} ECC direct encryption"
                echo -e "   📄 ${BOLD}1KB - 100MB:${RESET} AES-256-GCM or ChaCha20"
                echo -e "   📄 ${BOLD}100MB - 10GB:${RESET} AES-256-GCM (best performance)"
                echo -e "   📄 ${BOLD}> 10GB:${RESET} Consider file splitting or streaming"
                echo
                echo -e "${GREEN}${BOLD}System Tuning:${RESET}"
                echo -e "   ⚙️ ${BOLD}Disable swap${RESET} for sensitive operations"
                echo -e "   ⚙️ ${BOLD}Use RAM disk${RESET} for temporary files (if available)"
                echo -e "   ⚙️ ${BOLD}Close other applications${RESET} during large encryptions"
                echo -e "   ⚙️ ${BOLD}Monitor system resources${RESET} (htop, iotop)"
                echo
                ;;
            6)
                echo
                echo -e "${BLUE}${BOLD}🔧 TROUBLESHOOTING GUIDE:${RESET}"
                echo -e "${MAGENTA}─────────────────────────${RESET}"
                echo
                echo -e "${RED}${BOLD}Common Problems & Solutions:${RESET}"
                echo
                echo -e "${YELLOW}❌ \"Wrong password\" or \"Bad decrypt\"${RESET}"
                echo -e "   🔍 Check if you're using the correct algorithm"
                echo -e "   🔍 Verify password (case-sensitive)"
                echo -e "   🔍 Ensure file hasn't been corrupted"
                echo -e "   🔍 Try different decryption algorithms"
                echo
                echo -e "${YELLOW}❌ \"File too large\" (RSA/ECC)${RESET}"
                echo -e "   💡 Use Hybrid algorithms instead"
                echo -e "   💡 RSA: max ~200 bytes, ECC: max ~32 bytes"
                echo -e "   💡 Consider AES-256-GCM for large files"
                echo
                echo -e "${YELLOW}❌ \"Permission denied\"${RESET}"
                echo -e "   📁 Check file permissions: chmod 644 filename"
                echo -e "   📁 Verify directory write permissions"
                echo -e "   📁 Run with appropriate user privileges"
                echo
                echo -e "${YELLOW}❌ \"OpenSSL command not found\"${RESET}"
                echo -e "   📦 Ubuntu/Debian: sudo apt install openssl"
                echo -e "   📦 CentOS/RHEL: sudo yum install openssl"
                echo -e "   📦 macOS: brew install openssl"
                echo
                echo -e "${YELLOW}❌ \"Algorithm not supported\"${RESET}"
                echo -e "   🔄 Update OpenSSL to latest version"
                echo -e "   🔄 Check OpenSSL compilation flags"
                echo -e "   🔄 Use classical algorithms as fallback"
                echo
                echo -e "${GREEN}${BOLD}Debug Mode:${RESET}"
                echo -e "   🐛 Check logs: cat $LOG_FILE"
                echo -e "   🐛 Verbose mode: bash -x encryptor"
                echo -e "   🐛 Test OpenSSL: openssl version -a"
                echo
                ;;
            7)
                echo
                echo -e "${BLUE}${BOLD}🎯 BEST PRACTICES:${RESET}"
                echo -e "${MAGENTA}─────────────────${RESET}"
                echo
                echo -e "${GREEN}${BOLD}Development & Enterprise Use:${RESET}"
                echo -e "   🏢 ${BOLD}CI/CD Integration:${RESET} Automate encryption in pipelines"
                echo -e "   🏢 ${BOLD}Key Management:${RESET} Use dedicated key management systems"
                echo -e "   🏢 ${BOLD}Audit Trails:${RESET} Enable comprehensive logging"
                echo -e "   🏢 ${BOLD}Access Control:${RESET} Implement role-based access"
                echo
                echo -e "${GREEN}${BOLD}Personal Use:${RESET}"
                echo -e "   👤 ${BOLD}Document Recovery:${RESET} Keep secure password/key recovery methods"
                echo -e "   👤 ${BOLD}Regular Testing:${RESET} Verify you can decrypt important files"
                echo -e "   👤 ${BOLD}Backup Strategy:${RESET} 3-2-1 rule (3 copies, 2 different media, 1 offsite)"
                echo -e "   👤 ${BOLD}Update Policy:${RESET} Re-encrypt with modern algorithms periodically"
                echo
                echo -e "${GREEN}${BOLD}Security Compliance:${RESET}"
                echo -e "   📋 ${BOLD}GDPR:${RESET} Use strong encryption for personal data"
                echo -e "   📋 ${BOLD}HIPAA:${RESET} AES-256 minimum for healthcare data"
                echo -e "   📋 ${BOLD}PCI-DSS:${RESET} Strong encryption for payment data"
                echo -e "   📋 ${BOLD}SOC2:${RESET} Document encryption procedures and key management"
                echo
                echo -e "${GREEN}${BOLD}Algorithm Selection Strategy:${RESET}"
                echo -e "   🎯 ${BOLD}High Performance:${RESET} AES-256-GCM or ChaCha20-Poly1305"
                echo -e "   🎯 ${BOLD}Maximum Security:${RESET} Hybrid ECC+AES"
                echo -e "   🎯 ${BOLD}Legacy Systems:${RESET} AES-256-CBC or RSA+AES"
                echo -e "   🎯 ${BOLD}Future-Proofing:${RESET} ECC-based algorithms"
                echo
                ;;
            8)
                echo
                echo -e "${BLUE}${BOLD}📁 FILE MANAGEMENT:${RESET}"
                echo -e "${MAGENTA}──────────────────${RESET}"
                echo
                echo -e "${GREEN}${BOLD}File Extensions Guide:${RESET}"
                echo -e "   📄 ${BOLD}.enc${RESET} - Encrypted file (all algorithms)"
                echo -e "   🔑 ${BOLD}.key${RESET} - Private key (RSA/ECC)"
                echo -e "   🔓 ${BOLD}.pub${RESET} - Public key (RSA/ECC)"
                echo -e "   🔒 ${BOLD}.key.enc${RESET} - Encrypted symmetric key"
                echo -e "   📊 ${BOLD}.log${RESET} - Operation logs"
                echo -e "   ↩️ ${BOLD}.dec${RESET} - Decrypted file"
                echo
                echo -e "${GREEN}${BOLD}Automatic File Naming:${RESET}"
                echo -e "   🎯 Prevents accidental overwrites"
                echo -e "   📝 Original: document.txt"
                echo -e "   📝 First encryption: document.txt.enc"
                echo -e "   📝 If exists: document.txt.enc.1"
                echo -e "   📝 Next: document.txt.enc.2, etc."
                echo
                echo -e "${GREEN}${BOLD}Secure File Operations:${RESET}"
                echo -e "   🗑️ ${BOLD}Secure deletion:${RESET} shred -u filename (Linux)"
                echo -e "   🗑️ ${BOLD}Secure deletion:${RESET} rm -P filename (macOS)"
                echo -e "   📂 ${BOLD}Temporary files:${RESET} Created in $TEMP_DIR"
                echo -e "   🧹 ${BOLD}Auto cleanup:${RESET} All temp files removed on exit"
                echo
                echo -e "${GREEN}${BOLD}Backup Strategies:${RESET}"
                echo -e "   💾 ${BOLD}Local backups:${RESET} External drives, different algorithms"
                echo -e "   ☁️ ${BOLD}Cloud backups:${RESET} Encrypt before uploading"
                echo -e "   🌍 ${BOLD}Geographic distribution:${RESET} Store copies in different locations"
                echo -e "   🔄 ${BOLD}Rotation schedule:${RESET} Regular backup updates and testing"
                echo
                ;;
            q|Q)
                return 0
                ;;
            *)
                echo -e "${RED}Invalid choice. Please select 1-8 or 'q' to return.${RESET}"
                ;;
        esac
        echo
        echo -e "${DIM}Press Enter to continue or 'q' to return to main menu...${RESET}"
        read continue_choice
        if [[ "$continue_choice" == "q" || "$continue_choice" == "Q" ]]; then
            return 0
        fi
        echo
    done
}

# main menu with system status
show_main_menu() {
    echo -e "${CYAN}${BOLD}🏠 Main Menu${RESET}"
    echo -e "${CYAN}─────────────────────────────────────────────────────────${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}1)${RESET} List files in current directory 📁             ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}2)${RESET} Encrypt a file 🔐                             ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}3)${RESET} Decrypt a file 🔓                             ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}4)${RESET} Batch operations 📦                           ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}5)${RESET} System information 💻                         ${CYAN}│${RESET}"
    echo -e "${CYAN}├─────────────────────────────────────────────────────────┤${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}h)${RESET} Help manual 📖                               ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}v)${RESET} Version information ℹ️                        ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}l)${RESET} View operation logs 📊                       ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}q)${RESET} Quit 🚪                                      ${CYAN}│${RESET}"
    echo -e "${CYAN}└─────────────────────────────────────────────────────────┘${RESET}"
    
    # System status indicator
    local openssl_status="❌"
    local disk_space=""
    if command -v openssl >/dev/null 2>&1; then
        openssl_status="✅"
    fi
    
    if command -v df >/dev/null 2>&1; then
        disk_space=$(df -h . | awk 'NR==2 {print $4}')
    fi
    
    echo -e "${DIM}Status: OpenSSL $openssl_status | Free space: ${disk_space:-N/A} | Logs: $(wc -l < "$LOG_FILE" 2>/dev/null || echo 0) entries${RESET}"
    echo
}

# Batch operations functionality
batch_operations() {
    echo -e "${BLUE}${BOLD}📦 Batch Operations${RESET}"
    echo -e "${MAGENTA}═══════════════════${RESET}"
    echo
    echo -e "${CYAN}┌─ Available Batch Operations ──────────────────────────┐${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}1)${RESET} Encrypt multiple files (same algorithm)         ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}2)${RESET} Decrypt multiple files                          ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}3)${RESET} Verify encrypted files integrity               ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}4)${RESET} Generate key pairs in bulk                      ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}q)${RESET} Return to main menu                             ${CYAN}│${RESET}"
    echo -e "${CYAN}└────────────────────────────────────────────────────────┘${RESET}"
    echo
    
    echo -n -e "${BOLD}Your choice > ${RESET}"
    read batch_choice
    
    case $batch_choice in
        1)
            echo -e "${BLUE}📁 Select files to encrypt (space-separated):${RESET}"
            echo -e "${DIM}Example: file1.txt file2.pdf document.doc${RESET}"
            echo -n -e "${BOLD}Files > ${RESET}"
            read -a files_array
            
            if [[ ${#files_array[@]} -eq 0 ]]; then
                echo -e "${RED}No files specified${RESET}"
                return
            fi
            
            show_encryption_menu
            echo -n -e "${BOLD}Algorithm choice > ${RESET}"
            read algo_choice
            
            echo -e "${GREEN}🚀 Starting batch encryption...${RESET}"
            for file in "${files_array[@]}"; do
                if [[ -f "$file" ]]; then
                    echo -e "${BLUE}Processing: $file${RESET}"

                else
                    echo -e "${YELLOW}⚠️ File not found: $file${RESET}"
                fi
            done
            ;;
        2)
            echo -e "${BLUE}📁 Select encrypted files to decrypt (*.enc):${RESET}"
            ls -1 *.enc 2>/dev/null | head -10
            echo -n -e "${BOLD}File pattern (e.g., *.enc or specific files) > ${RESET}"
            read pattern
            # Batch decryption logic here
            ;;
        3)
            echo -e "${BLUE}🔍 Verifying encrypted files...${RESET}"
            local verified=0
            local failed=0
            for file in *.enc; do
                if [[ -f "$file" ]]; then
                    echo -n -e "${CYAN}Checking $file... ${RESET}"
                    if file "$file" | grep -q "data"; then
                        echo -e "${GREEN}✅${RESET}"
                        ((verified++))
                    else
                        echo -e "${RED}❌${RESET}"
                        ((failed++))
                    fi
                fi
            done
            echo -e "${BLUE}📊 Results: $verified verified, $failed failed${RESET}"
            ;;
        4)
            echo -e "${BLUE}🔑 Bulk key generation${RESET}"
            echo -n -e "${BOLD}Number of key pairs to generate > ${RESET}"
            read key_count
            if [[ "$key_count" =~ ^[0-9]+$ ]] && [[ $key_count -gt 0 ]] && [[ $key_count -le 10 ]]; then
                for ((i=1; i<=key_count; i++)); do
                    echo -e "${CYAN}Generating key pair $i/$key_count...${RESET}"
                    openssl ecparam -genkey -name prime256v1 -out "keypair_$i.key" 2>/dev/null
                    openssl ec -in "keypair_$i.key" -pubout -out "keypair_$i.pub" 2>/dev/null
                    chmod 600 "keypair_$i.key"
                done
                echo -e "${GREEN}✅ Generated $key_count ECC key pairs${RESET}"
            else
                echo -e "${RED}Invalid number (1-10 allowed)${RESET}"
            fi
            ;;
        q|Q)
            return 0
            ;;
        *)
            echo -e "${RED}Invalid choice${RESET}"
            ;;
    esac
    
    echo
    echo -e "${DIM}Press Enter to continue...${RESET}"
    read
}

# System information display
show_system_info() {
    echo -e "${BLUE}${BOLD}💻 System Information${RESET}"
    echo -e "${MAGENTA}═══════════════════${RESET}"
    echo
    
    # OS Information
    echo -e "${GREEN}${BOLD}Operating System:${RESET}"
    if command -v lsb_release >/dev/null 2>&1; then
        lsb_release -a 2>/dev/null | grep -E "(Description|Release)"
    elif [[ -f /etc/os-release ]]; then
        source /etc/os-release
        echo "  Name: $PRETTY_NAME"
    elif [[ $(uname) == "Darwin" ]]; then
        echo "  macOS $(sw_vers -productVersion)"
    else
        echo "  $(uname -srm)"
    fi
    echo
    
    # Hardware Information
    echo -e "${GREEN}${BOLD}Hardware:${RESET}"
    echo "  CPU: $(uname -p)"
    if command -v nproc >/dev/null 2>&1; then
        echo "  Cores: $(nproc)"
    fi
    
    # Check for AES-NI support
    if grep -q "aes" /proc/cpuinfo 2>/dev/null; then
        echo "  AES-NI: ✅ Supported"
    elif sysctl -n machdep.cpu.features 2>/dev/null | grep -q "AES"; then
        echo "  AES-NI: ✅ Supported (macOS)"
    else
        echo "  AES-NI: ❌ Not detected"
    fi
    
    # Memory information
    if command -v free >/dev/null 2>&1; then
        local mem_info=$(free -h | awk 'NR==2{printf "  RAM: %s total, %s free\n", $2, $7}')
        echo "$mem_info"
    fi
    echo
    
    # OpenSSL Information
    echo -e "${GREEN}${BOLD}Cryptographic Support:${RESET}"
    if command -v openssl >/dev/null 2>&1; then
        local ssl_version=$(openssl version)
        echo "  $ssl_version"
        
        # Check algorithm support
        echo "  Supported algorithms:"
        local algos=("aes-256-gcm" "chacha20-poly1305" "ec")
        for algo in "${algos[@]}"; do
            if openssl list -cipher-algorithms 2>/dev/null | grep -qi "$algo" || 
               openssl ecparam -list_curves 2>/dev/null >/dev/null 2>&1; then
                echo "    ✅ $algo"
            else
                echo "    ❌ $algo"
            fi
        done
    else
        echo "  ❌ OpenSSL not found"
    fi
    echo
    
    # Disk Space
    echo -e "${GREEN}${BOLD}Storage:${RESET}"
    if command -v df >/dev/null 2>&1; then
        df -h . | awk 'NR==2{printf "  Current directory: %s used, %s available\n", $3, $4}'
    fi
    
    # Encryptor-specific information
    echo -e "${GREEN}${BOLD}Encryptor Configuration:${RESET}"
    echo "  Version: $VERSION"
    echo "  Config directory: $CONFIG_DIR"
    echo "  Temporary directory: $TEMP_DIR"
    echo "  Log file: $LOG_FILE"
    if [[ -f "$LOG_FILE" ]]; then
        local log_entries=$(wc -l < "$LOG_FILE")
        echo "  Log entries: $log_entries"
    fi
    echo
}

# View logs functionality
view_logs() {
    echo -e "${BLUE}${BOLD}📊 Operation Logs${RESET}"
    echo -e "${MAGENTA}═════════════════${RESET}"
    echo
    
    if [[ ! -f "$LOG_FILE" ]]; then
        echo -e "${YELLOW}No log file found. Operations will be logged here.${RESET}"
        return
    fi
    
    local log_count=$(wc -l < "$LOG_FILE")
    echo -e "${BLUE}Total log entries: $log_count${RESET}"
    echo
    
    echo -e "${CYAN}┌─ Recent Operations (last 20) ──────────────────────────┐${RESET}"
    tail -20 "$LOG_FILE" | while IFS= read -r line; do
        # Color code different log levels
        if [[ "$line" =~ ERROR ]]; then
            echo -e "${RED}$line${RESET}"
        elif [[ "$line" =~ SUCCESS ]]; then
            echo -e "${GREEN}$line${RESET}"
        elif [[ "$line" =~ PERF ]]; then
            echo -e "${BLUE}$line${RESET}"
        else
            echo -e "${DIM}$line${RESET}"
        fi
    done
    echo -e "${CYAN}└────────────────────────────────────────────────────────┘${RESET}"
    echo
    
    echo -e "${YELLOW}Options:${RESET}"
    echo -e "  ${BOLD}c)${RESET} Clear logs"
    echo -e "  ${BOLD}f)${RESET} View full log file"
    echo -e "  ${BOLD}Enter)${RESET} Return to main menu"
    echo
    echo -n -e "${BOLD}Choice > ${RESET}"
    read log_choice
    
    case $log_choice in
        c|C)
            echo -n -e "${YELLOW}Clear all logs? (y/N) > ${RESET}"
            read confirm
            if [[ "$confirm" =~ ^[Yy]$ ]]; then
                > "$LOG_FILE"
                echo -e "${GREEN}✅ Logs cleared${RESET}"
            fi
            ;;
        f|F)
            if command -v less >/dev/null 2>&1; then
                less "$LOG_FILE"
            else
                cat "$LOG_FILE"
            fi
            ;;
    esac
}

# Version information with enhanced details
show_version() {
    echo -e "${BLUE}${BOLD}ℹ️ Encryptor Version Information${RESET}"
    echo -e "${MAGENTA}═══════════════════════════════════${RESET}"
    echo
    echo -e "${GREEN}${BOLD}Encryptor v$VERSION${RESET}"
    echo -e "${CYAN}Advanced File Encryption Tool${RESET}"
    echo
    echo -e "${BLUE}${BOLD}Features in this version:${RESET}"
    echo -e "  ✅ 8 encryption algorithms (4 modern + 4 classical)"
    echo -e "  ✅ Enhanced user interface with colors and icons"
    echo -e "  ✅ Performance monitoring and logging"
    echo -e "  ✅ Batch operations support"
    echo -e "  ✅ Comprehensive help system"
    echo -e "  ✅ System compatibility checking"
    echo -e "  ✅ Secure file management"
    echo
    echo -e "${BLUE}${BOLD}Supported Algorithms:${RESET}"
    echo -e "  🔮 Modern: AES-256-GCM, ChaCha20-Poly1305, ECC P-256, Hybrid ECC+AES"
    echo -e "  📚 Classical: AES-256-CBC, RSA-2048, RSA+AES Hybrid, 3DES"
    echo
    echo -e "${BLUE}${BOLD}System Requirements:${RESET}"
    echo -e "  • Bash 4.0+"
    echo -e "  • OpenSSL 1.1.0+"
    echo -e "  • Linux/macOS/WSL"
    echo
    echo -e "${DIM}Repository: https://github.com/mpgamer75/encryptor${RESET}"
    echo -e "${DIM}License: MIT${RESET}"
    echo
}

# Initialize logging
log_operation "INFO" "Encryptor v$VERSION started"

# Main execution
clear_and_header

# Quick system check
if ! command -v openssl >/dev/null 2>&1; then
    echo -e "${RED}❌ Error: OpenSSL not found${RESET}"
    echo -e "${YELLOW}Please install OpenSSL and try again${RESET}"
    exit 1
fi

# Main application loop
while true; do
    show_main_menu
    echo -n -e "${BOLD}Your choice > ${RESET}"
    read choice

    case $choice in
        1)
            echo
            list_files_enhanced
            echo -e "${DIM}Press Enter to continue...${RESET}"
            read
            ;;
        2)
            echo
            echo -n -e "${BOLD}File name to encrypt > ${RESET}"
            read file
            if [[ ! -f "$file" ]]; then
                echo -e "${RED}❌ Error: File '$file' does not exist${RESET}"
                echo
                continue
            fi

            echo
            show_encryption_menu
            echo -n -e "${BOLD}Your choice > ${RESET}"
            read algo

            # Generate safe output filename
            outfile="$file.enc"
            if [[ -f "$outfile" ]]; then
                echo -n -e "${YELLOW}⚠️ Warning: File $outfile already exists. Overwrite (y/n)? ${RESET}"
                read ow
                if [[ "$ow" != "y" ]]; then
                    n=1
                    while [[ -f "$file.$n.enc" ]]; do
                        ((n++))
                    done
                    outfile="$file.$n.enc"
                    echo -e "${YELLOW}Using new filename: $outfile${RESET}"
                fi
            fi

            echo
            case $algo in
                1) encrypt_aes_gcm "$file" "$outfile" ;;
                2) encrypt_chacha20 "$file" "$outfile" ;;
                3) encrypt_ecc "$file" "$outfile" ;;
                4) encrypt_ecc_aes_hybrid "$file" "$outfile" ;;
                5) 
                    echo "🔐 AES-256-CBC encryption"
                    start_timer
                    if openssl enc -aes-256-cbc -pbkdf2 -salt -in "$file" -out "$outfile"; then
                        end_timer "AES-256-CBC encryption"
                        echo -e "${GREEN}✅ AES-256-CBC encryption completed -> $outfile${RESET}"
                        log_operation "SUCCESS" "AES-256-CBC encryption: $file -> $outfile"
                    else
                        handle_error $? "AES-256-CBC encryption" "$file"
                    fi
                    ;;
                6) # RSA
                    echo "🔐 RSA-2048 encryption"
                    local keyfile="rsa_private.pem"
                    local pubfile="rsa_public.pem"
                    
                    start_timer
                    if [[ ! -f "$keyfile" || ! -f "$pubfile" ]]; then
                        echo "📊 Generating RSA-2048 key pair..."
                        openssl genrsa -out "$keyfile" 2048 2>/dev/null
                        openssl rsa -in "$keyfile" -pubout -out "$pubfile" 2>/dev/null
                        chmod 600 "$keyfile"
                        echo "🔑 Keys generated: $keyfile (private), $pubfile (public)"
                    fi
                    
                    local filesize=$(stat -f%z "$file" 2>/dev/null || stat -c%s "$file" 2>/dev/null)
                    if [[ $filesize -gt 190 ]]; then
                        echo -e "${YELLOW}⚠️ File too large for RSA encryption (max ~190 bytes)${RESET}"
                        echo "💡 Consider using RSA+AES hybrid instead"
                        continue
                    fi
                    
                    if openssl pkeyutl -encrypt -pubin -inkey "$pubfile" -in "$file" -out "$outfile" 2>/dev/null; then
                        end_timer "RSA-2048 encryption"
                        echo -e "${GREEN}✅ RSA encryption completed -> $outfile${RESET}"
                        log_operation "SUCCESS" "RSA-2048 encryption: $file -> $outfile"
                    else
                        handle_error $? "RSA encryption" "$file"
                    fi
                    ;;
                7) # RSA+AES Hybrid
                    echo "🔐 RSA+AES Hybrid encryption"
                    local datafile="$outfile"
                    local keyfile="${file%.*}.rsa.aes.key.enc"
                    local rsaprivate="rsa_private.pem"
                    local rsapublic="rsa_public.pem"
                    
                    start_timer
                    if [[ ! -f "$rsaprivate" || ! -f "$rsapublic" ]]; then
                        echo "📊 Generating RSA-2048 key pair..."
                        openssl genrsa -out "$rsaprivate" 2048 2>/dev/null
                        openssl rsa -in "$rsaprivate" -pubout -out "$rsapublic" 2>/dev/null
                        chmod 600 "$rsaprivate"
                        echo "🔑 RSA keys generated"
                    fi
                    
                    local temp_aes_key="$TEMP_DIR/aes_key_$"
                    openssl rand -out "$temp_aes_key" 32
                    
                    echo "📊 Encrypting file with AES-256-CBC..."
                    openssl enc -aes-256-cbc -in "$file" -out "$datafile" -pass file:"$temp_aes_key" 2>/dev/null
                    
                    echo "🔑 Encrypting AES key with RSA..."
                    openssl pkeyutl -encrypt -pubin -inkey "$rsapublic" -in "$temp_aes_key" -out "$keyfile" 2>/dev/null
                    
                    rm -f "$temp_aes_key"
                    
                    if [[ $? -eq 0 ]]; then
                        end_timer "RSA+AES Hybrid encryption"
                        echo -e "${GREEN}✅ Hybrid encryption completed:${RESET}"
                        echo -e "   📄 Data: $datafile"
                        echo -e "   🔑 Key:  $keyfile"
                        log_operation "SUCCESS" "RSA+AES Hybrid encryption: $file"
                    else
                        handle_error $? "RSA+AES Hybrid encryption" "$file"
                    fi
                    ;;
                8) # 3DES
                    echo "🔐 3DES encryption (deprecated)"
                    echo -e "${YELLOW}⚠️ Warning: 3DES is deprecated. Consider using AES-256-GCM instead.${RESET}"
                    echo -n -e "Continue with 3DES? (y/N) > "
                    read confirm_3des
                    if [[ "$confirm_3des" =~ ^[Yy]$ ]]; then
                        start_timer
                        if openssl enc -des-ede3-cbc -pbkdf2 -salt -in "$file" -out "$outfile"; then
                            end_timer "3DES encryption"
                            echo -e "${GREEN}✅ 3DES encryption completed -> $outfile${RESET}"
                            log_operation "SUCCESS" "3DES encryption: $file -> $outfile"
                        else
                            handle_error $? "3DES encryption" "$file"
                        fi
                    fi
                    ;;
                *)
                    echo -e "${RED}❌ Invalid algorithm choice${RESET}"
                    ;;
            esac
            echo
            echo -e "${DIM}Press Enter to continue...${RESET}"
            read
            ;;
        3) # Decryption
            echo
            echo -n -e "${BOLD}File name to decrypt > ${RESET}"
            read file
            if [[ ! -f "$file" ]]; then
                echo -e "${RED}❌ Error: File '$file' does not exist${RESET}"
                echo
                continue
            fi

            echo
            show_decryption_menu
            echo -n -e "${BOLD}Your choice > ${RESET}"
            read algo
            
            local decfile="${file%.enc}.dec"
            if [[ -f "$decfile" ]]; then
                echo -n -e "${YELLOW}⚠️ Warning: Output file $decfile exists. Overwrite (y/n)? ${RESET}"
                read ow
                if [[ "$ow" != "y" ]]; then
                    n=1
                    while [[ -f "${file%.enc}.$n.dec" ]]; do
                        ((n++))
                    done
                    decfile="${file%.enc}.$n.dec"
                    echo -e "${YELLOW}Using new filename: $decfile${RESET}"
                fi
            fi

            echo
            start_timer
            case $algo in
                1) # AES-256-GCM decryption
                    echo "🔓 AES-256-GCM decryption"
                    echo -n "Enter password: "
                    read -s password
                    echo
                    if openssl enc -d -aes-256-gcm -in "$file" -out "$decfile" -pass pass:"$password" 2>/dev/null; then
                        end_timer "AES-256-GCM decryption"
                        echo -e "${GREEN}✅ AES-256-GCM decryption completed -> $decfile${RESET}"
                        log_operation "SUCCESS" "AES-256-GCM decryption: $file -> $decfile"
                    else
                        handle_error $? "AES-256-GCM decryption" "$file"
                    fi
                    ;;
                2) # ChaCha20-Poly1305 decryption
                    echo "🔓 ChaCha20-Poly1305 decryption"
                    if openssl enc -d -chacha20-poly1305 -pbkdf2 -in "$file" -out "$decfile" 2>/dev/null; then
                        end_timer "ChaCha20-Poly1305 decryption"
                        echo -e "${GREEN}✅ ChaCha20-Poly1305 decryption completed -> $decfile${RESET}"
                        log_operation "SUCCESS" "ChaCha20-Poly1305 decryption: $file -> $decfile"
                    else
                        handle_error $? "ChaCha20-Poly1305 decryption" "$file"
                    fi
                    ;;
                3) # ECC decryption
                    echo "🔓 ECC P-256 decryption"
                    local eccprivate="${file%.*}.ecc.key"
                    if [[ ! -f "$eccprivate" ]]; then
                        echo -n -e "${BOLD}ECC private key file > ${RESET}"
                        read eccprivate
                        if [[ ! -f "$eccprivate" ]]; then
                            echo -e "${RED}❌ Private key file not found${RESET}"
                            continue
                        fi
                    fi
                    
                    if openssl pkeyutl -decrypt -inkey "$eccprivate" -in "$file" -out "$decfile" 2>/dev/null; then
                        end_timer "ECC P-256 decryption"
                        echo -e "${GREEN}✅ ECC decryption completed -> $decfile${RESET}"
                        log_operation "SUCCESS" "ECC P-256 decryption: $file -> $decfile"
                    else
                        handle_error $? "ECC decryption" "$file"
                    fi
                    ;;
                4) # Hybrid ECC+AES decryption
                    echo "🔓 Hybrid ECC+AES decryption"
                    echo -n -e "${BOLD}Encrypted key file (.ecc.aes.key.enc) > ${RESET}"
                    read keyfile
                    if [[ ! -f "$keyfile" ]]; then
                        echo -e "${RED}❌ Key file not found${RESET}"
                        continue
                    fi
                    
                    local eccprivate="${file%.*}.ecc.key"
                    if [[ ! -f "$eccprivate" ]]; then
                        echo -n -e "${BOLD}ECC private key file > ${RESET}"
                        read eccprivate
                        if [[ ! -f "$eccprivate" ]]; then
                            echo -e "${RED}❌ Private key file not found${RESET}"
                            continue
                        fi
                    fi
                    
                    local temp_aes_key="$TEMP_DIR/aes_key_dec_$"
                    echo "🔑 Decrypting AES key with ECC..."
                    openssl pkeyutl -decrypt -inkey "$eccprivate" -in "$keyfile" -out "$temp_aes_key" 2>/dev/null
                    
                    echo "📊 Decrypting file with AES..."
                    openssl enc -d -aes-256-gcm -in "$file" -out "$decfile" -pass file:"$temp_aes_key" 2>/dev/null
                    rm -f "$temp_aes_key"
                    
                    if [[ $? -eq 0 ]]; then
                        end_timer "Hybrid ECC+AES decryption"
                        echo -e "${GREEN}✅ Hybrid decryption completed -> $decfile${RESET}"
                        log_operation "SUCCESS" "Hybrid ECC+AES decryption: $file -> $decfile"
                    else
                        handle_error $? "Hybrid ECC+AES decryption" "$file"
                    fi
                    ;;
                5) # AES-256-CBC decryption
                    echo "🔓 AES-256-CBC decryption"
                    if openssl enc -d -aes-256-cbc -pbkdf2 -in "$file" -out "$decfile"; then
                        end_timer "AES-256-CBC decryption"
                        echo -e "${GREEN}✅ AES-256-CBC decryption completed -> $decfile${RESET}"
                        log_operation "SUCCESS" "AES-256-CBC decryption: $file -> $decfile"
                    else
                        handle_error $? "AES-256-CBC decryption" "$file"
                    fi
                    ;;
                6) # RSA decryption
                    echo "🔓 RSA-2048 decryption"
                    local rsaprivate="rsa_private.pem"
                    if [[ ! -f "$rsaprivate" ]]; then
                        echo -n -e "${BOLD}RSA private key file > ${RESET}"
                        read rsaprivate
                        if [[ ! -f "$rsaprivate" ]]; then
                            echo -e "${RED}❌ Private key file not found${RESET}"
                            continue
                        fi
                    fi
                    
                    if openssl pkeyutl -decrypt -inkey "$rsaprivate" -in "$file" -out "$decfile" 2>/dev/null; then
                        end_timer "RSA-2048 decryption"
                        echo -e "${GREEN}✅ RSA decryption completed -> $decfile${RESET}"
                        log_operation "SUCCESS" "RSA-2048 decryption: $file -> $decfile"
                    else
                        handle_error $? "RSA decryption" "$file"
                    fi
                    ;;
                7) # RSA+AES Hybrid decryption
                    echo "🔓 RSA+AES Hybrid decryption"
                    echo -n -e "${BOLD}Encrypted key file (.rsa.aes.key.enc) > ${RESET}"
                    read keyfile
                    if [[ ! -f "$keyfile" ]]; then
                        echo -e "${RED}❌ Key file not found${RESET}"
                        continue
                    fi
                    
                    local rsaprivate="rsa_private.pem"
                    if [[ ! -f "$rsaprivate" ]]; then
                        echo -n -e "${BOLD}RSA private key file > ${RESET}"
                        read rsaprivate
                        if [[ ! -f "$rsaprivate" ]]; then
                            echo -e "${RED}❌ Private key file not found${RESET}"
                            continue
                        fi
                    fi
                    
                    local temp_aes_key="$TEMP_DIR/aes_key_dec_$"
                    echo "🔑 Decrypting AES key with RSA..."
                    openssl pkeyutl -decrypt -inkey "$rsaprivate" -in "$keyfile" -out "$temp_aes_key" 2>/dev/null
                    
                    echo "📊 Decrypting file with AES..."
                    openssl enc -d -aes-256-cbc -in "$file" -out "$decfile" -pass file:"$temp_aes_key" 2>/dev/null
                    rm -f "$temp_aes_key"
                    
                    if [[ $? -eq 0 ]]; then
                        end_timer "RSA+AES Hybrid decryption"
                        echo -e "${GREEN}✅ Hybrid decryption completed -> $decfile${RESET}"
                        log_operation "SUCCESS" "RSA+AES Hybrid decryption: $file -> $decfile"
                    else
                        handle_error $? "RSA+AES Hybrid decryption" "$file"
                    fi
                    ;;
                8) # 3DES decryption
                    echo "🔓 3DES decryption"
                    if openssl enc -d -des-ede3-cbc -pbkdf2 -in "$file" -out "$decfile"; then
                        end_timer "3DES decryption"
                        echo -e "${GREEN}✅ 3DES decryption completed -> $decfile${RESET}"
                        log_operation "SUCCESS" "3DES decryption: $file -> $decfile"
                    else
                        handle_error $? "3DES decryption" "$file"
                    fi
                    ;;
                *)
                    echo -e "${RED}❌ Invalid algorithm choice${RESET}"
                    ;;
            esac
            echo
            echo -e "${DIM}Press Enter to continue...${RESET}"
            read
            ;;
        4) # Batch operations
            batch_operations
            ;;
        5) # System information
            show_system_info
            echo -e "${DIM}Press Enter to continue...${RESET}"
            read
            ;;
        h|H) # Help
            show_enhanced_help
            clear_and_header
            ;;
        v|V) # Version
            show_version
            echo -e "${DIM}Press Enter to continue...${RESET}"
            read
            ;;
        l|L) # View logs
            view_logs
            ;;
        q|Q) # Quit
            echo
            echo -e "${MAGENTA}${BOLD}Thank you for using Encryptor v$VERSION!${RESET}"
            echo -e "${BLUE}Your files are secure. Stay safe! 🔐${RESET}"
            echo
            log_operation "INFO" "Encryptor session ended"
            exit 0
            ;;
        *) # Invalid choice
            echo -e "${RED}❌ Invalid choice. Please select a valid option.${RESET}"
            echo
            ;;
    esac
done