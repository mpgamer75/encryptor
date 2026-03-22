# Encryption Algorithms in Encryptor

This document describes the encryption algorithms available in Encryptor v2.1.0,
their security properties, appropriate use cases, and implementation details.

---

## Quick Reference

| Algorithm | Type | Authentication | Key Size | Recommended |
|-----------|------|----------------|----------|-------------|
| **AES-256-GCM** | Symmetric | ✅ AEAD | 256-bit | ✅ **Default** |
| **S/MIME** | Asymmetric | ✅ AEAD | RSA 2048-4096 | ✅ For recipients |
| AES-256-CBC | Symmetric | ❌ None | 256-bit | ⚠ Legacy only |
| AES-256-CTR | Symmetric | ❌ None | 256-bit | ⚠ Legacy only |
| ChaCha20 | Symmetric | ❌ None | 256-bit | ⚠ No auth |
| Camellia-256-CBC | Symmetric | ❌ None | 256-bit | ⚠ Compatibility |
| ARIA-256-CBC | Symmetric | ❌ None | 256-bit | ⚠ Compatibility |

> **What is AEAD?**
> Authenticated Encryption with Associated Data — the cipher provides both
> *confidentiality* (data is secret) and *integrity* (data has not been tampered with).
> Non-AEAD modes only provide confidentiality.

---

## Recommended Algorithms

### AES-256-GCM — Default Recommended

**Type:** Symmetric (password-based)
**Authentication:** ✅ AEAD
**Key size:** 256-bit
**Block size:** 128-bit
**Mode:** Galois/Counter Mode (GCM)

AES-256-GCM is the gold standard for symmetric encryption in 2024. It is:
- NIST-approved (FIPS 197 + SP 800-38D)
- Used in TLS 1.3, SSH, Signal Protocol, and virtually every modern security system
- Authenticated: decryption will fail if the ciphertext is tampered with
- Parallelizable for high throughput
- Hardware-accelerated on Intel (AES-NI) and ARM (ARMv8 Crypto)

**Implementation in Encryptor:**
```
Key derivation: PBKDF2-HMAC-SHA256, 600,000 iterations, random 8-byte salt
Encryption:     OpenSSL enc -aes-256-gcm -salt -pbkdf2 -iter 600000
Password:       Passed via file descriptor (never on command line)
Integrity:      SHA-256 sidecar file written alongside .enc file
```

**When to use:**
- Default choice for all new encrypted files
- Any situation where you need password-based symmetric encryption

---

### S/MIME (Certificate-Based) — Recommended for Recipients

**Type:** Asymmetric (certificate/key-based)
**Authentication:** ✅ AEAD (AES-256-GCM for content encryption)
**Key wrap:** RSA 2048–4096-bit
**Standard:** RFC 5751 (S/MIME v3.2)

S/MIME encrypts for a specific recipient using their X.509 public certificate.
Only the holder of the matching private key can decrypt. No shared password is needed.

**Implementation in Encryptor:**
```
Encryption: openssl smime -encrypt -aes256-gcm -outform PEM recipient.pem
Decryption: openssl smime -decrypt -recip cert.pem -inkey key.pem
```

**When to use:**
- Encrypting files for a specific person or system
- When no shared secret is possible
- Email attachments with S/MIME-capable clients (Thunderbird, Outlook)
- Server-to-server secure file transfer

---

## Legacy / Compatibility Algorithms

These algorithms provide **confidentiality only** — they have **no authentication**.
A tampered or corrupted encrypted file may silently produce garbage output or
no error at all on decryption.

Encryptor writes a SHA-256 integrity sidecar file (`.sha256`) for all modes
and verifies it before decryption to partially compensate, but this is an
external check, not built into the cipher.

**Use legacy algorithms only for:**
- Interoperability with older systems that do not support GCM
- Re-encrypting existing legacy files

### AES-256-CBC

**Standard:** NIST FIPS 197 + SP 800-38A
**Mode:** Cipher Block Chaining
**Auth:** None — no integrity protection
**Note:** Susceptible to padding oracle attacks if not used with constant-time
decryption and MAC verification. Encryptor's PBKDF2 key derivation and SHA-256
sidecar mitigate but do not eliminate the risk.

### AES-256-CTR

**Mode:** Counter Mode (stream cipher behavior)
**Auth:** None
**Note:** Bit-flipping attacks are possible. Nonce reuse is catastrophic.
OpenSSL manages the nonce internally, but there is no authentication guarantee.

### ChaCha20

**Origin:** D.J. Bernstein, 2008
**Standard:** RFC 7539
**Auth:** None (ChaCha20-Poly1305 would provide AEAD — planned for a future release)
**Note:** Excellent performance on platforms without AES hardware acceleration.

### Camellia-256-CBC

**Origin:** NTT and KDDI (Japan), 2000
**Standard:** ISO/IEC 18033-3, RFC 3713
**Auth:** None
**Security:** Equivalent to AES-256 by design. No known practical attacks.
**When to use:** Compliance requirements mandating Japanese national cryptography standards.

### ARIA-256-CBC

**Origin:** NSRI / KISA (South Korea), 2003
**Standard:** ISO/IEC 18033-3, RFC 5794
**Auth:** None
**Security:** Equivalent to AES-256. No known practical attacks.
**When to use:** Compliance requirements mandating Korean national cryptography standards.

---

## Key Derivation

All password-based algorithms use **PBKDF2-HMAC-SHA256** for key derivation:

| Parameter | Value | Standard |
|-----------|-------|----------|
| Algorithm | PBKDF2-HMAC-SHA256 | NIST SP 800-132 |
| Iterations | **600,000** | OWASP 2024 recommendation |
| Salt | 8 bytes random | OpenSSL default |
| Output key length | 256 bits | Matches cipher key size |

> **Why 600,000 iterations?**
> OWASP's [Password Storage Cheat Sheet (2024)](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)
> recommends 600,000 iterations for PBKDF2-HMAC-SHA256. This raises the cost
> of brute-force attacks while remaining fast enough for interactive use
> (approximately 0.5 to 2 seconds on modern hardware).

---

## Integrity Verification

For all encryption operations, Encryptor writes a SHA-256 hash file alongside
the encrypted output:

```
myfile.txt         ->  myfile.txt.enc
                       myfile.txt.enc.sha256
```

Before decryption, Encryptor:
1. Reads the `.sha256` sidecar
2. Computes the current SHA-256 of the `.enc` file
3. Compares them — failure aborts decryption with a warning

The user can override the integrity check, but this is not recommended.

---

## Password Security

Passwords are **never** passed on the command line. Encryptor writes the password
to a temporary file in a mode-600 file inside `/tmp/encryptor_$$` (which is
cleaned up on exit via `trap`), then passes `file:/path` to OpenSSL.

This means the password does NOT appear in:
- `ps aux` / `ps -ef` output
- `/proc/<pid>/cmdline`
- Shell history (it is always read interactively via `read -rs`)
- OpenSSL error messages

---

## Algorithm Comparison

| Property | AES-256-GCM | AES-256-CBC | ChaCha20 | S/MIME |
|----------|-------------|-------------|----------|--------|
| Confidentiality | Yes | Yes | Yes | Yes |
| Integrity (AEAD) | Yes | No | No | Yes |
| Hardware accel | Yes | Yes | Yes | Yes |
| NIST approved | Yes | Yes | No | Yes |
| No shared secret | No | No | No | Yes |
| Padding attacks | N/A | Risk | N/A | N/A |

---

## References

- [NIST FIPS 197 — AES](https://nvlpubs.nist.gov/nistpubs/FIPS/NIST.FIPS.197-upd1.pdf)
- [NIST SP 800-38D — GCM](https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-38d.pdf)
- [NIST SP 800-132 — Key Derivation](https://nvlpubs.nist.gov/nistpubs/Legacy/SP/nistspecialpublication800-132.pdf)
- [OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)
- [RFC 5751 — S/MIME v3.2](https://www.rfc-editor.org/rfc/rfc5751)
- [RFC 7539 — ChaCha20-Poly1305](https://www.rfc-editor.org/rfc/rfc7539)
- [RFC 3713 — Camellia](https://www.rfc-editor.org/rfc/rfc3713)
- [RFC 5794 — ARIA](https://www.rfc-editor.org/rfc/rfc5794)
