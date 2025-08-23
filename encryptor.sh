#!/bin/bash

# Colors
RED="\e[31m"
GREEN="\e[32m"
YELLOW="\e[33m"
BLUE="\e[34m"
MAGENTA="\e[35m"
CYAN="\e[36m"
BOLD="\e[1m"
RESET="\e[0m"

# Clear screen for better presentation
clear

# Enhanced ASCII Art
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
echo -e "${GREEN}${BOLD}                    Advanced Encryption Tool${RESET}"
echo -e "${BLUE}                        Secure your files${RESET}"
echo
echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════════${RESET}"
echo

while true; do
    echo -e "${CYAN}${BOLD}┌─ Available Options ───────────────────────────────────────┐${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}1)${RESET} List all files in current directory              ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}2)${RESET} Encrypt a file                                   ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}3)${RESET} Decrypt a file                                   ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}h)${RESET} Help manual                                      ${CYAN}│${RESET}"
    echo -e "${CYAN}│${RESET} ${YELLOW}q)${RESET} Quit                                             ${CYAN}│${RESET}"
    echo -e "${CYAN}└───────────────────────────────────────────────────────────┘${RESET}"
    echo
    echo -n -e "${BOLD}Your choice > ${RESET}"
    read choice

    case $choice in
        1)
            echo
            echo -e "${BLUE}${BOLD}Files in current directory:${RESET}"
            echo -e "${MAGENTA}═══════════════════════════════════════${RESET}"
            ls -lah --color=always
            echo
            ;;
        2)
            echo
            echo -n -e "${BOLD}File name to encrypt > ${RESET}"
            read file
            if [[ ! -f $file ]]; then
                echo -e "${RED}Error: file does not exist${RESET}"
                echo
                continue
            fi

            echo
            echo -e "${BLUE}${BOLD}Choose encryption algorithm:${RESET}"
            echo -e "${CYAN}┌─ Available Algorithms ─────────────────────────┐${RESET}"
            echo -e "${CYAN}│${RESET} ${YELLOW}1)${RESET} AES-256 ${GREEN}(Recommended)${RESET}                   ${CYAN}│${RESET}"
            echo -e "${CYAN}│${RESET} ${YELLOW}2)${RESET} RSA ${YELLOW}(Files < 200 bytes)${RESET}              ${CYAN}│${RESET}"
            echo -e "${CYAN}│${RESET} ${YELLOW}3)${RESET} AES+RSA ${GREEN}(Hybrid - Very secure)${RESET}         ${CYAN}│${RESET}"
            echo -e "${CYAN}│${RESET} ${YELLOW}4)${RESET} 3DES ${RED}(Deprecated)${RESET}                     ${CYAN}│${RESET}"
            echo -e "${CYAN}└───────────────────────────────────────────────┘${RESET}"
            echo
            echo -n -e "${BOLD}Your choice > ${RESET}"
            read algo

            case $algo in
                1)  # AES-256
                    outfile="$file.enc" # we check if the file already exist, the user can either overwrite or use a different name for the new file
                    if [[ -f "$outfile" ]]; then
                        echo -n -e "${YELLOW}Warning: File $outfile already exists. Overwrite (y/n)? ${RESET}"
                        read ow
                        if [[ $ow == "n" ]]; then
                            n=1
                            while [[ -f "$file.$n.enc" ]]; do
                                ((n++))
                            done
                            outfile="$file.$n.enc"
                            echo -e "${YELLOW}Using new filename: $outfile${RESET}"
                        else
                            echo -e "${YELLOW}Overwriting $outfile${RESET}"
                        fi
                    fi
                    echo
                    echo "***AES-256 encryption***"
                    openssl enc -aes-256-cbc -pbkdf2 -salt -in "$file" -out "$outfile"
                    echo -e "${GREEN}AES encryption done -> $outfile${RESET}"
                    ;;

                2)  # RSA
                    outfile="$file.enc"
                    if [[ -f "$outfile" ]]; then
                        echo -n -e "${YELLOW}Warning: File $outfile already exists. Overwrite (y/n)? ${RESET}"
                        read ow
                        if [[ $ow == "n" ]]; then
                            n=1
                            while [[ -f "$file.$n.enc" ]]; do
                                ((n++))
                            done
                            outfile="$file.$n.enc"
                            echo -e "${YELLOW}Using new filename: $outfile${RESET}"
                        else
                            echo -e "${YELLOW}Overwriting $outfile${RESET}"
                        fi
                    fi

                    echo
                    echo "***RSA encryption***"
                    if [[ ! -f public.pem || ! -f private.pem ]]; then
                        echo "No RSA keys found, generating them..."
                        openssl genrsa -out private.pem 2048 2>/dev/null
                        openssl rsa -in private.pem -pubout -out public.pem 2>/dev/null
                        echo "Keys generated: private.pem/ public.pem"
                    fi
                    if ! openssl pkeyutl -encrypt -pubin -inkey public.pem -in "$file" -out "$outfile" 2>/dev/null; then
                        echo -e "${RED}Error: File too large for RSA direct encryption. Use AES+RSA instead.${RESET}"
                        rm -f "$outfile"
                    else
                        echo -e "${GREEN}RSA encryption done -> $outfile${RESET}"
                    fi
                    ;;

                3)  # AES + RSA
                    datafile="$file.enc"
                    keyfile="$file.key.enc"

                    if [[ -f "$datafile" || -f "$keyfile" ]]; then
                        echo -n -e "${YELLOW}Warning: Output files exist. Overwrite (y/n)? ${RESET}"
                        read ow
                        if [[ $ow == "n" ]]; then
                            n=1
                            while [[ -f "$file.$n.enc" || -f "$file.$n.key.enc" ]]; do
                                ((n++))
                            done
                            datafile="$file.$n.enc"
                            keyfile="$file.$n.key.enc"
                            echo -e "${YELLOW}Using new filenames: $datafile / $keyfile${RESET}"
                        else
                            echo -e "${YELLOW}Overwriting $datafile and $keyfile${RESET}"
                        fi
                    fi

                    echo
                    echo "***RSA+AES encryption***"
                    if [[ ! -f public.pem || ! -f private.pem ]]; then
                        echo "No RSA keys found, generating them..."
                        openssl genrsa -out private.pem 2048 2>/dev/null
                        openssl rsa -in private.pem -pubout -out public.pem 2>/dev/null
                        echo "Keys generated: private.pem/ public.pem"
                    fi
                    keyfile_tmp=$(mktemp)
                    openssl rand -base64 32 > "$keyfile_tmp"
                    openssl enc -aes-256-cbc -pbkdf2 -salt -in "$file" -out "$datafile" -pass file:"$keyfile_tmp"
                    openssl pkeyutl -encrypt -pubin -inkey public.pem -in "$keyfile_tmp" -out "$keyfile"
                    rm -f "$keyfile_tmp"
                    echo -e "${GREEN}AES+RSA encryption done -> $datafile + $keyfile${RESET}"
                    ;;

                4)  # 3DES
                    outfile="$file.enc"
                    if [[ -f "$outfile" ]]; then
                        echo -n -e "${YELLOW}Warning: File $outfile already exists. Overwrite (y/n)? ${RESET}"
                        read ow
                        if [[ $ow == "n" ]]; then
                            n=1
                            while [[ -f "$file.$n.enc" ]]; do
                                ((n++))
                            done
                            outfile="$file.$n.enc"
                            echo -e "${YELLOW}Using new filename: $outfile${RESET}"
                        else
                            echo -e "${YELLOW}Overwriting $outfile${RESET}"
                        fi
                    fi
                    echo
                    echo "***3DES encryption***"
                    openssl enc -des-ede3-cbc -pbkdf2 -salt -in "$file" -out "$outfile"
                    echo -e "${GREEN}3DES encryption done -> $outfile${RESET}"
                    ;;
                *)
                    echo -e "${RED}Invalid algorithm choice${RESET}"
                    ;;
            esac
            echo
            ;;

        3)
            echo
            echo -n -e "${BOLD}File name to decrypt > ${RESET}"
            read file
            if [[ ! -f $file ]]; then
                echo -e "${RED}Error: file does not exist${RESET}"
                echo
                continue
            fi

            echo
            echo -e "${BLUE}${BOLD}Choose decryption algorithm:${RESET}"
            echo -e "${CYAN}┌─ Available Algorithms ─────────────────────────┐${RESET}"
            echo -e "${CYAN}│${RESET} ${YELLOW}1)${RESET} AES-256                               ${CYAN}│${RESET}"
            echo -e "${CYAN}│${RESET} ${YELLOW}2)${RESET} RSA                                   ${CYAN}│${RESET}"
            echo -e "${CYAN}│${RESET} ${YELLOW}3)${RESET} AES+RSA                               ${CYAN}│${RESET}"
            echo -e "${CYAN}│${RESET} ${YELLOW}4)${RESET} 3DES                                  ${CYAN}│${RESET}"
            echo -e "${CYAN}└───────────────────────────────────────────────┘${RESET}"
            echo
            echo -n -e "${BOLD}Your choice > ${RESET}"
            read algo
            echo

            case $algo in
                1)
                    openssl enc -d -aes-256-cbc -pbkdf2 -in "$file" -out "${file%.enc}.dec"
                    echo -e "${GREEN}AES decryption done -> ${file%.enc}.dec${RESET}"
                    ;;
                2)
                    if [[ ! -f private.pem ]]; then
                        echo -e "${RED}Error: private.pem not found${RESET}"
                        echo
                        continue
                    fi
                    openssl pkeyutl -decrypt -inkey private.pem -in "$file" -out "${file%.enc}.dec"
                    echo -e "${GREEN}RSA decryption done -> ${file%.enc}.dec${RESET}"
                    ;;
                3)
                    echo -n -e "${BOLD}Encrypted key file (.key.enc) > ${RESET}"
                    read keyfile
                    if [[ ! -f $keyfile ]]; then
                        echo -e "${RED}Error: key file does not exist${RESET}"
                        echo
                        continue
                    fi
                    if [[ ! -f private.pem ]]; then
                        echo -e "${RED}Error: private.pem not found${RESET}"
                        echo
                        continue
                    fi
                    keyfile_tmp=$(mktemp)
                    openssl pkeyutl -decrypt -inkey private.pem -in "$keyfile" -out "$keyfile_tmp"
                    openssl enc -d -aes-256-cbc -pbkdf2 -in "$file" -out "${file%.enc}.dec" -pass file:"$keyfile_tmp"
                    rm -f "$keyfile_tmp"
                    echo -e "${GREEN}AES+RSA decryption done -> ${file%.enc}.dec${RESET}"
                    ;;
                4)
                    openssl enc -d -des-ede3-cbc -pbkdf2 -in "$file" -out "${file%.enc}.dec"
                    echo -e "${GREEN}3DES decryption done -> ${file%.enc}.dec${RESET}"
                    ;;
                *)
                    echo -e "${RED}Invalid algorithm choice${RESET}"
                    ;;
            esac
            echo
            ;;
        h|H)
            echo
            echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════════${RESET}"
            echo -e "${GREEN}${BOLD}                          ENCRYPTOR HELP MANUAL${RESET}"
            echo -e "${CYAN}${BOLD}════════════════════════════════════════════════════════════════════${RESET}"
            echo
            
            echo -e "${BLUE}${BOLD}MAIN OPTIONS:${RESET}"
            echo -e "${YELLOW}1) List files${RESET} - Shows all files in your current directory with details"
            echo -e "   (file size, permissions, modification date)"
            echo
            echo -e "${YELLOW}2) Encrypt a file${RESET} - Protects your file using cryptographic algorithms"
            echo -e "   • You'll be asked for the filename to encrypt"
            echo -e "   • Choose an encryption algorithm (see below)"
            echo -e "   • Enter a password when prompted"
            echo -e "   • Output: Creates an encrypted .enc file"
            echo
            echo -e "${YELLOW}3) Decrypt a file${RESET} - Restores your encrypted file to original form"
            echo -e "   • You'll be asked for the .enc filename to decrypt"
            echo -e "   • Choose the same algorithm used for encryption"
            echo -e "   • Enter the same password used for encryption"
            echo -e "   • Output: Creates a .dec file with original content"
            echo
            
            echo -e "${BLUE}${BOLD}ENCRYPTION ALGORITHMS:${RESET}"
            echo
            echo -e "${GREEN}${BOLD}AES-256 (Advanced Encryption Standard)${RESET} ${GREEN}[RECOMMENDED]${RESET}"
            echo -e "• Industry standard encryption algorithm"
            echo -e "• Uses 256-bit keys for maximum security"
            echo -e "• Fast encryption/decryption for any file size"
            echo -e "• Used by governments and financial institutions"
            echo -e "• What you'll need: Just a password"
            echo
            
            echo -e "${YELLOW}${BOLD}RSA (Rivest-Shamir-Adleman)${RESET} ${YELLOW}[FILES < 200 BYTES ONLY]${RESET}"
            echo -e "• Public-key cryptography algorithm"
            echo -e "• Uses mathematical key pairs (public/private)"
            echo -e "• Limited to very small files due to key size constraints"
            echo -e "• Automatically generates keys if not found"
            echo -e "• What you'll need: Nothing (keys auto-generated)"
            echo -e "• Files created: yourfile.enc, public.pem, private.pem"
            echo
            
            echo -e "${GREEN}${BOLD}AES+RSA Hybrid${RESET} ${GREEN}[VERY SECURE]${RESET}"
            echo -e "• Combines the best of both algorithms"
            echo -e "• AES encrypts your file (fast, any size)"
            echo -e "• RSA encrypts the AES key (secure key exchange)"
            echo -e "• Perfect for large files requiring maximum security"
            echo -e "• What you'll need: Password for AES encryption"
            echo -e "• Files created: yourfile.enc, yourfile.key.enc, public.pem, private.pem"
            echo
            
            echo -e "${RED}${BOLD}3DES (Triple Data Encryption Standard)${RESET} ${RED}[DEPRECATED]${RESET}"
            echo -e "• Legacy encryption algorithm (not recommended)"
            echo -e "• Slower than AES with weaker security"
            echo -e "• Included for compatibility with old systems only"
            echo -e "• What you'll need: Just a password"
            echo
            
            echo -e "${BLUE}${BOLD}SECURITY TIPS:${RESET}"
            echo -e "• Use strong passwords: mix of letters, numbers, symbols"
            echo -e "• Keep your private.pem key file safe and secret"
            echo -e "• For maximum security, use AES+RSA hybrid method"
            echo -e "• Always backup your keys and remember your passwords"
            echo -e "• Encrypted files are useless without correct password/keys"
            echo
            
            echo -e "${BLUE}${BOLD}FILE EXAMPLES:${RESET}"
            echo -e "• Original file: document.pdf"
            echo -e "• After AES encryption: document.pdf.enc"
            echo -e "• After decryption: document.pdf.dec"
            echo -e "• AES+RSA creates: document.pdf.enc + document.pdf.key.enc"
            echo
            
            echo -e "${MAGENTA}${BOLD}Press any key to return to main menu...${RESET}"
            read -n 1
            clear
            # Redraw header after help
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
            echo -e "${GREEN}${BOLD}                    Advanced Encryption Tool${RESET}"
            echo -e "${BLUE}                        Secure your files${RESET}"
            echo
            echo -e "${MAGENTA}═══════════════════════════════════════════════════════════════════${RESET}"
            echo
            ;;
        q|Q|4)
            echo
            echo -e "${MAGENTA}Thank you for using Encryptor!${RESET}"
            echo -e "${BLUE}Your files are now secure${RESET}"
            echo
            exit 0
            ;;
        *)
            echo -e "${RED}Invalid choice${RESET}"
            echo
            ;;
    esac
done