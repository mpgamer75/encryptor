# 🔐 Encryption Algorithms Guide

This document provides detailed information about the encryption algorithms supported by Encryptor, including their technical specifications, use cases, and security considerations.

## Table of Contents

- [Overview](#overview)
- [AES-256 (Advanced Encryption Standard)](#aes-256-advanced-encryption-standard)
- [RSA (Rivest-Shamir-Adleman)](#rsa-rivest-shamir-adleman)
- [Hybrid AES+RSA](#hybrid-aes-rsa)
- [3DES (Triple Data Encryption Standard)](#3des-triple-data-encryption-standard)
- [Algorithm Comparison](#algorithm-comparison)
- [Security Best Practices](#security-best-practices)
- [Technical Implementation](#technical-implementation)

## Overview

Encryptor supports four robust encryption algorithms, each designed for specific use cases and security requirements. All implementations use industry-standard OpenSSL cryptographic primitives to ensure maximum security and compatibility.

## AES-256 (Advanced Encryption Standard)

### Description

AES-256 is a symmetric block cipher that uses a 256-bit key for encryption. It's the gold standard for modern encryption and is approved by the U.S. National Security Agency (NSA) for protecting classified information up to the TOP SECRET level.

### Technical Specifications

- **Algorithm Type**: Symmetric block cipher
- **Key Size**: 256 bits
- **Block Size**: 128 bits (16 bytes)
- **Mode**: CBC (Cipher Block Chaining)
- **Key Derivation**: PBKDF2 with SHA-256
- **Salt**: Random 64-bit salt for each encryption
- **Iterations**: 100,000 PBKDF2 iterations

### Security Level

⭐⭐⭐⭐⭐ **Military Grade**

- **Theoretical Security**: 2^256 possible keys (practically unbreakable)
- **Known Attacks**: No practical attacks against AES-256
- **Compliance**: FIPS 140-2 approved, NSA Suite B

### Use Cases

- **Best For**: General-purpose file encryption
- **File Size**: Unlimited (scales efficiently)
- **Performance**: Excellent (hardware acceleration available)
- **Key Sharing**: Requires secure key exchange

### Implementation Details

```bash
# Encryption command used internally
openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 \
    -in input_file -out output_file -pass pass:"user_password"

# Decryption command used internally
openssl enc -d -aes-256-cbc -pbkdf2 -iter 100000 \
    -in encrypted_file -out output_file -pass pass:"user_password"
```

### Advantages

- ✅ Extremely secure with proper implementation
- ✅ Fast encryption/decryption speeds
- ✅ Widely supported and tested
- ✅ Hardware acceleration available on modern CPUs
- ✅ No practical file size limitations

### Limitations

- ⚠️ Requires secure password/key distribution
- ⚠️ Same key for encryption and decryption
- ⚠️ Password-based security (vulnerable to weak passwords)

## RSA (Rivest-Shamir-Adleman)

### Description

RSA is an asymmetric (public-key) cryptographic algorithm that uses a pair of mathematically related keys. It's primarily used for secure key exchange and digital signatures, with limited direct file encryption capabilities due to size constraints.

### Technical Specifications

- **Algorithm Type**: Asymmetric (public-key) cryptography
- **Key Size**: 2048 bits (default)
- **Padding**: PKCS#1 v1.5 (OpenSSL default)
- **Maximum Data Size**: ~200 bytes per encryption block
- **Key Generation**: Secure random prime number generation

### Security Level

⭐⭐⭐⭐ **Very Secure**

- **Security Basis**: Integer factorization problem
- **Key Strength**: 2048-bit keys considered secure until 2030+
- **Known Attacks**: No practical attacks against properly implemented 2048-bit RSA
- **Post-Quantum**: Vulnerable to future quantum computers

### Use Cases

- **Best For**: Small files, key exchange, digital signatures
- **File Size**: Maximum ~200 bytes per encryption operation
- **Performance**: Slower than symmetric algorithms
- **Key Sharing**: Public key can be shared openly

### Implementation Details

```bash
# Key generation
openssl genrsa -out private_key.pem 2048
openssl rsa -in private_key.pem -pubout -out public_key.pem

# Encryption
openssl pkeyutl -encrypt -pubin -inkey public_key.pem \
    -in input_file -out encrypted_file

# Decryption
openssl pkeyutl -decrypt -inkey private_key.pem \
    -in encrypted_file -out output_file
```

### Advantages

- ✅ No key distribution problem (public key cryptography)
- ✅ Enables secure communication without prior key exchange
- ✅ Well-established and thoroughly analyzed
- ✅ Suitable for digital signatures and authentication
- ✅ Industry standard for secure communications

### Limitations

- ⚠️ Very limited file size (maximum ~200 bytes)
- ⚠️ Significantly slower than symmetric encryption
- ⚠️ Larger key sizes required for equivalent security
- ⚠️ Vulnerable to future quantum computing attacks

## Hybrid AES+RSA

### Description

Hybrid encryption combines the best aspects of both symmetric and asymmetric encryption. A random AES key is generated for each encryption operation, the file is encrypted with AES-256, and then the AES key is encrypted with RSA for secure distribution.

### Technical Specifications

- **File Encryption**: AES-256-CBC with random key
- **Key Encryption**: RSA-2048 for AES key protection
- **Key Generation**: Cryptographically secure random 256-bit AES keys
- **Key Derivation**: PBKDF2 for AES key strengthening
- **Components**: Encrypted file + encrypted key + RSA private key

### Security Level

⭐⭐⭐⭐⭐ **Maximum Security**

- **Combined Strength**: Benefits from both AES-256 and RSA-2048 security
- **Key Management**: Secure key distribution via public-key cryptography
- **Perfect Forward Secrecy**: Each encryption uses a unique AES key

### Use Cases

- **Best For**: Maximum security requirements, large files with secure key exchange
- **File Size**: Unlimited (AES handles the bulk encryption)
- **Performance**: Fast (AES) with secure key exchange (RSA)
- **Key Sharing**: RSA public key can be shared; private key remains secret

### Implementation Process

1. **Generate RSA key pair** (2048-bit)
2. **Generate random AES key** (256-bit)
3. **Encrypt file with AES-256** using the random key
4. **Encrypt AES key with RSA public key**
5. **Store**: Encrypted file + Encrypted AES key + RSA private key

### Advantages

- ✅ Maximum security combining both algorithm strengths
- ✅ No file size limitations
- ✅ Secure key distribution
- ✅ Fast encryption of large files
- ✅ Perfect forward secrecy with unique keys per encryption
- ✅ Suitable for secure file sharing

### Limitations

- ⚠️ More complex key management (3 components)
- ⚠️ Requires careful handling of multiple files
- ⚠️ Slightly more overhead than pure AES

## 3DES (Triple Data Encryption Standard)

### Description

3DES applies the DES algorithm three times to each data block, effectively using a 168-bit key length. While still considered secure, it's primarily maintained for legacy compatibility and is gradually being phased out in favor of AES.

### Technical Specifications

- **Algorithm Type**: Symmetric block cipher
- **Key Size**: 168 bits (effective), 192 bits (actual)
- **Block Size**: 64 bits (8 bytes)
- **Mode**: CBC (Cipher Block Chaining)
- **Key Derivation**: PBKDF2 with SHA-256
- **Iterations**: 100,000 PBKDF2 iterations

### Security Level

⭐⭐⭐ **Legacy Secure**

- **Current Status**: Still secure but deprecated
- **Vulnerabilities**: Sweet32 attack (theoretical, requires massive data)
- **Compliance**: Being phased out by security standards
- **Recommended Until**: 2023 (NIST recommendation)

### Use Cases

- **Best For**: Legacy system compatibility
- **File Size**: Unlimited (but slower than AES)
- **Performance**: Slower than AES-256
- **Migration Path**: Should migrate to AES-256

### Implementation Details

```bash
# Encryption
openssl enc -des-ede3-cbc -salt -pbkdf2 -iter 100000 \
    -in input_file -out output_file -pass pass:"user_password"

# Decryption
openssl enc -d -des-ede3-cbc -pbkdf2 -iter 100000 \
    -in encrypted_file -out output_file -pass pass:"user_password"
```

### Advantages

- ✅ Widely supported in legacy systems
- ✅ Well-tested and analyzed
- ✅ Still considered secure for most applications
- ✅ Compatible with older systems

### Limitations

- ⚠️ Slower than AES
- ⚠️ Smaller block size (64-bit vs 128-bit)
- ⚠️ Being phased out by security standards
- ⚠️ Not recommended for new implementations

## Algorithm Comparison

| Algorithm | Security | Speed | File Size | Key Management | Best Use Case |
|-----------|----------|--------|-----------|----------------|---------------|
| **AES-256** | ⭐⭐⭐⭐⭐ | Very Fast | Unlimited | Password-based | General purpose |
| **RSA** | ⭐⭐⭐⭐ | Slow | ~200 bytes | Public/Private key | Small files, key exchange |
| **Hybrid AES+RSA** | ⭐⭐⭐⭐⭐ | Fast | Unlimited | Public/Private key | Maximum security |
| **3DES** | ⭐⭐⭐ | Moderate | Unlimited | Password-based | Legacy compatibility |

## Security Best Practices

### Password Security

- **Minimum Length**: 12+ characters
- **Complexity**: Mix of uppercase, lowercase, numbers, symbols
- **Uniqueness**: Use different passwords for different files
- **Storage**: Use a reputable password manager

### Key Management

- **RSA Keys**: Store private keys securely, share public keys freely
- **Backup**: Keep secure backups of important keys
- **Rotation**: Regularly rotate encryption keys for sensitive data
- **Access Control**: Limit access to private keys

### File Handling

- **Secure Deletion**: Use secure delete tools for sensitive plaintext files
- **Backup Strategy**: Encrypt backups with different keys
- **Transport Security**: Use secure channels for sharing encrypted files
- **Verification**: Verify file integrity after encryption/decryption

### Algorithm Selection Guidelines

1. **For general use**: Choose AES-256
2. **For maximum security**: Choose Hybrid AES+RSA
3. **For small files/keys**: Choose RSA
4. **For legacy systems only**: Choose 3DES

## Technical Implementation

### Error Handling

Encryptor implements robust error handling for:

- Invalid file permissions
- Corrupted encrypted files
- Wrong passwords/keys
- Insufficient disk space
- OpenSSL errors

### Temporary Files

- All temporary files created in `/tmp/encryptor_$$`
- Automatic cleanup on script exit
- Secure permissions (600) on temporary files
- No plaintext passwords stored in temporary files

### Randomness

- Uses OpenSSL's cryptographically secure random number generator
- Proper salt generation for each encryption operation
- Secure key generation for RSA and AES keys

### Compatibility

- **OpenSSL Version**: Requires OpenSSL 1.1.0 or higher
- **Platform Support**: Linux, macOS, WSL
- **File Systems**: Compatible with all major file systems
- **Character Encoding**: Handles binary files correctly

## Performance Benchmarks

Approximate performance on modern hardware:

| Algorithm | Encryption Speed | Decryption Speed | CPU Usage |
|-----------|-----------------|------------------|-----------|
| AES-256 | ~100 MB/s | ~100 MB/s | Low |
| RSA | ~1 KB/s | ~10 KB/s | High |
| Hybrid | ~95 MB/s | ~95 MB/s | Low-Medium |
| 3DES | ~30 MB/s | ~30 MB/s | Medium |

*Note: Performance varies based on hardware, file size, and system load.*

---

## Further Reading

- [NIST Special Publication 800-57](https://csrc.nist.gov/publications/detail/sp/800-57-part-1/rev-5/final) - Key Management Guidelines
- [RFC 3447](https://tools.ietf.org/html/rfc3447) - RSA PKCS #1 v2.1
- [FIPS 197](https://csrc.nist.gov/publications/detail/fips/197/final) - AES Standard
- [OpenSSL Documentation](https://www.openssl.org/docs/) - Implementation Details

For questions or security concerns, please review the main documentation or submit an issue on the project repository.