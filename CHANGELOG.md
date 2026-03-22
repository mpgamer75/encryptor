# Changelog

All notable changes to Encryptor are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).
Versioning follows [Semantic Versioning](https://semver.org/).

---

## [2.1.0] — 2026-03-22

### Security — Critical fixes

- **FIXED: Password no longer exposed on command line.**
  Previously `-pass "pass:$PASSWORD"` put the plaintext password into the
  process argument list, visible in `ps aux` and `/proc/<pid>/cmdline` to all
  users on the system. Now uses `-pass file:/tmp/encryptor_$$/pass.tmp`
  (mode 600, auto-deleted by EXIT trap). This is the single most important
  security fix in this release.

- **FIXED: False "Integrated AEAD" claim removed.**
  The encryption report previously displayed `(Integrated AEAD)` for all
  algorithms including AES-256-CBC and AES-256-CTR, which provide no
  authentication whatsoever. The display now accurately reflects which
  modes are authenticated (GCM, S/MIME) and which are not.

- **FIXED: PKCS#12 export password leak.**
  `-passout pass:$p12_pass` replaced with `-passout file:$pass_file`.

- **CLARIFIED: `openssl enc` does not support AEAD/GCM modes.**
  AES-256-GCM is available via S/MIME (certificate-based) only. All
  symmetric modes (CBC, CTR, ChaCha20, Camellia, ARIA) use external
  SHA-256 sidecar files for integrity verification. The false claim that
  CBC/CTR modes provide "Integrated AEAD" has been corrected.
  AES-256-CBC remains the recommended symmetric mode.

- **CHANGED: PBKDF2 iterations raised from 100,000 to 600,000.**
  Aligns with OWASP 2024 recommendations for PBKDF2-HMAC-SHA256
  (previously at the 2017 minimum; now at the 2024 recommended level).

- **ADDED: SHA-256 integrity sidecar files.**
  Every encrypted file now produces a companion `.sha256` file. Encryptor
  verifies this hash before decrypting. This provides tamper detection for
  non-AEAD modes.

### Architecture

- **REFACTORED: Monolithic 1812-line script split into modules.**
  - `lib/ui.sh` — colors, headers, menus, spinner, file selector
  - `lib/crypto.sh` — encryption/decryption, algorithm registry
  - `lib/certs.sh` — X.509 / PKI certificate management
  - `lib/audit.sh` — security audit (local checks + remote scan)
  - `encryptor.sh` — entry point (sources modules, handles CLI args)

  Each module can now be independently tested, reviewed, and updated.

- **ADDED: `set -uo pipefail`** at the top of the main script.
  Catches undefined variable references and pipe failures that were
  previously silent.

### Features

- **ADDED: ASCII spinner** displayed during long-running encryption/decryption
  operations. Shows which algorithm and iteration count is active.

- **ADDED: Status bar** in the main menu header, showing OpenSSL version,
  certificate/key count, config directory path, and last log entry.

- **ADDED: Batch / non-interactive mode.**
  ```
  encryptor --encrypt FILE --algo aes-256-gcm --pass-file PASSFILE
  encryptor --decrypt FILE --algo aes-256-gcm --pass-file PASSFILE
  encryptor --encrypt FILE --algo smime --cert CERT.pem
  encryptor --encrypt FILE --algo aes-256-gcm --pass-file PASSFILE --json
  ```
  Enables CI/CD pipelines, scripts, and automation. `--json` flag outputs
  machine-readable JSON for integration with other tools.

- **ADDED: Built-in `--help`** that works without installing the `.deb` package.
  Previously the help message only pointed users to `man encryptor`.

- **ADDED: Security audit check for SHA-256 sidecar coverage.**
  The local audit now reports how many `.enc` files are missing integrity
  sidecar files.

- **ADDED: Security audit check for AES-GCM support.**
  Warns if the installed OpenSSL version does not support AES-256-GCM.

- **ADDED: PBKDF2 iteration check in local audit.**
  Verifies the configured iteration count meets OWASP 2024 recommendations.

- **IMPROVED: `uninstall.sh`** — now properly removes the binary, man page,
  optional lib directory, and prompts the user before deleting certs/keys/logs
  in `~/.config/encryptor/`. Previously only removed the binary.

### CI/CD

- **UPGRADED: `actions/checkout@v3` → `@v4`** across all workflows.

- **ADDED: ShellCheck linting step** (`shellcheck -S warning`) for all scripts.

- **ADDED: Functional smoke tests** in GitHub Actions:
  - AES-256-GCM round-trip (encrypt + decrypt + diff)
  - AES-256-CBC round-trip
  - SHA-256 sidecar creation and verification
  - JSON output mode
  - Process argument security check (verifies password not in `ps` output)

- **ADDED: Debian package build test** in CI.

### Documentation

- **FIXED: `docs/ALGORITHMS.md`** — removed documentation for 3DES and bare
  RSA which are not implemented in the tool. Added AES-256-GCM documentation.
  Added accuracy notes for which modes are/are not authenticated. Updated PBKDF2
  iteration count to 600,000. Added integrity verification section.

- **ADDED: `CHANGELOG.md`** at repo root (this file).

- **ADDED: `CONTRIBUTING.md`** — development setup, code style, testing, PR process.

- **ADDED: `SECURITY.md`** — vulnerability reporting process and supported versions.

---

## [2.0.0] — Previous Release

- Multiple modern symmetric algorithms: AES-256-CBC/CTR, ChaCha20, Camellia-256-CBC, ARIA-256-CBC
- S/MIME support with X.509 certificates (AES-256-GCM key wrap)
- PBKDF2 key derivation (100,000 iterations)
- Complete certificate management: Root CA, CSR generation, signing, validation
- PKCS#12 export for Windows/browsers/email
- Certificate expiration checking
- Local security audits
- testssl.sh integration for remote SSL/TLS scanning
- Interactive color-coded TUI
- Comprehensive logging
- One-line curl install + Debian package
- Cross-platform support (Linux, macOS, WSL)

---

[2.1.0]: https://github.com/mpgamer75/encryptor/compare/v2.0.0...v2.1.0
[2.0.0]: https://github.com/mpgamer75/encryptor/releases/tag/v2.0.0
