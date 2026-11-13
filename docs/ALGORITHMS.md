# Cryptography in Encryptor 3

What Encryptor uses, why, and what it deliberately does not claim.
The byte-level format is in [FORMAT.md](FORMAT.md).

## Summary

| Purpose | Algorithm | Standard |
|---|---|---|
| Bulk encryption (default) | AES-256-CTR | FIPS 197, SP 800-38A |
| Bulk encryption (options) | ChaCha20, AES-256-CBC, Camellia-256-CBC, ARIA-256-CBC | RFC 8439, SP 800-38A, RFC 3713, RFC 5794 |
| Integrity / authentication | HMAC-SHA256, encrypt-then-MAC | FIPS 198-1, RFC 2104 |
| Password key derivation | PBKDF2-HMAC-SHA256, 600,000 iterations | SP 800-132, RFC 8018 |
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

PBKDF2-HMAC-SHA256 with **600,000 iterations** — the figure the OWASP Password
Storage Cheat Sheet gives for this function, and the option OWASP recommends
when FIPS-140 compliance is required. The iteration count is stored in each
file, so raising the default later never breaks old files. Override with
`--iter N` or `ENCRYPTOR_PBKDF2_ITER` (minimum 100,000).

**Honest limitation:** PBKDF2 is not memory-hard. Against GPU/ASIC attackers it
is weaker than scrypt or Argon2id at equal user-visible cost. Memory-hard KDFs
are not used because the OpenSSL command line offers no way to run them
without putting the password in the process arguments (`openssl kdf` takes it
only as `-kdfopt pass:`). Compensate with length: `encryptor passgen` produces
a 24-character random password (~142 bits), and the interactive UI estimates
strength and warns below ~45 bits.

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
- Memory-hard password hashing (see above).
- Chunked streaming AEAD: integrity is checked over the whole file in a first
  pass, then the file is decrypted in a second pass.
- Post-quantum key exchange.
- Hiding file size or recipient identities.
- A FIPS 140 validation. With an AES cipher, Encryptor uses only approved
  *algorithms*; whether the module is validated depends on your OpenSSL build
  and its configuration.

## Verifying an installation

```bash
encryptor selftest
```

runs known-answer tests (HMAC-SHA256 from RFC 4231, a PBKDF2-HMAC-SHA256
vector checked against an independent implementation), a full encrypt/decrypt
round trip, and a tamper test. The installer runs it automatically and refuses
to declare success if it fails.

## References

- OpenSSL `enc` manual: <https://docs.openssl.org/master/man1/openssl-enc/>
- OpenSSL passphrase options: <https://docs.openssl.org/master/man1/openssl-passphrase-options/>
- OWASP Password Storage Cheat Sheet: <https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html>
- NIST SP 800-132 (password-based key derivation), SP 800-38A (block cipher modes), FIPS 198-1 (HMAC)
- RFC 2104 / RFC 4231 (HMAC, test vectors), RFC 8018 (PBKDF2), RFC 5652 (CMS), RFC 8017 (RSA-OAEP)
- Bellare, Namprempre: *Authenticated Encryption: Relations among notions and analysis of the generic composition paradigm*
