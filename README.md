<div align="center">

![Encryptor Logo](image/logo.png)

# Encryptor

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/Language-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS-blue.svg)](#compatibility)
[![Version](https://img.shields.io/badge/Version-2.0.0-brightgreen.svg)](https://github.com/mpgamer75/encryptor/releases)
[![Downloads](https://img.shields.io/github/downloads/mpgamer75/encryptor/total)](https://github.com/mpgamer75/encryptor/releases)

**Advanced file encryption tool with modern AEAD algorithms and comprehensive certificate management**

*Built with pure Bash and OpenSSL for maximum security and compatibility*

</div>

---

## Table of Contents

- [Overview](#overview)
- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Usage](#usage)
- [Encryption Algorithms](#encryption-algorithms)
- [Certificate Management](#certificate-management)
- [Security Audit](#security-audit)
- [Configuration](#configuration)
- [Uninstallation](#uninstallation)
- [Compatibility](#compatibility)
- [Security Considerations](#security-considerations)
- [Building Debian Package](#building-debian-package)
- [GitHub Release](#github-release)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

Encryptor is a modern, user-friendly command-line encryption tool designed for secure file protection. It leverages state-of-the-art AEAD (Authenticated Encryption with Associated Data) algorithms and provides comprehensive X.509 certificate management capabilities.

The tool features an intuitive interactive interface with color-coded menus, built-in security auditing, and support for both symmetric and asymmetric encryption methods.

## Features

### Core Encryption
- **Modern AEAD Ciphers**: AES-256-GCM and ChaCha20-Poly1305 for authenticated encryption
- **S/MIME Support**: Certificate-based asymmetric encryption for secure communications
- **PBKDF2 Key Derivation**: 100,000 iterations with SHA-256 for password-based encryption
- **Automatic Salt Generation**: Unique salt for each encryption operation

### Certificate Management
- **Root CA Creation**: Generate self-signed Certificate Authority certificates
- **CSR Generation**: Create Certificate Signing Requests with private keys
- **Certificate Signing**: Sign CSRs with your CA
- **Certificate Inspection**: View and analyze certificate details
- **Secure Key Storage**: Automatic permission management (400/600)

### Security Features
- **Security Audit**: Local system security checks
- **testssl.sh Integration**: Remote SSL/TLS server vulnerability scanning
- **OpenSSL Version Checks**: Ensure modern cryptographic libraries
- **Key Permission Validation**: Detect insecure private key permissions
- **Comprehensive Logging**: Track all encryption operations

### User Experience
- **Interactive Interface**: Color-coded menus with ASCII art headers
- **File Browser**: Visual file listing with icons and sizes
- **Smart File Selection**: Numbered menu or direct filename input
- **Automatic Naming**: Prevent file overwrites with timestamp suffixes
- **Real-time Reports**: Detailed encryption/decryption operation reports
- **Operation Timing**: Millisecond-precision performance metrics

## Installation

### One-Line Installation (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/mpgamer75/encryptor/main/install.sh | bash
```

This command will:
- Check system requirements (Bash, OpenSSL, Git, coreutils)
- Detect your shell configuration (Bash, Zsh, Fish)
- Download and install Encryptor
- Configure PATH automatically
- Verify installation

### Manual Installation

```bash
# Download the script
curl -fsSL https://raw.githubusercontent.com/mpgamer75/encryptor/main/encryptor.sh -o encryptor

# Make executable
chmod +x encryptor

# Install system-wide (requires sudo)
sudo mv encryptor /usr/local/bin/

# OR install for current user only
mkdir -p ~/.local/bin
mv encryptor ~/.local/bin/
export PATH="$HOME/.local/bin:$PATH"
```

### System Requirements

- **Bash**: Version 4.0 or higher
- **OpenSSL**: Version 1.1.1 or higher (3.x recommended)
- **Git**: Required for testssl.sh security audits
- **coreutils**: For numfmt (file size formatting)
- **less**: For viewing logs and certificates
- **Operating System**: Linux, macOS, or WSL (Windows Subsystem for Linux)

## Quick Start

```bash
# Launch interactive mode
encryptor

# Show version
encryptor --version

# Show help
encryptor --help
```

## Usage

### Interactive Mode

Encryptor launches in interactive mode by default, presenting a main menu:

```
1. List Files
2. Encrypt a File
3. Decrypt a File
4. Certificate Manager (X.509 / S/MIME)
5. Security Audit (Local & testssl.sh)
h. Help
l. View Logs
q. Quit
```

### Encrypting a File

1. Select option **2** from the main menu
2. Choose a file (by number or filename)
3. Select an encryption algorithm:
   - **AES-256-GCM**: Fast, hardware-accelerated (Recommended)
   - **ChaCha20-Poly1305**: Excellent performance, no hardware dependency
   - **S/MIME**: Certificate-based asymmetric encryption
4. Provide password or certificate as required
5. Review the encryption report

### Decrypting a File

1. Select option **3** from the main menu
2. Choose the encrypted file
3. Select the same algorithm used for encryption
4. Provide the correct password or private key/certificate
5. Review the decryption report

### File Naming Convention

- **Encrypted files**: `original_filename.enc`
- **Decrypted files**: `original_filename.dec`
- **Automatic suffixes**: Timestamped if file already exists (e.g., `file-1234567890.enc`)

## Encryption Algorithms

### AES-256-GCM (Recommended)

- **Type**: Symmetric AEAD (Authenticated Encryption with Associated Data)
- **Key Size**: 256 bits
- **Security**: Military-grade, NSA Suite B compliant
- **Performance**: Excellent with hardware acceleration (AES-NI)
- **Use Case**: General-purpose file encryption

**Technical Details**:
- Mode: Galois/Counter Mode (GCM) provides both confidentiality and authenticity
- Key Derivation: PBKDF2 with 100,000 iterations
- Salt: Random 64-bit salt per operation
- Authentication Tag: 128-bit for integrity verification

### ChaCha20-Poly1305

- **Type**: Symmetric AEAD stream cipher
- **Key Size**: 256 bits
- **Security**: Modern, cryptanalysis-resistant
- **Performance**: Excellent on all platforms, no hardware dependency
- **Use Case**: Systems without AES hardware acceleration

**Technical Details**:
- Cipher: ChaCha20 stream cipher
- MAC: Poly1305 for authentication
- Key Derivation: PBKDF2 with 100,000 iterations
- Design: Constant-time implementation resistant to side-channel attacks

### S/MIME (Certificate-based)

- **Type**: Asymmetric encryption using X.509 certificates
- **Cipher**: AES-256-GCM for actual file encryption
- **Key Exchange**: RSA public key cryptography
- **Use Case**: Secure communications, email encryption, recipient-specific encryption

**Technical Details**:
- File encrypted with symmetric AES-256-GCM
- AES key encrypted with recipient's RSA public key
- Supports certificate chains and trust hierarchies
- Decryption requires private key + certificate

## Certificate Management

Access the Certificate Manager via option **4** in the main menu.

### Create Root Certificate Authority

Generate a self-signed CA for signing other certificates:

```
CA Features:
- 4096-bit RSA key
- SHA-256 signature
- 10-year validity
- Secure key permissions (400)
```

### Generate Private Key and CSR

Create a private key and Certificate Signing Request:

```
Key Features:
- 2048-bit RSA key
- SHA-256 signature algorithm
- Customizable subject information
- Automatic secure permissions
```

### Sign Certificate Signing Request

Sign CSRs with your CA to create valid certificates:

```
Certificate Features:
- 365-day validity (configurable)
- SHA-256 signature
- Serial number tracking
```

### Certificate Inspection

View detailed certificate information:

```
Details Shown:
- Subject and Issuer information
- Validity period
- Public key details
- Signature algorithm
- Extensions and key usage
```

### Managed Files Location

All certificates and keys are stored in:
```
~/.config/encryptor/certs/
```

## Security Audit

Access security auditing via option **5** in the main menu.

### Local System Audit

Checks your local security configuration:

1. **OpenSSL Version Check**
   - Verifies OpenSSL version (1.1.1+ or 3.x required)
   - Warns about outdated versions

2. **Private Key Permissions Check**
   - Scans managed keys in `~/.config/encryptor/certs/`
   - Identifies insecure permissions (not 400/600)
   - Provides fix commands

### testssl.sh Server Scan

Comprehensive SSL/TLS security testing:

1. Install testssl.sh (option 3 in Security Audit menu)
2. Run scan on any domain/IP (option 2)
3. Review detailed vulnerability reports

**testssl.sh checks**:
- SSL/TLS protocol support
- Cipher suite strength
- Certificate validity
- Known vulnerabilities (Heartbleed, POODLE, etc.)
- Security headers

## Configuration

### Configuration Directory

```
~/.config/encryptor/
├── certs/           # Managed certificates and keys
├── tools/           # Downloaded tools (testssl.sh)
└── encryptor.log    # Operation logs
```

### Logs

View operation logs via option **l** in the main menu:

```
Log Format:
[YYYY-MM-DD HH:MM:SS] [LEVEL] Message

Levels:
- INFO: General operations
- SUCCESS: Successful encryption/decryption
- ERROR: Failed operations
```

### Temporary Files

Temporary files are created in:
```
/tmp/encryptor_$$
```

All temporary files are automatically cleaned up on exit.

## Uninstallation

### Using the Uninstall Script

```bash
curl -fsSL https://raw.githubusercontent.com/mpgamer75/encryptor/main/uninstall.sh | bash
```

### Manual Uninstallation

```bash
# Remove binary
sudo rm -f /usr/local/bin/encryptor
rm -f ~/.local/bin/encryptor

# Optional: Remove configuration and certificates
rm -rf ~/.config/encryptor

# Optional: Remove PATH configuration from shell config
# Edit ~/.bashrc, ~/.zshrc, or ~/.config/fish/config.fish
# Remove lines containing "export PATH=.*\.local/bin"
```

## Compatibility

### Operating Systems

- **Linux**: Fully supported (all distributions)
- **macOS**: Fully supported (10.15+)
- **WSL**: Fully supported (Windows Subsystem for Linux)
- **BSD**: Should work (not officially tested)

### Shell Compatibility

- **Bash**: 4.0+ (recommended)
- **Zsh**: Fully compatible
- **Fish**: PATH configuration handled automatically
- **Other POSIX shells**: Basic functionality

### Terminal Requirements

- **Color Support**: Optional (fallback to plain text)
- **Unicode Support**: Recommended for icons (optional)
- **Terminal Emulators**: All modern emulators supported

## Security Considerations

### Password Security

- **Minimum Length**: 12+ characters recommended
- **Complexity**: Use uppercase, lowercase, numbers, symbols
- **Uniqueness**: Different password for each sensitive file
- **Storage**: Never store passwords in plain text

### Key Management

- **Private Keys**: Stored with 400 permissions (owner read-only)
- **Backup Strategy**: Keep secure offline backups
- **Access Control**: Limit access to certificate directory
- **Rotation**: Periodically rotate certificates and keys

### Algorithm Selection

- **Default Recommendation**: AES-256-GCM
- **For Shared Computers**: ChaCha20-Poly1305 (constant-time)
- **For Recipient-Specific**: S/MIME with certificates
- **Hardware Acceleration**: AES-256-GCM benefits from AES-NI

### Best Practices

1. **Verify Decryption**: Always test decryption before deleting originals
2. **Secure Deletion**: Use `shred` or similar for sensitive plaintext files
3. **Regular Audits**: Run security audit periodically
4. **Update OpenSSL**: Keep OpenSSL updated for security patches
5. **Certificate Validation**: Verify certificate authenticity before use

### Known Limitations

- **Password Visibility**: Passwords visible during typing (terminal limitation)
- **Memory Protection**: Basic password handling (no mlockall)
- **File Metadata**: Original filename visible in encrypted file context
- **Compression**: No built-in compression (consider pre-compression)

## Building Debian Package

### Prerequisites

To build the Debian package, you need:

```bash
# Ubuntu/Debian
sudo apt-get install build-essential fakeroot dpkg-dev

# Verify tools
which dpkg-deb fakeroot
```

### Build Instructions

```bash
# Navigate to project directory
cd encryptor

# Make build script executable
chmod +x build_deb.sh

# Build the package
./build_deb.sh
```

This creates: `encryptor_2.0.0-1_all.deb`

### Install Local Package

```bash
# Install the package
sudo dpkg -i encryptor_2.0.0-1_all.deb

# If dependencies are missing:
sudo apt-get install -f

# Verify installation
encryptor --version
which encryptor
man encryptor
```

### Test Package

```bash
# View package information
dpkg-deb --info encryptor_2.0.0-1_all.deb

# List package contents
dpkg-deb --contents encryptor_2.0.0-1_all.deb

# Validate package (optional)
lintian encryptor_2.0.0-1_all.deb
```

## GitHub Release

### Creating a Release

Follow these steps to create a GitHub release:

1. **Build the Debian package**:
   ```bash
   ./build_deb.sh
   ```

2. **Commit and tag**:
   ```bash
   git add .
   git commit -m "Release v2.0.0"
   git tag -a v2.0.0 -m "Encryptor v2.0.0 - Modern AEAD Encryption"
   git push origin main
   git push origin v2.0.0
   ```

3. **Create GitHub Release**:
   - Go to repository **Releases** section
   - Click **Create a new release**
   - Select tag: `v2.0.0`
   - Title: `Encryptor v2.0.0 - Modern AEAD Encryption`
   - Upload `encryptor_2.0.0-1_all.deb` as asset
   - Publish release

4. **Calculate checksums**:
   ```bash
   sha256sum encryptor_2.0.0-1_all.deb
   ```
   Add checksum to release notes.

### Download from Release

Users can download and install from GitHub releases:

```bash
# Download latest .deb package
wget https://github.com/mpgamer75/encryptor/releases/download/v2.0.0/encryptor_2.0.0-1_all.deb

# Install
sudo dpkg -i encryptor_2.0.0-1_all.deb

# Or use one-line install
curl -fsSL https://raw.githubusercontent.com/mpgamer75/encryptor/main/install.sh | bash
```

### Release Checklist

Before creating a release, ensure:

- [ ] Version updated in all files (`encryptor.sh`, `install.sh`, `README.md`, `debian/control`, `debian/changelog`)
- [ ] CHANGELOG updated with new features
- [ ] Documentation updated
- [ ] All tests pass
- [ ] Build script works: `./build_deb.sh`
- [ ] Package installs correctly: `sudo dpkg -i encryptor_2.0.0-1_all.deb`
- [ ] One-line installer works from GitHub
- [ ] Man page displays correctly: `man encryptor`

For detailed release instructions, see [.github-release-guide.md](.github-release-guide.md)

## Contributing

Contributions are welcome! Please follow these guidelines:

1. **Bug Reports**: Use GitHub Issues with detailed reproduction steps
2. **Feature Requests**: Describe use case and expected behavior
3. **Pull Requests**: Include tests and documentation updates
4. **Security Issues**: Follow responsible disclosure (see SECURITY.md)

### Development Setup

```bash
# Clone repository
git clone https://github.com/mpgamer75/encryptor.git
cd encryptor

# Run directly
./encryptor.sh

# Test installation
./install.sh
```

### Code Style

- Follow existing Bash style conventions
- Use shellcheck for linting
- Add comments for complex logic
- Test on multiple platforms

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

Copyright (c) 2024 mpgamer75

```
MIT License Summary:
- Commercial use allowed
- Modification allowed
- Distribution allowed
- Private use allowed
- No warranty provided
```

---

## Support

- **Documentation**: See [docs/USAGE.md](docs/USAGE.md) and [docs/ALGORITHMS.md](docs/ALGORITHMS.md)
- **Issues**: [GitHub Issues](https://github.com/mpgamer75/encryptor/issues)
- **Discussions**: [GitHub Discussions](https://github.com/mpgamer75/encryptor/discussions)

---

**Made with security in mind. Use responsibly.**
