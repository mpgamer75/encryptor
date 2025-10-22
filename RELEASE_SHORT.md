# 🔐 Encryptor v2.0.0

Professional command-line file encryption tool with modern algorithms, comprehensive PKI management, and intuitive UX.

## ✨ What's New

### 🔒 Modern Encryption
- **5 Modern Algorithms**: AES-256 (CBC/CTR), ChaCha20, Camellia-256, ARIA-256, S/MIME
- **PBKDF2**: 100,000 iterations for strong password-based encryption
- **Secure Deletion**: Optional 3-pass shred for original files

### 🔑 Complete PKI Management
- Root CA creation with customizable details
- CSR generation and signing
- PKCS#12 export (Windows/browsers)
- Certificate validation and expiration monitoring
- Automatic permission management

### 🛡️ Enhanced Security
- System security audit (6 local checks)
- Remote SSL/TLS scanning (testssl.sh integration)
- Comprehensive operation logging
- Key location transparency

### 🎨 User Experience
- SLANT ASCII art (modern, professional)
- Expanded color palette
- Interactive file browser
- Detailed operation reports
- Contextual error messages
- Multi-platform support (Linux, macOS, WSL)

## 🚀 Quick Install

```bash
curl -fsSL https://raw.githubusercontent.com/mpgamer75/encryptor/main/install.sh | bash
```

Or download the Debian package: `encryptor_2.0.0-1_all.deb`

## 📋 Usage

```bash
encryptor              # Launch interactive menu
encryptor --version    # Show version
encryptor --help       # Show help
```

## 📚 Documentation

- [Complete README](https://github.com/mpgamer75/encryptor/blob/main/README.md)
- [Algorithm Guide](https://github.com/mpgamer75/encryptor/blob/main/docs/ALGORITHMS.md)
- [Usage Examples](https://github.com/mpgamer75/encryptor/blob/main/docs/USAGE.md)

## 🔧 Requirements

- Bash 4.0+
- OpenSSL 1.1.1+ (3.x recommended)
- Linux, macOS, or WSL

## 📦 Assets

- `encryptor_2.0.0-1_all.deb` - Debian package
- Source code (tar.gz / zip)

**Checksums (SHA-256):**
```
[Add checksums after building]
```

## 🤝 Contributing

Contributions welcome! Submit issues, feature requests, or PRs.

## 📜 License

MIT License - See [LICENSE](LICENSE) file

---

**Full Release Notes**: [See RELEASE_v2.0.0.md](https://github.com/mpgamer75/encryptor/blob/main/RELEASE_v2.0.0.md)

**Changelog**: v1.0.0 → v2.0.0

---

⭐ **If you find this useful, please star the repository!**

