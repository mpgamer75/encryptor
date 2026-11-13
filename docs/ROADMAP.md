# Roadmap

Ideas that fit the project's niche (Bash + OpenSSL, X.509, auditable,
automation-friendly), roughly in priority order. Each entry says *how* it can
be built with the existing architecture.

## Next

1. **Detached signatures** (`encryptor sign` / `verify-signature`)
   `openssl cms -sign -binary -outform DER` with an identity from the store;
   verification with `openssl cms -verify -CAfile`. Adds the sender
   authentication that recipient mode lacks. New engine functions in
   `lib/crypto.sh`, two CLI commands, one TUI screen.

2. **Directory mode** (`encryptor encrypt --archive DIR`)
   Pipe `tar -cf -` into the existing stdin path and record `content: tar` in
   the (authenticated) header so `decrypt --extract` can unpack safely into a
   new directory. Today: `tar cz DIR | encryptor encrypt -o DIR.tgz.enc -`.

3. **Re-key without re-encrypting** (`encryptor rekey`)
   Password change or recipient add/remove currently means decrypt + encrypt.
   Wrapping the master key in the header for *both* modes (password mode would
   wrap a random master with the PBKDF2 key) makes this a header-only rewrite.
   Requires a format revision (`ENCRYPTOR/4`); the reader already rejects
   unknown versions cleanly.

4. **Intermediate CAs and revocation**
   `pathlen`-aware intermediate profile, an index of issued serials, CRL
   generation (`openssl ca -gencrl`), and a revocation check before encrypting
   to a recipient.

5. **Optional memory-hard KDF**
   When the `argon2` reference CLI is installed (it reads the password from
   stdin), offer `--kdf argon2id` and record the parameters in the header.
   Stays opt-in so default files remain decryptable with OpenSSL alone.

## Later

6. **Hardware keys (PKCS#11 / YubiKey PIV)** — `openssl cms -decrypt -engine pkcs11 -keyform engine`
   (or the pkcs11 provider on OpenSSL 3) so the private key never leaves the token.
7. **`age` interoperability backend** — `--backend age` for users who want
   scrypt and chunked streaming and have the binary installed.
8. **Structured audit log** — optional JSON-lines log with tool version,
   OpenSSL version and recipient fingerprints for SIEM ingestion.
9. **Batch manifest** — `encrypt --recursive` with a signed manifest of
   file hashes for backup verification.
10. **Packaging** — Homebrew formula, AUR package, signed release artifacts
    (minisign or CMS signature over `SHA256SUMS`).
11. **Localisation** — message catalogue (the code base is English; earlier
    releases mixed French and English).

## Not planned

- Re-implementing primitives in shell. Everything cryptographic stays inside OpenSSL.
- A chunked AEAD format: it cannot be done from the OpenSSL command line
  without one process per chunk. Use age for pipe-to-pipe streaming.
- Claims of FIPS validation. That is a property of the OpenSSL module in use.
