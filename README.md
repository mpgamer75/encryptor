<div align="center">

![Encryptor Logo](image/logo.png)

# 🔐 Encryptor

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/Language-Bash-green.svg)](https://www.gnu.org/software/bash/)
[![Platform](https://img.shields.io/badge/Platform-Linux%20%7C%20macOS-blue.svg)](#compatibility)
[![Version](https://img.shields.io/badge/Version-1.0.0-brightgreen.svg)](https://github.com/mpgamer75/encryptor/releases)
[![Downloads](https://img.shields.io/github/downloads/mpgamer75/encryptor/total)](https://github.com/mpgamer75/encryptor/releases)

**Advanced file encryption tool with multiple algorithms and intuitive interface**

*Built with pure Bash and OpenSSL for maximum security and compatibility*

---

</div>

## 🚀 **Key Features**

- 🔒 **Multiple Encryption Algorithms**: AES-256, RSA, Hybrid AES+RSA, and 3DES
- 🎨 **Beautiful CLI Interface**: Colorful, intuitive menus with clear guidance
- 🛡️ **Military-Grade Security**: Industry-standard encryption used by governments
- ⚡ **Fast & Lightweight**: Pure Bash implementation with minimal dependencies
- 🔑 **Smart Key Management**: Automatic RSA key generation and secure handling
- 📁 **File Safety**: Automatic backup naming to prevent accidental overwrites
- 📖 **Built-in Help**: Comprehensive manual with algorithm explanations
- 🎯 **Cross-Platform**: Works on Linux, macOS, and WSL

## 📦 **Installation**

### 🌟 Ubuntu/Debian Users (Recommended)

**Single command installation with native package management:**

```bash
# Download and install .deb package
wget https://github.com/mpgamer75/encryptor/releases/latest/download/encryptor_1.0.0-1_all.deb
sudo dpkg -i encryptor_1.0.0-1_all.deb

# Fix dependencies if needed
sudo apt-get install -f
```

**Benefits:**

- ✅ Native package management integration
- ✅ Automatic dependency resolution
- ✅ Easy updates with `apt upgrade`
- ✅ Clean uninstallation with `apt remove encryptor`
- ✅ Man page included (`man encryptor`)

### 🔧 All Linux/macOS Systems

**Universal installation script for any POSIX system:**

```bash
curl -fsSL https://raw.githubusercontent.com/mpgamer75/encryptor/main/install.sh | bash
```

### 📋 Manual Installation

**For advanced users or custom setups:**

```bash
git clone https://github.com/mpgamer75/encryptor.git
cd encryptor
chmod +x install.sh
./install.sh
```

### ⚡ Direct Download

**Minimal setup for quick testing:**

```bash
wget https://raw.githubusercontent.com/mpgamer75/encryptor/main/encryptor.sh
chmod +x encryptor.sh
sudo mv encryptor.sh /usr/local/bin/encryptor
```

## 🚀 **Quick Start**

```bash
# Launch Encryptor
encryptor

# Follow the intuitive menu:
# 1) List files
# 2) Encrypt a file  
# 3) Decrypt a file
# h) Help manual
# q) Quit
```

## 🔐 **Encryption Algorithms**

| Algorithm | Security Level | Best For | File Size Limit |
|-----------|---------------|----------|-----------------|
| **AES-256** | ⭐⭐⭐⭐⭐ | General use, fast encryption | Unlimited |
| **AES+RSA Hybrid** | ⭐⭐⭐⭐⭐ | Maximum security, key exchange | Unlimited |
| **RSA** | ⭐⭐⭐⭐ | Small files, public key crypto | < 200 bytes |
| **3DES** | ⭐⭐⭐ | Legacy compatibility | Unlimited |

### 🛡️ **Security Features**

- **PBKDF2** key derivation with salt
- **Modern OpenSSL** commands (pkeyutl vs deprecated rsautl)
- **Secure temporary files** with automatic cleanup
- **Strong random key generation** for hybrid encryption
- **No plaintext password storage**

## 🏗️ **Tech Stack**

- **Language**: Bash 4.0+
- **Cryptography**: OpenSSL
- **Interface**: ANSI escape sequences for colors
- **Platform**: POSIX-compliant systems
- **Package Format**: Debian (.deb) for Linux distributions

## 🎯 **Project Mission**

In an era where data breaches and privacy violations are rampant, **Encryptor** addresses the critical need for accessible, robust file encryption. Many users find existing encryption tools either too complex or lacking in security features.

**Encryptor bridges this gap by providing**:

- **Enterprise-level security** with a **consumer-friendly interface**
- **Multiple encryption options** to match different security requirements
- **Educational value** through built-in algorithm explanations
- **Zero learning curve** with guided workflows

Whether you're a security professional, developer, or privacy-conscious individual, Encryptor empowers you to protect your sensitive data without compromise.

## 📊 **Usage Examples**

### Encrypt a Document

```bash
encryptor
# Select: 2) Encrypt a file
# Enter: document.pdf
# Choose: 1) AES-256 (Recommended)
# Result: document.pdf.enc
```

### Decrypt with Maximum Security

```bash
encryptor  
# Select: 3) Decrypt a file
# Enter: secret.enc
# Choose: 3) AES+RSA
# Enter: secret.key.enc
# Result: secret.dec
```

### View Help Manual

```bash
encryptor
# Select: h) Help manual
# Browse comprehensive algorithm guide
```

## 🔧 **Requirements**

- **Bash** 4.0 or higher
- **OpenSSL** 1.1.0 or higher
- **Linux/macOS/WSL** environment
- **Terminal** with ANSI color support

## 🧪 **Compatibility**

| OS | Status | Installation Method |
|----|--------|---------------------|
| Ubuntu 18.04+ | ✅ Fully Supported | `.deb` package or script |
| Debian 10+ | ✅ Fully Supported | `.deb` package or script |
| CentOS 7+ | ✅ Fully Supported | Installation script |
| macOS 10.14+ | ✅ Fully Supported | Installation script |
| Windows WSL | ✅ Fully Supported | `.deb` package or script |
| Alpine Linux | ✅ Fully Supported | Installation script |

## 📦 **Package Management**

**For Debian/Ubuntu users with .deb package:**

```bash
# Update Encryptor (when new version available)
sudo apt update && sudo apt upgrade encryptor

# Show package information
apt show encryptor

# View installed files
dpkg -L encryptor

# Completely remove Encryptor
sudo apt remove encryptor
```

## 📈 **Performance**

- **AES-256**: ~100MB/s encryption speed
- **Memory Usage**: < 10MB during operation  
- **Key Generation**: ~2 seconds for 2048-bit RSA
- **Startup Time**: < 0.5 seconds
- **Package Size**: ~15KB (.deb package)

## 🤝 **Contributing**

We welcome contributions! Please see our [Contributing Guidelines](CONTRIBUTING.md).

### Development Setup

```bash
git clone https://github.com/mpgamer75/encryptor.git
cd encryptor
./encryptor.sh  # Test locally
```

### Building Debian Package

```bash
# Install build dependencies
sudo apt install dpkg-dev debhelper fakeroot

# Build package
./build_deb.sh

# Test package
sudo dpkg -i encryptor_1.0.0-1_all.deb
```

### Running Tests

```bash
# Test encryption/decryption cycle
echo "test" > test.txt
./encryptor.sh  # Encrypt test.txt
./encryptor.sh  # Decrypt test.txt.enc
diff test.txt test.dec  # Should be identical
```

## 📜 **License**

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🔮 **Roadmap**

- [ ] APT Repository for easier installation (`sudo apt install encryptor`)
- [ ] GUI version with Electron
- [ ] Additional algorithms (ChaCha20, Blowfish)
- [ ] Batch encryption for multiple files
- [ ] Integration with cloud storage APIs
- [ ] Mobile companion app
- [ ] Hardware security key support

## 📚 **Documentation**

- 📖 [Usage Guide](docs/USAGE.md) - Complete usage examples and best practices
- 🔐 [Algorithm Guide](docs/ALGORITHMS.md) - Detailed security information and technical specs
- 📋 Manual page: `man encryptor` (available after .deb installation)

## 🙏 **Acknowledgments**

- **OpenSSL** team for robust cryptographic primitives
- **Bash** community for scripting inspiration
- **Security researchers** for algorithm recommendations

## 📊 **Download Statistics**

Check out our [releases page](https://github.com/mpgamer75/encryptor/releases) for the latest version and download statistics.

<div align="center">

---

**⭐ Star this repository if Encryptor helped secure your files! ⭐**

[📥 Download Latest Release](https://github.com/mpgamer75/encryptor/releases/latest) • [🐛 Report Bug](https://github.com/mpgamer75/encryptor/issues) • [✨ Request Feature](https://github.com/mpgamer75/encryptor/issues) • [📖 Documentation](docs/)

---

</div>
