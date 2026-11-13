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

- Bash 4.4+ (5.x recommended), OpenSSL 1.1.1+ (3.x recommended), coreutils
- [ShellCheck](https://www.shellcheck.net) for linting
- Optional: `tmux` to drive the interactive UI in tests, `python3` for strict JSON checks

### Clone and run

```bash
git clone https://github.com/mpgamer75/encryptor.git
cd encryptor
./encryptor.sh            # interactive UI, straight from the checkout
bash tests/run.sh         # full test suite
```

Use `ENCRYPTOR_CONFIG_DIR=/tmp/enc-dev ./encryptor.sh` to keep experiments
away from your real key store.

### Project structure

```
encryptor.sh        Entry point: locates lib/, loads modules, dispatches
lib/core.sh         Exit codes, state dirs, temp files, traps, logging, utilities
lib/crypto.sh       Encryption engine (ENCRYPTOR/3 + legacy readers). No UI.
lib/certs.sh        PKI engine (pki_*) and its interactive screens (cert_ui_*)
lib/audit.sh        Audit engine (audit_*), reports, TLS scan wrapper
lib/ui.sh           Terminal UI toolkit (theme, menus, panels, prompts, spinner)
lib/tui.sh          Interactive application (main menu, wizards)
lib/cli.sh          Non-interactive commands
tests/run.sh        Test suite (plain Bash)
man/encryptor.1     Manual page
docs/               USAGE, ALGORITHMS, FORMAT (specification), ROADMAP
install.sh, uninstall.sh, build_deb.sh, encryptor.spec, Dockerfile, debian/
.github/workflows/  CI (lint, tests, packaging) and release
```

### Layering rules

```
cli.sh / tui.sh      →  talk to the user, never call openssl for crypto
crypto.sh / pki_* / audit_*  →  do the work, never prompt or print
core.sh              →  shared runtime, no dependencies
```

- **Engine functions** return an exit code from `lib/core.sh` and put a
  human-readable reason in `$ENC_ERR`. They never read from the terminal and
  never print. This is what lets the CLI and the UI share one implementation
  and what makes the engine testable.
- **Presentation functions** (`tui_*`, `cert_ui_*`, `audit_ui_*`, `cli_*`)
  collect input, call the engine, and render the result.
- A new feature normally means: one engine function, one CLI option or
  command, one UI screen, tests, docs.

---

## Code Style

1. `#!/usr/bin/env bash`; the program runs under `set -uo pipefail` (no `-e`:
   errors are handled explicitly).
2. Declare variables `local`; separate declaration from command substitution
   (`local v; v=$(cmd)`).
3. Quote every expansion. Use `--` before file operands (`rm -f -- "$f"`).
4. **Secrets never go into argv or onto disk.** Pass them to OpenSSL with
   `-pass fd:3 3< <(printf '%s\n' "$secret")`. Never use `pass:`, never write
   a password to a file, never `echo` one into a pipeline of external
   commands (`printf` is a built-in; `echo` is too, but keep to `printf`).
5. **Never interpolate user input into an option position.** Validate against
   an allow-list or a strict regular expression first (see `crypto_is_cipher`,
   `is_safe_name`, `audit_valid_target`).
6. `core_tmpdir` must be called from the main shell, not inside `$(...)`
   (a directory created in a subshell would escape the exit trap).
7. UI output goes through the `ui_*` helpers so that `NO_COLOR`, ASCII
   fallback and line-mode keep working. No raw escape codes elsewhere.
8. **Untrusted text is filtered before display.** File names, certificate
   fields and engine messages go through `ui_safe` / `ui_base` / `ui_path`
   before they reach the terminal.
9. **No early-exit readers on a pipeline whose status matters.** The program
   runs with `pipefail`: `openssl … | grep -q …` or `… | head -n 1` can fail
   intermittently when the reader exits before the writer finishes. Capture
   the output in a variable and test that, or use a reader that consumes all
   input (`sed -n '1p'`, `grep … >/dev/null`).
10. Numbers from users or files are validated with a regular expression and
    then read in base 10 (`$(( 10#$n ))`): a leading zero must not mean octal.
11. Naming: `snake_case` functions, `_leading_underscore` for module-private
   ones, `UPPER_CASE` globals, prefixes by module (`crypto_`, `pki_`,
   `audit_`, `ui_`, `tui_`, `cli_`, `core_`).
12. ShellCheck clean at `-S warning`, both per file and for the concatenated
    program (CI runs both).

### Adding a cipher

1. Add its OpenSSL name to `ENC_CIPHER_IDS` and entries to `ENC_CIPHER_LABEL`
   / `ENC_CIPHER_DESC` in `lib/crypto.sh`. It must be a mode `openssl enc`
   supports (no AEAD modes).
2. Add it to the round-trip loop in `tests/run.sh` and to the completion list
   in `lib/cli.sh`.
3. Document it in `docs/ALGORITHMS.md`.

Nothing else changes: the container, the MAC and both front ends are generic.

### Changing the file format

The format is a compatibility contract. Anything that changes the bytes
written must bump the version in the magic line, keep a reader for the old
version, update `docs/FORMAT.md`, and keep the openssl-only recovery recipe
working (it is executed by the test suite).

---

## Testing

```bash
bash tests/run.sh        # everything; -v also lists passing assertions
shellcheck -S warning encryptor.sh install.sh uninstall.sh build_deb.sh lib/*.sh tests/run.sh
```

The suite covers round trips for every cipher, tamper detection (header,
body, truncation, appended data, cipher swap), wrong credentials, CLI error
handling and exit codes, JSON validity, stdin/stdout, recipients (RSA, EC,
encrypted keys, non-recipients), legacy 2.0/2.1/S-MIME files, the HMAC and
PBKDF2 implementations against OpenSSL and fixed vectors, the documented
recovery recipe, absence of secrets in process arguments and temp files, the
PKI engine, log and permission hygiene, and a line-mode run of the UI.

Every bug fix should come with an assertion that fails without the fix.

### Manual UI check

```bash
tmux new-session -d -s enc -x 100 -y 34 './encryptor.sh'
tmux send-keys -t enc e          # drive it
tmux capture-pane -t enc -p      # see the screen
```

Before a release, walk through: encrypt/decrypt with a password, encrypt for
two recipients and decrypt with a passphrase-protected key, create an
identity / CA / CSR / signed certificate, dashboard, audit, `Ctrl-C` in the
middle of an operation (terminal restored, no temp files left).

---

## Security Guidelines

Because Encryptor handles cryptographic operations and private keys, security
is a first-class concern in every contribution.

**Mandatory for all PRs touching crypto code:**
- Secrets must not appear in process arguments, on disk, or in logs
- Nothing may write unauthenticated plaintext: verify the tag before decrypting
- Values read from a file header are untrusted until validated against an allow-list
- The default PBKDF2 work factor must remain at or above 600,000
- No new primitive without a known-answer test in `crypto_selftest` and `tests/run.sh`

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
