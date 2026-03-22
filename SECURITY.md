# Security Policy

## Supported Versions

| Version | Status |
|---------|--------|
| 2.1.x | ✅ Supported — actively maintained |
| 2.0.x | ⚠️ Critical fixes only |
| < 2.0 | ❌ Not supported |

Users running versions below 2.1.0 are strongly encouraged to upgrade.
Version 2.1.0 contains critical security fixes including:
- Password no longer exposed in process argument list (`ps aux`)
- False AEAD claim corrected (AES-256-CBC/CTR are not authenticated)
- PKCS#12 export password leak fixed
- PBKDF2 iterations raised to OWASP 2024 recommended level (600,000)

---

## Reporting a Vulnerability

**Please do not report security vulnerabilities as public GitHub issues.**

If you discover a security vulnerability in Encryptor:

1. **Email the maintainer privately:**
   Send a description of the vulnerability to the maintainer via GitHub's
   private vulnerability reporting feature:
   `https://github.com/mpgamer75/encryptor/security/advisories/new`

2. **Include in your report:**
   - Encryptor version (`encryptor --version`)
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if you have one)

3. **Response timeline:**
   - Acknowledgement: within 72 hours
   - Initial assessment: within 7 days
   - Fix target: within 30 days for critical issues, 90 days for others
   - CVE assignment will be requested for confirmed vulnerabilities

4. **Disclosure:**
   We follow [coordinated disclosure](https://en.wikipedia.org/wiki/Coordinated_vulnerability_disclosure).
   We ask reporters to give us time to fix the issue before public disclosure.
   We will credit reporters in the release notes unless they prefer anonymity.

---

## Security Design

### Password handling
Passwords are never passed on the command line. They are written to a
mode-600 temporary file in `/tmp/encryptor_$$` and passed to OpenSSL via
`-pass file:/path`. The temporary directory is removed by an EXIT trap.

### Key derivation
Password-based encryption uses PBKDF2-HMAC-SHA256 with 600,000 iterations
and a random 8-byte salt, meeting OWASP 2024 and NIST SP 800-132 requirements.

### Authenticated encryption
AES-256-GCM (the default) and S/MIME provide authenticated encryption (AEAD).
Legacy modes (CBC, CTR, ChaCha20, Camellia-CBC, ARIA-CBC) provide confidentiality
only. A SHA-256 integrity sidecar file provides external tamper detection for
all modes.

### Private key storage
Private keys are stored with mode 400 (read-only by owner). The security audit
flags any keys with weaker permissions.

### Temporary files
All temporary files (password files, OpenSSL error buffers) are created inside
`/tmp/encryptor_$$` which is removed on program exit via `trap`.

### Logging
The operation log (`~/.config/encryptor/encryptor.log`) records operation types
and file names but never passwords, key material, or decrypted content.

---

## Known Limitations

- **SSD secure deletion:** `shred` may not effectively overwrite data on SSDs,
  NVMe drives, RAID arrays, or network-mounted filesystems due to wear leveling
  and write buffering. Encryptor attempts shred/overwrite but cannot guarantee
  secure deletion on these storage types.

- **Non-AEAD modes:** AES-256-CBC, AES-256-CTR, ChaCha20, Camellia-256-CBC,
  and ARIA-256-CBC provide no authentication. The SHA-256 sidecar provides
  basic tamper detection but is not cryptographically equivalent to AEAD.
  Use AES-256-GCM or S/MIME for authenticated encryption.

- **Shell history:** Interactive password entry uses `read -rs` (silent, no
  echo). The entered password is not stored in shell history. However, if a
  user accidentally types their password at the main menu prompt (before being
  asked), it may appear in history.

- **Memory:** Passwords exist in Bash process memory while the script runs.
  On systems with active swap or core dump enabled, this could theoretically
  be recovered. Disabling swap or using encrypted swap is recommended for
  high-security environments.
