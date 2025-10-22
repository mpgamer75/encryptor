# 🔐 Encryptor v2.0.0 - Major Release

## Overview

We're excited to announce the release of **Encryptor v2.0.0**, a professional command-line file encryption tool featuring modern cryptographic algorithms, comprehensive X.509 certificate management, and an intuitive user experience.

Built with pure Bash and OpenSSL 3.x, Encryptor provides enterprise-grade encryption capabilities in a user-friendly interactive interface.

---

## 🎯 What's New in v2.0.0

### 🔒 Modern Encryption Algorithms
- **AES-256-CBC/CTR** - NSA-approved industry standard with PBKDF2 key derivation (100,000 iterations)
- **ChaCha20** - Modern stream cipher with constant-time operations
- **Camellia-256-CBC** - Japanese cryptographic standard (NTT)
- **ARIA-256-CBC** - Korean cryptographic standard (NSRI)
- **S/MIME** - Certificate-based asymmetric encryption for secure communications

### 🔑 Complete PKI/Certificate Management
- Root Certificate Authority (CA) creation with customizable details
- Private key and CSR generation
- Certificate signing with your own CA
- Certificate inspection with detailed analysis (validity, expiration, key strength)
- **PKCS#12 export** for Windows, browsers, and email clients
- **Certificate/Key pair validation** to ensure matching pairs
- **Expiration monitoring** with 30-day warnings
- Automatic permission management (400/600) for secure key storage

### 🛡️ Enhanced Security Features
- **Secure file deletion** with 3-pass overwrite (shred) after encryption/decryption
- **Integrated system security audit** - 6 comprehensive local checks
- **Remote SSL/TLS scanning** integration (testssl.sh support)
- **Comprehensive logging** of all encryption operations
- **Key location display** - Clear indication where certificates/keys are stored
- OpenSSL version detection and upgrade recommendations

### 🎨 User Experience Improvements
- **Modern SLANT ASCII art** - Distinct, professional visual identity
- **Color-coded interface** - Expanded palette (Green, Blue, Cyan, Magenta, Yellow, Orange, Purple)
- **Interactive file browser** with visual listing (sizes, permissions)
- **Smart selection** - Choose by number or full path
- **Detailed operation reports** with step-by-step decryption instructions
- **Contextual error messages** - Algorithm-specific troubleshooting tips
- **Multi-platform support** - Linux, macOS, WSL with automatic OS detection
- **Robust input handling** - Improved whitespace and special character support

### 📚 Installation & Documentation
- **One-line installation** - Automated setup with dependency checking
- Automatic shell configuration (Bash, Zsh, Fish)
- PATH configuration across multiple environments
- Complete README with detailed guides
- Algorithm documentation (ALGORITHMS.md)
- Usage examples (USAGE.md)

---

## 🚀 Installation

### Quick Install (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/mpgamer75/encryptor/main/install.sh | bash
```

The installer will:
- Detect your operating system and version
- Check OpenSSL capabilities (CMS, AEAD support)
- Verify all dependencies (Bash 4.0+, OpenSSL, Git, coreutils)
- Configure your shell automatically
- Provide upgrade recommendations if needed

### Manual Installation

```bash
git clone https://github.com/mpgamer75/encryptor.git
cd encryptor
chmod +x install.sh
./install.sh
```

### Debian Package (Alternative)

```bash
# Download the .deb package from releases
wget https://github.com/mpgamer75/encryptor/releases/download/v2.0.0/encryptor_2.0.0-1_all.deb

# Install
sudo dpkg -i encryptor_2.0.0-1_all.deb

# If dependencies are missing
sudo apt-get install -f
```

---

## 📋 Quick Start

### Encrypt a File
```bash
encryptor
# Select option [2] Encrypt a File
# Choose your algorithm (AES-256-CBC recommended for general use)
# Enter a strong password
# Done! Your file is securely encrypted
```

### Decrypt a File
```bash
encryptor
# Select option [3] Decrypt a File
# Choose the encrypted file
# Select the algorithm used for encryption
# Enter your password
# Done! File decrypted successfully
```

### Create a Certificate Authority
```bash
encryptor
# Select option [4] Certificate Manager
# Select option [1] Create Root Certificate Authority
# Follow the interactive prompts
# Your CA is ready to sign certificates
```

---

## 🔧 System Requirements

- **Operating System**: Linux (Ubuntu, Debian, CentOS), macOS, WSL
- **Bash**: Version 4.0 or higher
- **OpenSSL**: Version 1.1.1 or higher (OpenSSL 3.x recommended for modern algorithms)
- **Git**: For installation and testssl.sh integration
- **Optional**: shred (for secure file deletion), testssl.sh (for remote SSL scans)

---

## 📊 Algorithm Comparison

| Algorithm | Security | Speed | Use Case |
|-----------|----------|-------|----------|
| **AES-256-CBC** | ⭐⭐⭐⭐⭐ | Very Fast | General purpose (Recommended) |
| **AES-256-CTR** | ⭐⭐⭐⭐⭐ | Very Fast | Parallel processing, no padding |
| **ChaCha20** | ⭐⭐⭐⭐⭐ | Excellent | Modern, constant-time operations |
| **Camellia-256** | ⭐⭐⭐⭐⭐ | Fast | Japanese standard, AES alternative |
| **ARIA-256** | ⭐⭐⭐⭐⭐ | Fast | Korean standard, modern cipher |
| **S/MIME** | ⭐⭐⭐⭐⭐ | Medium | Certificate-based, secure sharing |

---

## 🔐 Security Highlights

- **PBKDF2 Key Derivation**: 100,000 iterations with SHA-256
- **Automatic Salt Generation**: Unique salt for each encryption operation
- **Secure Key Storage**: Automatic permission management (400 for private keys, 600 for certificates)
- **Secure Deletion**: 3-pass overwrite with shred or random data fallback
- **No Plaintext Storage**: Temporary files cleaned automatically on exit
- **Comprehensive Logging**: Track all operations for audit trails
- **OpenSSL Best Practices**: Industry-standard cryptographic implementation

---

## 📖 Documentation

- **[README.md](https://github.com/mpgamer75/encryptor/blob/main/README.md)** - Complete project documentation
- **[ALGORITHMS.md](https://github.com/mpgamer75/encryptor/blob/main/docs/ALGORITHMS.md)** - Detailed algorithm specifications
- **[USAGE.md](https://github.com/mpgamer75/encryptor/blob/main/docs/USAGE.md)** - Usage examples and guides
- **Man Page**: `man encryptor` (after Debian package installation)

---

## 🐛 Known Issues & Limitations

- S/MIME encryption requires recipient's public certificate
- Some modern algorithms require OpenSSL 3.x (automatic detection included)
- testssl.sh requires manual installation for remote SSL/TLS scans
- Windows native support not available (use WSL or Git Bash)

---

## 🔮 Roadmap for v2.1.0

- Batch encryption support (encrypt multiple files at once)
- Automatic compression before encryption (gzip/bzip2)
- Built-in secure password generator
- Usage statistics and dashboards
- Multilingual interface (French, Spanish, German)

---

## 🤝 Contributing

Contributions are welcome! Please feel free to submit issues, feature requests, or pull requests.

**How to contribute:**
1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

**Contribution areas:**
- 🐛 Bug reports and fixes
- 💡 New encryption algorithms or features
- 📖 Documentation improvements
- 🌐 Translations
- 🧪 Test cases and usage examples

---

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

---

## 🙏 Acknowledgments

- **OpenSSL Project** - For the robust cryptographic library
- **testssl.sh** - For SSL/TLS scanning capabilities
- **Open Source Community** - For continuous feedback and support

---

## 📦 Release Assets

### Downloads

- **Source Code**: `encryptor-v2.0.0.tar.gz` / `encryptor-v2.0.0.zip`
- **Debian Package**: `encryptor_2.0.0-1_all.deb`
- **Installation Script**: `install.sh`

### Checksums (SHA-256)

```
[CHECKSUM_DEB]  encryptor_2.0.0-1_all.deb
[CHECKSUM_TAR]  encryptor-v2.0.0.tar.gz
[CHECKSUM_ZIP]  encryptor-v2.0.0.zip
```

**Verify integrity:**
```bash
sha256sum -c checksums.txt
```

---

## 🔗 Links

- **Repository**: https://github.com/mpgamer75/encryptor
- **Issues**: https://github.com/mpgamer75/encryptor/issues
- **Discussions**: https://github.com/mpgamer75/encryptor/discussions
- **Author**: [@mpgamer75](https://github.com/mpgamer75)

---

## ⚠️ Disclaimer

This tool is provided for legitimate data protection purposes. Always use strong passwords and follow cryptographic best practices. The authors are not responsible for any misuse or data loss.

---

## 📝 Changelog Summary

### Added
- Modern encryption algorithms (ChaCha20, AES-CTR, Camellia, ARIA)
- Complete X.509 PKI management (CA creation, CSR, signing, inspection)
- PKCS#12 export for Windows/browser compatibility
- Certificate/key pair validation
- Certificate expiration monitoring
- Secure file deletion (3-pass shred)
- System security audit (6 checks)
- Remote SSL/TLS scanning integration
- Key location display for transparency
- SLANT ASCII art for distinct visual identity
- Expanded color palette for better UX
- Contextual error messages and troubleshooting

### Improved
- Robust input handling (whitespace, special characters)
- OS detection and OpenSSL compatibility checks
- Installation process with automatic shell configuration
- Error messages with algorithm-specific tips
- File selection with visual browser
- Documentation (README, ALGORITHMS, USAGE)

### Fixed
- AEAD cipher support through proper OpenSSL commands
- Input handling issues in menus and prompts
- File size display with proper error handling
- ASCII art alignment and spacing
- Version consistency across all files

### Changed
- Menu labels for clarity ("Local & Remote" instead of "Local & testssl.sh")
- Removed emoji indicators for better terminal compatibility
- Switched to pipe delimiter for algorithm descriptions

---

**Full Changelog**: https://github.com/mpgamer75/encryptor/compare/v1.0.0...v2.0.0

---

🎉 **Thank you for using Encryptor! Your feedback and contributions are greatly appreciated.**

**Found this useful? Please consider giving us a ⭐ on GitHub!**

