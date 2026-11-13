# Independent security review — Encryptor 3.0.0

**Date:** 2026-11-13 · **Code reviewed:** branch `claude/zen-wright-yybcov`, commit `40ca0df` · **Fixes verified at:** the commit that adds this file

## What this is, and what it is not

Three reviewers examined the code independently of the author and of each
other. Each was given the source and a scope, not the author's conclusions,
and was asked to attack it and to prove findings by experiment. They were AI
reviewers (Claude sessions with no access to the development conversation),
working in isolated scratch directories with read-only use of the repository.

This is an adversarial code review with reproduced findings. **It is not a
professional third-party cryptographic audit**, it carries no certification,
and it should not be presented as one. An audit by a specialist firm remains
advisable before relying on Encryptor for high-value data. Everything below
is reproducible from the test suite (`tests/run.sh`), which now contains a
regression test for each fixed finding.

| Reviewer | Scope |
|---|---|
| Cryptographic design | `lib/crypto.sh`, `lib/core.sh`, the format and algorithm documents, how the CLI calls the engine |
| Shell implementation | every `lib/*.sh` and `encryptor.sh`: injection, file handling, races, signals, secrets, parsing of untrusted input, the UI |
| PKI and supply chain | `lib/certs.sh`, `lib/audit.sh`, installer and uninstaller, Debian/RPM/Docker packaging, GitHub Actions workflows |

## Result in one paragraph

The core construction held: no reviewer could get a modified, truncated,
extended or spliced ENCRYPTOR/3 file accepted, forge one without the password
or key, inject a command, option, arithmetic expression or format string, or
find a secret in a process argument list, a temporary file or the log. The
problems were around the core: one data-loss bug, a window between verifying
and decrypting, a silent path to the unauthenticated legacy format, unsanitised
terminal output, an installer that trusted its surroundings, and an audit that
could report "pass" wrongly. After merging duplicates there were roughly forty
distinct findings: **none critical, one high, eleven medium, the rest low or
informational. Every high and medium finding is fixed**, as are most of the
others; the remainder are listed under "Accepted or deferred".

## High

| # | Finding | Fix |
|---|---|---|
| H1 | `--shred` with `-o` naming the input by another spelling (`-o ./file file`, an absolute path, a hard link) replaced the input with ciphertext, verified it, then shredded it: plaintext and ciphertext both gone, exit 0. | Input and output are compared by device and inode (`-ef`) in the CLI and in the engine, before encrypting and again immediately before deleting. |

## Medium

| # | Finding | Fix |
|---|---|---|
| M1 | **Verify-then-decrypt read the file twice.** A writer with access to the ciphertext (shared folder, sync client) could change bytes after they were authenticated and before they were decrypted; modified plaintext was written with exit 0. | Decryption to a file is now a single pass: one byte stream feeds both the HMAC and the decryption (through a FIFO), into a private in-progress file that is renamed only if the tag over the bytes actually decrypted is correct. Output to a pipe first stages the ciphertext in the private temp directory. |
| M2 | **Any `Salted__` file was accepted through the unauthenticated 2.x path.** Swapping an authenticated file for 2.x-style data (or random bytes, 1 time in 256 for CBC, always for CTR) produced output with exit 0; `-q` hid the warning. | Legacy files are refused (exit 6) unless `--legacy` is given, before any secret is requested. The warning cannot be silenced. JSON reports `"verified":false`. The UI requires an explicit confirmation. |
| M3 | **Cost parameters were taken from the unauthenticated header with loose bounds**: a 400-byte file could demand 100,000,000 PBKDF2 iterations (about a CPU-minute) from anything that decrypts or verifies untrusted files. | PBKDF2 is capped at 10,000,000 iterations; scrypt at 32 MiB (`N·r`) and about six times the default work (`N·r·p`), enforced by the tool itself before any derivation. Leading zeros are refused. |
| M4 | **Passwords were silently truncated**: only the first line of a multi-line secret was used, and the length limit counted characters while OpenSSL reads about 1 KiB of bytes, so long non-ASCII passphrases collided. | Secrets containing a line break are refused; the limit is 1000 bytes. Applied to passwords, key passphrases and export passwords. |
| M5 | **Terminal escape and line injection** from certificate names and file names: forged UI rows on the certificate-import screen, OSC sequences changing the terminal title. | One `ui_safe` filter (C0, DEL, C1, line separators) on everything derived from a file name, certificate or engine message before display; OpenSSL is asked to escape control characters and only the first line of each field is used. |
| M6 | **Certificate fields could be spoofed**: a subject containing newlines produced a fake issuer and hid the self-signed status; a subject containing `CA:TRUE` made any certificate count as a CA; a subject imitating a key-algorithm line changed the key usage issued. | Subject and issuer are queried separately; self-signed status compares name hashes; CA status, key usage and key type are read from the real extensions and from the public key, never from a text search. Signing also refuses expired or non-signing CAs and leaves that would outlive the CA. |
| M7 | **The installer trusted any `encryptor.sh` + `lib/` beside the script** and ignored `ENCRYPTOR_REF` / `ENCRYPTOR_SHA256` on that path: files planted in `/tmp` next to a saved `install.sh` ran as root. | A directory is used as a source only if it holds the complete file set and is not owned by someone else or writable by group/others; otherwise the installer stops. A pinned ref or checksum always forces a verified download. `--local` / `--download` make the choice explicit. |
| M8 | **The documented pinned install could not verify**: the release `SHA256SUMS` described a different byte stream from the archive the installer downloaded. | For a release tag the installer downloads the release tarball itself and checks it against `ENCRYPTOR_SHA256`, or against the release's `SHA256SUMS`. |
| M9 | **The local audit gave false "pass" results**: 2.x S/MIME files not counted as legacy; key protection judged by a text search; DSA and SHA-1 RSA-PSS certificates not flagged; unparsable `.pem` files and private keys saved as `.pem` skipped silently. | Legacy detection covers both 2.x formats; key encryption is tested structurally; unknown algorithms are warnings, DSA and SHA-1 failures; unreadable certificates, private keys in `.pem` files, weak key-file work factors and leftover in-progress files are reported. |
| M10 | **Private keys and PKCS#12 bundles used 2,048 PBKDF2 iterations**, some 300 times weaker than the tool's own files. | Key files: AES-256 with PBKDF2-HMAC-SHA256 at 600,000 iterations. PKCS#12: 600,000 on OpenSSL 3.x; OpenSSL 1.1.1 cannot raise it, which the UI now states. |
| M11 | **`uninstall.sh` removed any directory named `encryptor.*` in `$TMPDIR`**, including unrelated ones and the live temp directory of a running instance. | Only directories with the exact shape Encryptor creates, owned by the user and untouched for an hour. `--purge` refuses a directory that is not recognisably Encryptor state. |

## Low and informational — fixed

- A directory given as `--output` with `--force` reported success and left the file inside it under a temporary name → refused.
- Numbers with leading zeros were read as octal (`--warn-days 030` meant 24; `--iter 0999999` skipped the range check) → base 10 everywhere.
- The line-mode UI echoed secrets when stdin was a terminal but stdout was not; a generated password went into the pipe → no echo whenever stdin is a terminal; generated passwords are shown on the terminal itself.
- The legacy `.sha256` check was skipped for file names containing `=` (an `awk` pitfall) → parsed without `awk`.
- `--json` could emit invalid JSON for file names that are not valid UTF-8 → non-UTF-8 bytes are replaced (portable validity check; `iconv` is not reliable for this on musl).
- A `--pass-env` password was inherited by every child process → the variable is unset as soon as it has been read.
- `HOME` unset crashed with a Bash error → clear message.
- `--shred` in recipient mode deleted the original after re-parsing only the header → requires `--key` and a real verification; the UI verifies with your own key when you are a recipient, otherwise demands a typed confirmation.
- Recipient certificates were checked only for expiry → not-yet-valid, key usage, RSA < 2048 and EC < 224 bits are refused.
- `inspect` printed "authenticated" for files it had not verified → reports `"verified":false` and says to run `verify`.
- The hand-written HMAC truncated keys longer than 64 bytes instead of hashing them (never reachable) → such keys are refused.
- RSA-OAEP silently fell back to PKCS#1 v1.5 key transport if the first attempt failed → no fallback.
- The CSR signature pre-check never fired on OpenSSL 3.0 (`openssl req -verify` exits 0 on failure) → the message is checked.
- The CSR subject was never shown before signing → shown, with a confirmation; a store name is never derived from an unvalidated file name.
- testssl.sh was pinned by tag name only → the clone must also be the reviewed commit.
- The release job ran tests and builds while holding a write token → split into a read-only build job and a publish job that runs no project code.
- The Docker base image was past end of life → current Alpine release, Dependabot for the base image and the Actions; running as the invoking user is documented and tested.
- Both compatibility jobs were allowed to fail → required. The RPM spec lacked `BuildRequires` and some `Requires` → added and built from them in CI.
- A root install under `umask 077` produced unreadable directories; a failed completion step left an empty file; `ENCRYPTOR_REF` was not validated; old 2.x man pages survived; a 2.x copy in `/usr/local/bin` could shadow the package → all handled.
- `--no-color` was stripped even after `--`; `decrypt --pass-stdin -` was not refused up front; invalid IPv4 octets and C1 controls in certificate fields were accepted; `.deb` lacked `md5sums` → fixed.
- The decrypt screen deleted a `.sha256` file next to any encrypted file → only for legacy files.

Found by the author while verifying the reviews:

- Checks of the form `openssl … | grep -q` can fail intermittently under `pipefail` when the reader exits before the writer has finished. Removed throughout.
- The built-in self-test's tamper check overwrote a byte with a fixed value and so failed spuriously 1 time in 256. Made deterministic.
- On OpenSSL 1.1.1 a scrypt envelope could be created but not opened with the command form first used. Fixed and now covered by a required CI job on that version.

## Accepted or deferred

| Finding | Status |
|---|---|
| The in-progress output file is created exclusively, but later writes use its name: in an output directory that is writable by an attacker **and** lacks the sticky bit, it could be swapped for a symlink. | Accepted. Such a directory offers stronger attacks than this; do not encrypt into one. |
| `--shred` checks for a symbolic link and then calls `shred`, which follows links; someone able to write the directory could race it. | Accepted, same precondition. |
| `recipient-fp` lines in a header are not compared with the recipients inside the CMS blob. | Documented: `inspect` labels them as listed in the header. They are covered by the tag once the file is verified. |
| After `SIGKILL` an in-progress file (plaintext, for a decryption) and a temp directory can remain. | Cannot be prevented. `encryptor audit` now reports both. |
| `inspect --json` exits 0 when its output cannot be written (e.g. disk full). | Deferred (low). |
| GitHub Actions are pinned by version tag, not commit hash; CI container images are not pinned by digest. | Deferred. Both are first-party; Dependabot now tracks them. |
| Any `vX.Y.Z` tag on any commit publishes a release; `SHA256SUMS` is served from the same origin as the artifacts and is not signed. | Deferred to the roadmap (signed releases, protected tags). A compromise of the repository defeats every installer check. |
| scrypt memory is 16 MiB, the ceiling of the OpenSSL command line. | By design; see docs/ALGORITHMS.md. |
| No sender authentication; no chunked streaming AEAD; secrets live in Bash memory. | By design; see SECURITY.md. |

## Checked and found sound

- **Authenticity of ENCRYPTOR/3:** header and body edits, cipher swap, truncation, appended data, header/body splices between files under the same password, duplicate header keys, CRLF, NUL bytes, junk `sealed:` and `wrapped:` values — all rejected with nothing written.
- **Key schedule:** independent body and MAC keys bound to one per-file master; fresh master and independent body salt per file; no key or IV reuse path found.
- **HMAC implementation:** identical to `openssl dgst -mac HMAC` for all-zero, all-one, `0x36`, `0x5c`, `0x25`, `0x0a` and random keys over empty, NUL-containing and large messages, and RFC 4231 cases 1 and 2.
- **scrypt envelope:** parameters extracted and bounded before derivation; wrong password fails; no way found to make `asn1parse` disagree with what `pkcs8` uses; the 48-byte structure is checked after opening.
- **Secrets:** never observed in any `/proc/*/cmdline`, in `/proc/*/environ` (with `--pass-file` / `--pass-stdin`), in temporary files or in the log, including during RSA-4096 generation.
- **Injection:** file names with spaces, quotes, `$()`, globs, leading dashes and newlines; header values; certificate subjects; SAN lists (29 OpenSSL-config payloads round-tripped literally); TLS scan targets. No `eval`; every `read` uses `-r`.
- **PKI:** a leaf cannot act as a CA; extensions requested in a CSR do not leak into the certificate; serials are random; keys are never readable by others at any moment; key/certificate matching is correct for RSA, EC and cross-type pairs.
- **Robustness:** signals during every phase leave no partial output; full disk, closed stdout, unwritable directories and end-of-input at every prompt fail cleanly.
- **Workflows:** no `${{ … }}` inside `run:` blocks; `pull_request`, not `pull_request_target`; the release tag must equal the program version.

## Platforms the fixes were verified on

`tests/run.sh` (168 assertions) passes on OpenSSL 1.1.1 (Alpine 3.14, Ubuntu
20.04), 3.0 (Ubuntu 22.04/24.04), 3.5 (Alpine 3.24, musl), 4.0 (Fedora, during
the RPM build) and on macOS with Homebrew Bash and OpenSSL. The reviewers
themselves tested on OpenSSL 3.0 only.

## Limits

- No professional cryptographer or security firm has examined this code.
- LibreSSL was not tested by anyone. Bash 4.4 itself was not run (5.0 was the oldest).
- Timing side channels were reasoned about, not measured.
- Multi-user races were mostly reasoned, not reproduced.
- Most certificate screens were exercised in line mode or by calling the engine, not through a real terminal.
- The release workflow's publish job has never run: no `v3.0.0` tag exists yet. Its build half runs in CI on every push.
