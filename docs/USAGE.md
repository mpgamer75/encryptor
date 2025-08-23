# 📚 Encryptor Usage Guide

A comprehensive guide to using Encryptor for secure file encryption and decryption.

## Table of Contents

- [Quick Start](#quick-start)
- [Installation](#installation)
- [Basic Usage](#basic-usage)
- [Interactive Mode](#interactive-mode)
- [Command Line Options](#command-line-options)
- [Encryption Examples](#encryption-examples)
- [Decryption Examples](#decryption-examples)
- [File Management](#file-management)
- [Security Guidelines](#security-guidelines)
- [Troubleshooting](#troubleshooting)
- [Advanced Usage](#advanced-usage)
- [Integration Examples](#integration-examples)

## Quick Start

```bash
# Install Encryptor
curl -fsSL https://raw.githubusercontent.com/mpgamer75/encryptor/main/install.sh | bash

# Launch interactive mode
encryptor

# Show help
encryptor --help

# Show version
encryptor --version
```

## Installation

### Automatic Installation (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/mpgamer75/encryptor/main/install.sh | bash
```

The installer will:
- ✅ Check system requirements (Bash, OpenSSL)
- ✅ Detect your shell (Zsh, Bash, Fish, etc.)
- ✅ Download and install Encryptor
- ✅ Configure PATH automatically
- ✅ Test the installation

### Manual Installation

```bash
# Download the script
wget https://raw.githubusercontent.com/mpgamer75/encryptor/main/encryptor.sh

# Make executable and install
chmod +x encryptor.sh
sudo mv encryptor.sh /usr/local/bin/encryptor

# Or install locally
mkdir -p ~/.local/bin
mv encryptor.sh ~/.local/bin/encryptor
export PATH="$HOME/.local/bin:$PATH"
```

### System Requirements

- **Bash**: 4.0 or higher
- **OpenSSL**: 1.1.0 or higher
- **Operating System**: Linux, macOS, or WSL
- **Storage**: Minimal (< 1MB)

## Basic Usage

Encryptor operates in **interactive mode** by default, providing a user-friendly menu-driven interface.

```bash
# Launch Encryptor
encryptor
```

You'll see the main menu:
```
🏠 Main Menu
─────────────
1) List files in current directory
2) Encrypt a file 🔐
3) Decrypt a file 🔓
h) Help manual 📖
v) Show version
q) Quit
```

## Interactive Mode

### Main Menu Navigation

| Option | Action | Description |
|--------|--------|-------------|
| `1` | List Files | Show all files in current directory with icons and sizes |
| `2` | Encrypt | Start the file encryption workflow |
| `3` | Decrypt | Start the file decryption workflow |
| `h` | Help | Display algorithm explanations and security info |
| `v` | Version | Show Encryptor version and build information |
| `q` | Quit | Exit Encryptor |

### File Listing

When you select option `1`, Encryptor displays files with visual indicators:

```
📁 Files in current directory:

  📝 document.txt (2.3K)
  🖼️  photo.jpg (1.2M)
  📋 report.pdf (856K)
  🔒 secret.txt.enc (2.4K)
  📦 archive.zip (15M)
```

**File Icons:**
- 📄 Generic files
- 📝 Text files (.txt, .md)
- 📋 PDF documents
- 🖼️ Images (.jpg, .png, .gif)
- 🎬 Videos (.mp4, .avi, .mov)
- 🎵 Audio (.mp3, .wav, .flac)
- 📦 Archives (.zip, .tar, .gz)
- 🔒 Encrypted files (.enc)

## Command Line Options

```bash
# Show version information
encryptor --version
encryptor -v

# Display help message
encryptor --help
encryptor -h

# Interactive mode (default)
encryptor
```

## Encryption Examples

### Example 1: Basic AES-256 Encryption

```bash
encryptor
# Select: 2) Encrypt a file
# Enter filename: document.txt
# Choose algorithm: 1) AES-256 (Recommended)
# Enter password: [your secure password]
# Result: document.txt.enc created
```

**What happens:**
- Original file: `document.txt`
- Encrypted file: `document.txt.enc`
- Algorithm: AES-256-CBC with PBKDF2
- Password protection: Your chosen password

### Example 2: RSA Encryption (Small Files)

```bash
encryptor
# Select: 2) Encrypt a file
# Enter filename: password.txt
# Choose algorithm: 2) RSA (Small files only)
# Result: password.txt.enc, password.txt.key, password.txt.pub created
```

**Generated files:**
- `password.txt.enc` - Encrypted file
- `password.txt.key` - RSA private key (keep secret!)
- `password.txt.pub` - RSA public key (can share)

⚠️ **Note**: RSA is limited to files smaller than ~200 bytes.

### Example 3: Maximum Security (Hybrid AES+RSA)

```bash
encryptor
# Select: 2) Encrypt a file
# Enter filename: confidential.pdf
# Choose algorithm: 3) Hybrid AES+RSA (Maximum security)
# Result: Multiple files created for maximum security
```

**Generated files:**
- `confidential.pdf.enc` - AES-encrypted file
- `confidential.pdf.enc.key.enc` - RSA-encrypted AES key
- `confidential.pdf.key` - RSA private key

### Example 4: Legacy 3DES Encryption

```bash
encryptor
# Select: 2) Encrypt a file
# Enter filename: legacy_data.txt
# Choose algorithm: 4) 3DES (Legacy)
# Enter password: [your secure password]
# Result: legacy_data.txt.enc created
```

## Decryption Examples

### Example 1: AES-256 Decryption

```bash
encryptor
# Select: 3) Decrypt a file
# Enter filename: document.txt.enc
# Choose algorithm: 1) AES-256
# Enter password: [same password used for encryption]
# Result: document.txt.dec created
```

### Example 2: RSA Decryption

```bash
encryptor
# Select: 3) Decrypt a file
# Enter filename: password.txt.enc
# Choose algorithm: 2) RSA
# Enter private key filename: password.txt.key
# Result: password.txt.dec created
```

### Example 3: Hybrid AES+RSA Decryption

```bash
encryptor
# Select: 3) Decrypt a file
# Enter filename: confidential.pdf.enc
# Choose algorithm: 3) Hybrid AES+RSA
# Enter encrypted key filename: confidential.pdf.enc.key.enc
# Enter private key filename: confidential.pdf.key
# Result: confidential.pdf.dec created
```

## File Management

### Automatic File Naming

Encryptor automatically handles file naming to prevent overwrites:

```bash
# Original file
document.txt

# First encryption
document.txt.enc

# If document.txt.enc exists, creates:
document.txt.enc.1

# If document.txt.enc.1 exists, creates:
document.txt.enc.2
```

### File Extensions

| Extension | Description |
|-----------|-------------|
| `.enc` | Encrypted file |
| `.dec` | Decrypted file |
| `.key` | RSA private key |
| `.pub` | RSA public key |
| `.key.enc` | RSA-encrypted AES key |

### Secure File Handling

Encryptor follows security best practices:

- **Temporary files**: Created in `/tmp/encryptor_$$` with secure permissions
- **Automatic cleanup**: All temporary files removed on exit
- **Original files**: Never modified during encryption
- **Memory protection**: No plaintext passwords stored in variables

## Security Guidelines

### Password Best Practices

✅ **Do:**
- Use passwords with 12+ characters
- Include uppercase, lowercase, numbers, and symbols
- Use unique passwords for each file
- Use a password manager

❌ **Don't:**
- Reuse passwords across multiple files
- Use dictionary words or personal information
- Store passwords in plain text files
- Share passwords over insecure channels

### Key Management (RSA/Hybrid)

✅ **Private Keys:**
- Store in secure location with restricted permissions
- Create secure backups
- Never share private keys
- Use strong passphrases for key files

✅ **Public Keys:**
- Can be shared freely
- Verify authenticity before use
- Keep copies for reference

### File Security

✅ **Best Practices:**
- Securely delete original files after encryption
- Verify encrypted files before deleting originals
- Test decryption before relying on encrypted files
- Keep secure backups of important encrypted data

## Troubleshooting

### Common Issues

#### "Command not found: encryptor"

**Solution:**
```bash
# Check if installed
ls -la ~/.local/bin/encryptor

# Add to PATH temporarily
export PATH="$HOME/.local/bin:$PATH"

# Add to shell config permanently
echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.bashrc
source ~/.bashrc
```

#### "OpenSSL not found"

**Solution:**
```bash
# Ubuntu/Debian
sudo apt update && sudo apt install openssl

# CentOS/RHEL
sudo yum install openssl

# macOS
brew install openssl
```

#### "Permission denied"

**Solution:**
```bash
# Make script executable
chmod +x ~/.local/bin/encryptor

# Check file permissions
ls -la ~/.local/bin/encryptor
```

#### "File too large for RSA"

RSA encryption is limited to ~200 bytes. **Solutions:**

1. **Use AES-256** for larger files
2. **Use Hybrid AES+RSA** for maximum security with large files
3. **Split large files** into smaller chunks (not recommended)

#### "Wrong password" error

**Solutions:**
1. Verify you're using the correct password
2. Check if file was encrypted with different algorithm
3. Ensure file hasn't been corrupted
4. Try decryption with different algorithm

### Debug Mode

For troubleshooting, you can enable debug output:

```bash
# Run with debug information
bash -x ~/.local/bin/encryptor
```

### Log Files

Encryptor doesn't create persistent logs for security reasons, but you can capture output:

```bash
# Capture session output
encryptor 2>&1 | tee encryptor_session.log

# Remember to securely delete logs containing sensitive information
shred -u encryptor_session.log
```

## Advanced Usage

### Batch Operations

While Encryptor doesn't have built-in batch operations, you can script them:

```bash
# Encrypt multiple files with AES-256
for file in *.txt; do
    echo "Encrypting $file..."
    echo -e "2\n$file\n1\nmypassword" | encryptor
done
```

⚠️ **Warning**: This method exposes passwords in command history. Use with caution.

### Integration with Other Tools

#### Git Hooks

```bash
#!/bin/bash
# Pre-commit hook to encrypt sensitive files
encryptor << EOF
2
secrets.txt
1
$ENCRYPTION_PASSWORD
q
EOF
```

#### Backup Scripts

```bash
#!/bin/bash
# Automated backup with encryption
tar czf backup.tar.gz /important/data/
encryptor << EOF
2
backup.tar.gz
3
q
EOF
rm backup.tar.gz  # Remove unencrypted backup
```

### Custom Workflows

#### Secure File Sharing

1. **Sender:**
   ```bash
   # Encrypt with hybrid method
   encryptor  # Choose file, select Hybrid AES+RSA
   
   # Share: encrypted_file.enc + encrypted_key.key.enc
   # Keep: private.key (secret)
   ```

2. **Receiver:**
   ```bash
   # Receive: encrypted_file.enc + encrypted_key.key.enc + private.key
   encryptor  # Decrypt with Hybrid method
   ```

## Integration Examples

### Cron Jobs

```bash
# Daily backup encryption
0 2 * * * /home/user/backup_encrypt.sh

# backup_encrypt.sh content:
#!/bin/bash
cd /home/user/backups
for file in backup_*.sql; do
    if [[ ! -f "${file}.enc" ]]; then
        echo "backup_password" | encryptor << EOF
2
$file
1
backup_password
q
EOF
    fi
done
```

### CI/CD Pipelines

```bash
# GitHub Actions example
- name: Encrypt sensitive files
  run: |
    echo "$ENCRYPTION_PASSWORD" | encryptor << EOF
    2
    config/secrets.json
    1
    $ENCRYPTION_PASSWORD
    q
    EOF
```

### Shell Aliases

Add to your shell configuration:

```bash
# ~/.bashrc or ~/.zshrc
alias encrypt='encryptor'
alias enc-aes='echo -e "2\n\$1\n1\n" | encryptor'
alias enc-hybrid='echo -e "2\n\$1\n3\n" | encryptor'

# Usage:
# enc-aes myfile.txt
# enc-hybrid sensitive.pdf
```

## Performance Tips

### Large Files

- **Use AES-256 or Hybrid** for files > 1MB
- **Avoid RSA** for files > 200 bytes
- **Consider file compression** before encryption for better performance

### System Resources

- **RAM Usage**: Minimal (< 10MB during operation)
- **CPU Usage**: Depends on algorithm (AES < Hybrid < RSA)
- **Disk Space**: Encrypted files are slightly larger than originals

### Optimization

```bash
# For maximum performance, ensure:
# 1. SSD storage for temporary files
# 2. Sufficient RAM (4GB+ recommended)
# 3. Modern CPU with AES-NI support
```

---

## Getting Help

- **Built-in Help**: Press `h` in the main menu
- **Algorithm Guide**: See [ALGORITHMS.md](ALGORITHMS.md)
- **Command Help**: Run `encryptor --help`
- **GitHub Issues**: Report bugs and request features
- **Security Concerns**: Follow responsible disclosure practices

## Next Steps

1. **Practice**: Try encrypting/decrypting test files
2. **Security**: Review the [ALGORITHMS.md](ALGORITHMS.md) guide
3. **Integration**: Incorporate into your security workflows
4. **Contribute**: Help improve Encryptor on GitHub

Remember: **Good security practices matter more than complex tools.** Use strong passwords, manage your keys securely, and always verify your encrypted files work before relying on them.