# Cryptography in Encryptor 3

What Encryptor uses, why, and what it deliberately does not claim.
The byte-level format is in [FORMAT.md](FORMAT.md).

## Summary

| Purpose | Algorithm | Standard |
|---|---|---|
| Bulk encryption (default) | AES-256-CTR | FIPS 197, SP 800-38A |
| Bulk encryption (options) | ChaCha20, AES-256-CBC, Camellia-256-CBC, ARIA-256-CBC | RFC 8439, SP 800-38A, RFC 3713, RFC 5794 |
| Integrity / authentication | HMAC-SHA256, encrypt-then-MAC | FIPS 198-1, RFC 2104 |
| Password key derivation (default) | scrypt, N=2^14, r=8, p=5 — memory-hard | RFC 7914, PKCS#8/PBES2 (RFC 8018) |
| Password key derivation (`--kdf pbkdf2`) | PBKDF2-HMAC-SHA256, 600,000 iterations | SP 800-132, RFC 8018 |
| Subkey derivation | HMAC-SHA256 with fixed labels | — |
| Recipient key transport | CMS EnvelopedData: RSA-OAEP (SHA-256) or ECDH | RFC 5652, RFC 8017, RFC 5753 |
| Random numbers | `openssl rand` (OS CSPRNG) | SP 800-90A |

Every cipher is combined with HMAC-SHA256, so **every file is authenticated**
regardless of the cipher chosen. There is no unauthenticated mode for new
files.

## Why encrypt-then-MAC instead of AES-GCM

The OpenSSL manual is explicit: `openssl enc` "does not support authenticated
encryption modes like CCM and GCM, and will not support such modes in the
future." Earlier versions of this project advertised AES-256-GCM; it never
worked, and the S/MIME path that named it failed on OpenSSL 3.

Encryptor 3 therefore builds authenticated encryption from two primitives the
OpenSSL command line *does* expose safely:

1. encrypt with a standard cipher (`openssl enc`), then
2. authenticate the header and the ciphertext with HMAC-SHA256 under an
   independent key.

Encrypt-then-MAC with independent keys is the textbook generic composition
(Bellare–Namprempre) and is what TLS, SSH and IPsec used for years. The tag is
verified before decryption starts, which also removes padding-oracle concerns
for the CBC options.

HMAC is implemented from its RFC 2104 definition on top of `openssl dgst` so
that the key travels through a pipe instead of a command-line argument. The
result is bit-for-bit identical to `openssl dgst -mac HMAC`; the test suite and
`encryptor selftest` check this against RFC 4231 vectors and against OpenSSL
itself.

## Choosing a cipher

| Cipher | Choose it when |
|---|---|
| `aes-256-ctr` (default) | Always, unless you have a reason below. NIST-approved, hardware-accelerated, no padding. |
| `chacha20` | CPUs without AES instructions (older ARM, some embedded). Not NIST-approved. |
| `aes-256-cbc` | You want the most conservative, most widely implemented mode. |
| `camellia-256-cbc` | A policy requires CRYPTREC / Japanese-standard cryptography. |
| `aria-256-cbc` | A policy requires Korean-standard cryptography. |

The security level is the same for all of them in this construction; the
choice is about policy and performance. The cipher is recorded in the file and
covered by the tag, so it cannot be swapped by an attacker.

## Password-based keys

### scrypt (default)

A random 256-bit master key is generated for each file and **sealed** under
the password with scrypt: `N = 2^14, r = 8, p = 5`. Every password guess costs
an attacker 16 MiB of memory and about a quarter of a second of CPU, which is
what blunts GPU and ASIC cracking. This parameter set is one of the equivalent
scrypt configurations in the OWASP Password Storage Cheat Sheet.

How it is done without exposing the password: `openssl kdf` can run scrypt but
only accepts the password as a command-line argument, visible to every user of
the machine. The one place the OpenSSL command line runs scrypt with the
password delivered through a pipe is PKCS#8 private-key encryption. Encryptor
therefore stores the master key as the 32 secret bytes of a standard X25519
private-key structure and lets `openssl pkcs8 -scrypt` encrypt it (PBES2:
scrypt + AES-256-CBC). The X25519 algorithm itself is never used; the
structure is a standard, version-stable envelope that stock OpenSSL can open.
See [FORMAT.md](FORMAT.md).

Why not a larger N: OpenSSL's PKCS#8 code limits scrypt to 32 MiB, so
`N = 2^15` with `r = 8` is refused. `p = 5` makes up the work, as OWASP's
table prescribes. This is weaker memory-hardness than Argon2id or
scrypt at `N = 2^17`, and much stronger than PBKDF2.

A side benefit of sealing a random key: a future `rekey` command can change
the password by rewriting the header only, without re-encrypting the data.

### PBKDF2 (`--kdf pbkdf2` or `ENCRYPTOR_KDF=pbkdf2`)

PBKDF2-HMAC-SHA256 with **600,000 iterations** — the OWASP figure for this
function, and the option OWASP names when FIPS-140 compliance is required.
The iteration count is stored in each file. Use it when policy allows only
NIST-approved algorithms, or when a file must be opened by an OpenSSL build
without scrypt (LibreSSL). It is not memory-hard: compensate with length.
`--iter N` sets the count (minimum 100,000) and implies PBKDF2.

### Either way

Password strength remains the deciding factor. `encryptor passgen` produces a
24-character random password (~142 bits); the interactive UI estimates
strength and warns below ~45 bits. `encryptor audit` reports which KDF new
files will get on this machine.

## Certificate recipients

A random 256-bit file key is generated per file and wrapped once per
recipient inside a CMS EnvelopedData structure:

- **RSA** certificates: RSA-OAEP with SHA-256 (falls back to the library
  default key transport only if the OpenSSL build lacks OAEP options).
- **EC** certificates (P-256, P-384): ephemeral-static ECDH with AES key wrap.

The bulk data is then encrypted exactly as in password mode, so memory use is
constant for any file size. (Encrypting the whole file as one CMS message, as
2.x did via `openssl smime`, needs RAM proportional to the file — about 1.1 GB
for a 400 MB file — and corrupted binary files because `-binary` was missing.)

The wrapped blob sits in the authenticated header. Recipient mode gives
confidentiality and integrity but **not sender authentication**: anyone who
has the certificate can produce a valid file for its owner.

## What is not provided

- Digital signatures / proof of origin.
- Argon2id, or scrypt beyond 16 MiB (limits of the OpenSSL command line, see above).
- Chunked streaming AEAD: integrity is checked over the whole file in a first
  pass, then the file is decrypted in a second pass.
- Post-quantum key exchange.
- Hiding file size or recipient identities.
- A FIPS 140 validation. With an AES cipher and `--kdf pbkdf2`, Encryptor uses
  only approved *algorithms* (scrypt is not one); whether the module is
  validated depends on your OpenSSL build and its configuration.

## Verifying an installation

```bash
encryptor selftest
```

runs known-answer tests (HMAC-SHA256 from RFC 4231, a PBKDF2-HMAC-SHA256
vector checked against an independent implementation, and a fixed
scrypt-sealed envelope that must open to the same key on every OpenSSL
version), encrypt/decrypt round trips with both KDFs, and a tamper test. The installer runs it automatically and refuses
to declare success if it fails.

## References

- OpenSSL `enc` manual: <https://docs.openssl.org/master/man1/openssl-enc/>
- OpenSSL passphrase options: <https://docs.openssl.org/master/man1/openssl-passphrase-options/>
- OWASP Password Storage Cheat Sheet: <https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html>
- NIST SP 800-132 (password-based key derivation), SP 800-38A (block cipher modes), FIPS 198-1 (HMAC)
- RFC 2104 / RFC 4231 (HMAC, test vectors), RFC 7914 (scrypt), RFC 8018 (PBKDF2, PBES2), RFC 5958 (PKCS#8), RFC 8410 (X25519 key encoding), RFC 5652 (CMS), RFC 8017 (RSA-OAEP)
- Bellare, Namprempre: *Authenticated Encryption: Relations among notions and analysis of the generic composition paradigm*
