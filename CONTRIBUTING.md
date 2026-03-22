# Contributing to Encryptor

Thank you for your interest in contributing! Encryptor is an open-source CLI
encryption tool. Contributions of all kinds are welcome — bug reports, feature
requests, documentation improvements, and code changes.

---

## Table of Contents

1. [Development Setup](#development-setup)
2. [Code Style](#code-style)
3. [Testing](#testing)
4. [Security Guidelines](#security-guidelines)
5. [Pull Request Process](#pull-request-process)
6. [Reporting Bugs](#reporting-bugs)
7. [Feature Requests](#feature-requests)

---

## Development Setup

### Requirements

- Bash 4.0+ (5.x recommended)
- OpenSSL 3.x (1.1.1+ minimum)
- ShellCheck (`sudo apt install shellcheck`)
- BATS (optional, for unit tests): https://github.com/bats-core/bats-core
- Git

### Clone and run

```bash
git clone https://github.com/mpgamer75/encryptor.git
cd encryptor
chmod +x encryptor.sh
./encryptor.sh --help
./encryptor.sh          # launch interactive mode
```

### Project structure

```
encryptor/
├── encryptor.sh          # Entry point — sources lib/ modules
├── lib/
│   ├── ui.sh             # Colors, headers, menus, spinner, file selector
│   ├── crypto.sh         # Encryption/decryption logic, algorithm registry
│   ├── certs.sh          # X.509 / PKI certificate management
│   └── audit.sh          # Security audit (local + remote)
├── docs/
│   ├── ALGORITHMS.md     # Algorithm technical reference
│   └── USAGE.md          # End-user usage guide
├── tests/                # BATS unit tests (see Testing section)
├── debian/               # Debian package files
├── install.sh            # One-line installer
├── uninstall.sh          # Uninstaller
├── build_deb.sh          # .deb package builder
├── Dockerfile            # Container image
└── .github/workflows/    # CI/CD pipelines
```

---

## Code Style

### Bash conventions

1. **Shebang:** Use `#!/usr/bin/env bash` (not `#!/bin/bash`) for portability.

2. **Safety flags:** All scripts must start with `set -uo pipefail`.
   The interactive main script omits `-e` (exit-on-error) because `read`
   returns non-zero when interrupted, but new library functions should be
   written to handle errors explicitly.

3. **Local variables:** Always declare with `local`. Separate declaration from
   assignment when the value comes from a command:
   ```bash
   # Wrong — masks return code on Bash 4:
   local val=$(cmd)

   # Correct:
   local val
   val=$(cmd)
   ```

4. **Password handling:** Passwords MUST NEVER appear on the command line.
   Use the `_write_pass_file()` helper from `lib/crypto.sh` and pass
   `-pass file:$pass_file` to OpenSSL.

5. **Quoting:** Always double-quote variable expansions: `"$var"`, `"${arr[@]}"`.

6. **Command substitution:** Prefer `$(...)` over backticks.

7. **ShellCheck clean:** All code must pass `shellcheck -S warning`.

### Naming conventions

- Functions: `snake_case`
- Private functions (internal to a module): `_leading_underscore`
- Constants / config: `UPPER_CASE`
- Local variables: `lower_case`

### Adding a new encryption algorithm

1. Add an entry to the `ALGORITHMS` associative array in `lib/crypto.sh`
2. Add a case branch in `process_encryption()` and `process_decryption()`
3. Add a case in `_mode_label()` describing the mode
4. Update `docs/ALGORITHMS.md` with technical details
5. Add a round-trip test in `.github/workflows/test.yml`
6. Update the `--help` text in `lib/ui.sh`

---

## Testing

### Syntax check (mandatory, runs in CI)

```bash
bash -n encryptor.sh
for f in lib/*.sh; do bash -n "$f"; done
```

### ShellCheck (mandatory, runs in CI)

```bash
shellcheck -S warning encryptor.sh lib/*.sh install.sh uninstall.sh build_deb.sh
```

### Smoke tests (run in CI)

The CI workflow (`test.yml`) runs functional smoke tests including:
- AES-256-GCM round-trip encrypt/decrypt
- AES-256-CBC round-trip
- SHA-256 sidecar creation and verification
- JSON output mode
- Process argument security check (password not visible in `ps aux`)

### Manual testing checklist

Before submitting a PR, manually verify:

- [ ] `./encryptor.sh --help` and `--version` work
- [ ] Interactive menu loads without errors
- [ ] Encrypt a file with AES-256-GCM, then decrypt it successfully
- [ ] Encrypt a file with S/MIME (requires a certificate)
- [ ] Certificate Manager: create CA → generate key+CSR → sign → inspect
- [ ] Security Audit: local audit produces a score
- [ ] Uninstall script runs without destroying unrelated files

---

## Security Guidelines

Because Encryptor handles cryptographic operations and private keys, security
is a first-class concern in every contribution.

**Mandatory for all PRs touching crypto code:**
- Passwords must not appear in process arguments, environment variables, or logs
- Temporary files containing secrets must use mode 600 and be deleted by the EXIT trap
- New symmetric algorithms must be AEAD or explicitly documented as non-authenticated
- PBKDF2 iterations must remain at or above 600,000

**Reporting security vulnerabilities:**
See [SECURITY.md](./SECURITY.md) — do not open a public GitHub issue for
security vulnerabilities.

---

## Pull Request Process

1. **Fork** the repository and create a feature branch from `main`:
   ```bash
   git checkout -b feature/my-improvement
   ```

2. **Make your changes** following the code style above.

3. **Run checks locally:**
   ```bash
   bash -n encryptor.sh lib/*.sh
   shellcheck -S warning encryptor.sh lib/*.sh
   ```

4. **Update documentation** — if you add or change behavior, update:
   - `docs/ALGORITHMS.md` (if algorithm-related)
   - `docs/USAGE.md` (if user-facing behavior changes)
   - `CHANGELOG.md` (add an entry under `[Unreleased]`)
   - The man page `debian/encryptor.1` (if CLI options change)

5. **Write a clear commit message:**
   ```
   fix: prevent password exposure in process arguments

   Replace -pass "pass:$password" with -pass "file:$pass_file"
   throughout process_encryption(), process_decryption(), and
   the PKCS#12 export. The pass file lives in $TEMP_DIR (mode 600)
   which is cleaned on EXIT via trap.

   Fixes: password visible in ps aux and /proc/<pid>/cmdline
   ```

6. **Open a Pull Request** against the `main` branch. The CI pipeline will
   automatically run syntax checks, ShellCheck, smoke tests, and the .deb build.

7. A maintainer will review within 7 days. Please respond to feedback promptly.

---

## Reporting Bugs

Open an issue on GitHub with:
- Encryptor version (`encryptor --version`)
- Operating system and version
- OpenSSL version (`openssl version`)
- Steps to reproduce
- Expected vs actual behavior
- Relevant log output (redact passwords and private key content)

---

## Feature Requests

Open an issue with the `enhancement` label. Include:
- The use case and motivation
- What the feature would look like from the user's perspective
- Any relevant references (RFCs, standards, similar tools)

Large features may be discussed in the issue before a PR is opened, to ensure
alignment with the project direction.
