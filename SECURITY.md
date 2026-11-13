# Security Policy

## Supported Versions

| Version | Status |
|---------|--------|
| 3.0.x | ✅ Supported |
| 2.x | ❌ Not supported — upgrade (3.0 still reads 2.x files) |

Version 3.0.0 fixes several serious defects of 2.x; see "Fixed in 3.0" below.
Users of 2.x should upgrade and re-encrypt their files.

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

## Security design

### Threat model

Encryptor protects the **confidentiality and integrity of files at rest and in
transit** against an attacker who can read and modify the encrypted file but
does not know the password or hold a recipient's private key.

It does not protect against: malware or another user with root on the machine
where you encrypt or decrypt; weak or reused passwords; an attacker who can
replace the `encryptor` or `openssl` binaries; traffic analysis (file sizes and
recipient fingerprints are visible).

### Authenticated container
New files use the ENCRYPTOR/3 format (docs/FORMAT.md): cipher + HMAC-SHA256,
encrypt-then-MAC, independent subkeys. The tag covers the header and the
ciphertext and is verified before decryption. Cipher, MAC and KDF names read
from a file are checked against allow-lists; PBKDF2 iteration counts and
scrypt parameters are bounded before any work is done.

### Password protection
A random 256-bit file key is sealed under the password with scrypt (memory-
hard), inside a standard PKCS#8 envelope that stock OpenSSL can open. PBKDF2-
HMAC-SHA256 (600,000 iterations) is available with `--kdf pbkdf2` for
environments restricted to NIST-approved algorithms.

### Secret handling
- Passwords, derived keys and key passphrases are passed to OpenSSL through
  anonymous pipes (`-pass fd:N`). They are never placed in process arguments
  and never written to disk. HMAC keys are fed through standard input by shell
  built-ins.
- Secrets are accepted from the terminal (no echo), a file, an environment
  variable or standard input — never from a command-line argument.
- The CI suite checks that a canary password never appears in any
  `/proc/*/cmdline` or in the temporary directory.

### Files and permissions
- The process runs with `umask 077`: encrypted and decrypted outputs are 0600.
- State directory and key store are 0700; private keys 0400; the log 0600.
- Temporary data lives in a `mktemp -d` directory (unpredictable name, 0700)
  removed on exit and on SIGINT/SIGTERM/SIGHUP. It only ever holds ciphertext
  spooled from standard input, error output and short-lived OpenSSL
  configuration files containing certificate subject fields.
- Outputs are written to a temporary name and renamed on success; partial
  files are removed on failure or interruption.
- Existing files are not overwritten without `--force`.

### Input handling
- Cipher names are matched against a fixed list before reaching OpenSSL
  (2.x passed `--algo` straight through, so `--algo none` produced plaintext).
- Object names in the key store are restricted to `[A-Za-z0-9._-]`.
- Certificate subject fields are written to an OpenSSL config with escaping
  instead of being interpolated into `-subj`.
- TLS scan targets must match a host/IP[:port] grammar and can never be
  interpreted as options.
- Log messages are stripped of control characters; JSON output is escaped.

### Supply chain
- `install.sh` installs from a local checkout, or downloads a tarball of a
  ref you can pin (`ENCRYPTOR_REF`) and verify (`ENCRYPTOR_SHA256`). It never
  edits shell start-up files and never calls `sudo`.
- testssl.sh is optional, fetched only on request, from a pinned release tag.
- Releases are built by CI and published with a `SHA256SUMS` file.

---

## Known limitations

- **Memory-hardness is bounded.** Password files are sealed with scrypt at
  N=2^14, r=8, p=5 (16 MiB per guess), the strongest setting the OpenSSL
  command line accepts with the password passed through a pipe. This is an
  OWASP-listed configuration but weaker than Argon2id or scrypt at N=2^17.
  With `--kdf pbkdf2` there is no memory-hardness at all. Use long
  passphrases (`encryptor passgen`).
- **No sender authentication** in recipient mode, and no signatures.
- **Whole-file authentication.** Verification is a separate pass before
  decryption; this is not a chunked streaming AEAD.
- **Secrets in memory.** Passwords live in Bash variables while the program
  runs. Bash cannot lock or reliably wipe memory; with swap or core dumps
  enabled they could reach the disk. `encryptor audit` reports the core-dump
  setting.
- **Environment variables** (`--pass-env`) are readable by the same user (and
  root) through `/proc/<pid>/environ`. Prefer `--pass-file` or `--pass-stdin`.
- **Secure deletion is best-effort.** `shred`/overwriting does not reliably
  destroy data on SSDs, copy-on-write or journaling filesystems, snapshots,
  RAID or network storage. Use full-disk encryption.
- **Legacy 2.x files are not authenticated.** They can be decrypted but not
  verified; re-encrypt them.
- **Time-of-check/time-of-use.** The file is read twice (verify, then
  decrypt). An attacker able to swap the file between the two reads on your
  own machine could cause unauthenticated plaintext to be produced; such an
  attacker already controls your account.
- **Not independently audited.**

---

## Fixed in 3.0

Defects present in 2.1.0 and earlier:

| Severity | Issue |
|---|---|
| Critical | Certificate ("S/MIME") encryption failed silently on OpenSSL 3 — it reported success without creating a file, then offered to shred the original. |
| Critical | When it did run, S/MIME mode corrupted binary files and rewrote line endings (missing `-binary`). |
| Critical | No authentication: the `.sha256` sidecar was an unkeyed hash anyone could recompute; batch mode never checked it. Ciphertext could be modified undetected (bit-flipping in CTR/ChaCha20). |
| High | `--algo` was passed to OpenSSL unchecked: `--algo none` wrote plaintext and reported success. |
| High | A wrong password with CTR/ChaCha20 "succeeded" and wrote garbage. |
| High | Documentation claimed AES-256-GCM was the default; it was never available. |
| High | Passwords were written to a file under a predictable `/tmp/encryptor_$$` path created without checking ownership. |
| High | TLS scan target accepted option-like input (option injection into testssl.sh); testssl.sh was cloned from an unpinned branch. |
| Medium | 2.1 could not decrypt 2.0 files (iteration count changed, not stored). |
| Medium | Outputs and the log were world-readable under the default umask; existing files were overwritten silently. |
| Medium | CA and identity keys were always unencrypted; signed certificates had no X.509v3 extensions; names allowed path traversal. |
| Medium | JSON output was not escaped; log lines could be forged through file names. |
| Medium | The installer used any `encryptor.sh` found in the current directory and "verified" checksums that did not exist. |
| Low | PKCS#12 export allowed an empty password; key/certificate matching only worked for RSA; the menu looped forever on end-of-input. |
