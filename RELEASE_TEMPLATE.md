# Encryptor v2.0.0

Major release featuring modern AEAD algorithms and comprehensive certificate management.

## Highlights

- Modern AEAD ciphers: **AES-256-GCM** and **ChaCha20-Poly1305**
- **S/MIME** certificate-based encryption
- Complete **X.509 certificate management** (CA, CSR, signing)
- Integrated **security audit tools** (local + testssl.sh)
- Enhanced UI with color-coded menus and ASCII art
- Performance monitoring with millisecond precision
- Comprehensive logging system

## Installation

### Quick Install (One-Line)

```bash
curl -fsSL https://raw.githubusercontent.com/mpgamer75/encryptor/main/install.sh | bash
```

### Debian/Ubuntu Package

```bash
# Download the .deb package from Assets below
wget https://github.com/mpgamer75/encryptor/releases/download/v2.0.0/encryptor_2.0.0-1_all.deb

# Install
sudo dpkg -i encryptor_2.0.0-1_all.deb

# If dependencies missing:
sudo apt-get install -f
```

### Manual Installation

```bash
# Download script
wget https://raw.githubusercontent.com/mpgamer75/encryptor/main/encryptor.sh

# Install
chmod +x encryptor.sh
sudo mv encryptor.sh /usr/local/bin/encryptor
```

## What's New in v2.0.0

### Core Encryption
- Added AES-256-GCM (AEAD) with hardware acceleration support
- Added ChaCha20-Poly1305 (AEAD) for constant-time operations
- Implemented S/MIME with X.509 certificates
- PBKDF2 key derivation with 100,000 iterations
- Automatic salt generation per encryption

### Certificate Management
- Root CA creation (4096-bit RSA, 10-year validity)
- Private key and CSR generation
- Certificate signing with custom CA
- Certificate inspection and validation
- Managed storage in `~/.config/encryptor/certs/`
- Automatic secure permissions (400/600)

### Security Features
- Local system security audit
- OpenSSL version validation
- Private key permission checks
- testssl.sh integration for SSL/TLS scanning
- Comprehensive operation logging

### User Experience
- Color-coded interactive interface
- ASCII art headers
- Visual file browser with icons
- Smart file selection (numbered or direct)
- Automatic file naming with timestamp suffixes
- Real-time operation reports with metrics
- Millisecond-precision timing

### Platform Support
- Linux (all distributions)
- macOS (10.15+)
- WSL (Windows Subsystem for Linux)
- Multi-shell support (Bash, Zsh, Fish)

## System Requirements

- **Bash**: 4.0+
- **OpenSSL**: 1.1.1+ (3.x recommended)
- **Git**: For security audit tools
- **coreutils**: For file size formatting
- **less**: For log viewing

## Upgrade from Previous Version

```bash
# Uninstall old version
curl -fsSL https://raw.githubusercontent.com/mpgamer75/encryptor/main/uninstall.sh | bash

# Install new version
curl -fsSL https://raw.githubusercontent.com/mpgamer75/encryptor/main/install.sh | bash
```

## Documentation

- [README.md](https://github.com/mpgamer75/encryptor/blob/main/README.md) - Complete documentation
- [USAGE.md](https://github.com/mpgamer75/encryptor/blob/main/docs/USAGE.md) - Usage guide
- [ALGORITHMS.md](https://github.com/mpgamer75/encryptor/blob/main/docs/ALGORITHMS.md) - Algorithm details

## Checksums

**SHA256:**
```
[REPLACE WITH ACTUAL SHA256 AFTER BUILD]
```

To verify:
```bash
sha256sum encryptor_2.0.0-1_all.deb
```

**Calculate checksum:**
```bash
sha256sum encryptor_2.0.0-1_all.deb > encryptor_2.0.0-1_all.deb.sha256
```

## Support

- **Issues**: [GitHub Issues](https://github.com/mpgamer75/encryptor/issues)
- **Discussions**: [GitHub Discussions](https://github.com/mpgamer75/encryptor/discussions)

## License

MIT License - See [LICENSE](https://github.com/mpgamer75/encryptor/blob/main/LICENSE)

---

**Full Changelog**: https://github.com/mpgamer75/encryptor/compare/v1.0.0...v2.0.0

