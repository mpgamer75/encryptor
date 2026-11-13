# The ENCRYPTOR/3 container format

This document specifies the file format written by Encryptor 3.x precisely
enough to re-implement it, and shows how to decrypt a file with nothing but
the `openssl` command.

## Design goals

1. **Authenticated.** Any modification of the header or the ciphertext, and a
   wrong password, must be detected before plaintext is released.
2. **Self-describing.** The file records its own cipher and key-derivation
   parameters. Nothing has to be remembered or guessed at decryption time.
3. **Standard building blocks only.** scrypt and PBKDF2-HMAC-SHA256,
   HMAC-SHA256, `openssl enc`, PKCS#8, CMS. No custom primitives.
4. **Recoverable.** A file must remain decryptable with stock OpenSSL if this
   tool is unavailable.
5. **No secret in argv or on disk** during normal operation.

## Layout

```
ENCRYPTOR/3\n                       magic + format version
mode: password\n                    password | recipient
cipher: aes-256-ctr\n               an OpenSSL cipher name from the allow-list
mac: hmac-sha256\n
...mode-specific fields...\n
---\n                               end of header
<body>                              binary
<tag>                               64 lowercase hex characters, no newline
```

The header is ASCII, one `key: value` per line, LF line endings. Keys match
`[a-z][a-z0-9-]*`; values match `[A-Za-z0-9+/=._:-]+`. Readers ignore unknown
keys (they are still covered by the tag) and reject a file whose header is
longer than 64 lines, has a malformed line, or names a cipher, MAC or KDF that
is not on the allow-list.

### Password mode — scrypt (default)

```
mode: password
cipher: aes-256-ctr
mac: hmac-sha256
kdf: scrypt
sealed: <base64, single line>
---
```

`sealed` is a DER-encoded PKCS#8 `EncryptedPrivateKeyInfo` (RFC 5958) using
PBES2 (RFC 8018) with **scrypt** (RFC 7914) as the key-derivation function and
AES-256-CBC as the cipher. It is produced by

```
openssl pkcs8 -topk8 -scrypt -scrypt_N 16384 -scrypt_r 8 -scrypt_p 5 -v2 aes-256-cbc
```

The private key inside is an X25519 `PrivateKeyInfo` (RFC 8410): the fixed
16-byte prefix `30 2e 02 01 00 30 05 06 03 2b 65 6e 04 22 04 20` followed by
32 random bytes. **Those 32 bytes are the master key.** No X25519 operation is
ever performed: the structure is used only because PKCS#8 is the one place
where the OpenSSL command line runs scrypt with the password supplied through
a pipe, and because its encoding has no optional fields, so every OpenSSL
version produces and parses the same 48 bytes.

The scrypt parameters and salt live inside the structure. Before doing any
work a reader extracts them (`openssl asn1parse`) and rejects: N that is not a
power of two; `N·r > 262144` (more than 32 MiB of memory); `N·r·p > 4194304`
(more than about six times the default work); or a cipher other than
AES-256-CBC.

### Password mode — PBKDF2 (`--kdf pbkdf2`)

```
mode: password
cipher: aes-256-ctr
mac: hmac-sha256
kdf: pbkdf2-hmac-sha256
iter: 600000
salt: 3d00f296b520946d              8 random bytes, hex
---
```

### Recipient mode

```
mode: recipient
cipher: aes-256-ctr
mac: hmac-sha256
keywrap: cms
recipient-fp: <sha256 fingerprint of recipient certificate 1, hex>
recipient-fp: <sha256 fingerprint of recipient certificate 2, hex>
wrapped: <base64, single line>
---
```

`wrapped` is a DER-encoded CMS EnvelopedData structure whose content is the
64-character hex master key, with one RecipientInfo per certificate: RSA keys
use RSA-OAEP with SHA-256 (there is no fallback to PKCS#1 v1.5), EC keys use
ECDH key agreement. `recipient-fp` lines are informational: they let `inspect`
show who can open the file, are not compared with the CMS structure, and are
trustworthy only once the file has been verified.

## Key schedule

```
master   = 32 random bytes, sealed with scrypt in `sealed`          (password mode, scrypt)
master   = PBKDF2-HMAC-SHA256(password, salt, iter, 32 bytes)      (password mode, pbkdf2)
master   = 32 random bytes, wrapped with CMS in `wrapped`           (recipient mode)

body_key = HMAC-SHA256(key = master, msg = "encryptor/3 body-encryption")
mac_key  = HMAC-SHA256(key = master, msg = "encryptor/3 authentication")
```

All three keys are handled as lowercase hex strings. `master`, when used as an
HMAC key, is the 32 raw bytes. The two labels make the encryption and
authentication keys independent.

## Body

The body is exactly the output of

```
openssl enc -<cipher> -pbkdf2 -iter 1 -md sha256 -salt -pass <body_key as 64 hex characters>
```

that is: the 8 bytes `Salted__`, an 8-byte random salt, then the ciphertext.
OpenSSL derives the actual cipher key and IV from the hex `body_key` string and
that salt. One PBKDF2 iteration is sufficient here because `body_key` is
already a uniformly random 256-bit value; the per-file random salt guarantees a
fresh key/IV pair for every file.

## Tag

```
tag = HMAC-SHA256(key = mac_key, msg = every byte of the file before the tag)
```

i.e. the header (from the `E` of `ENCRYPTOR/3` through the newline after
`---`) followed by the body. The tag is appended as 64 lowercase hex
characters.

## Decryption procedure

1. Parse and validate the header (strict grammar, allow-lists, cost bounds).
   `iter` must be a decimal number without leading zeros, between 1000 and
   10,000,000.
2. Obtain `master` (open `sealed` with the password, or run PBKDF2, or
   CMS-decrypt `wrapped` with the private key).
3. Derive `body_key` and `mac_key`.
4. Read `file[0 .. size-64)` **once**. Feed every byte to the HMAC, and the
   bytes from `header_length` onwards to `openssl enc -d`, whose output goes to
   a private in-progress file.
5. Compare the computed tag with the last 64 bytes of the file. If they are
   equal, rename the in-progress file to the requested output; otherwise
   delete it. **Nothing is ever released for a file that does not verify**,
   including one that is modified while it is being read.

When the output is a pipe (where bytes cannot be taken back), the reference
implementation instead copies the ciphertext to a private location, verifies
the tag there, and only then decrypts from that copy.

A wrong password either fails to open `sealed` (step 2) or yields a different
`master`, hence a different `mac_key`, so step 4 fails: "wrong password" and
"modified file" are deliberately reported the same way.

The integrity of `sealed` itself needs no separate protection: it sits in the
authenticated header, and an attacker cannot construct an envelope that opens
under a password they do not know to a key of their choosing. Any change to it
makes step 2 or step 4 fail.

## Security properties and limits

- Confidentiality and integrity of the content; integrity of the header
  (cipher, iteration count and recipients cannot be altered or downgraded).
- Encrypt-then-MAC with independent keys is a standard, provably sound
  composition. With the AES ciphers every primitive is NIST-approved.
- The file length and the recipients' certificate fingerprints are visible.
- The tag is checked once, over the whole file; this is not a chunked
  streaming AEAD. Input from a pipe, and any input whose output is a pipe, is
  staged in a private temporary directory (ciphertext only).
- scrypt at N=2^14, r=8, p=5 costs 16 MiB of memory per password guess. That
  is the largest N the OpenSSL command line accepts for PKCS#8 (it caps scrypt
  memory at 32 MiB); p=5 supplies the rest of the work, and the combination is
  one of the equivalent configurations listed by OWASP. It is memory-hard, but
  less so than Argon2id or scrypt with N=2^17. Password strength still matters.
- With `--kdf pbkdf2` there is no memory-hardness; use it when only
  NIST-approved primitives are acceptable.
- Recipient mode does not authenticate the sender: anyone holding the
  certificate can create a valid file for its owner.
- In PBKDF2 mode the 8-byte salt is the size `openssl enc` supports on every
  OpenSSL version; it prevents precomputation and makes the master key unique
  per file. In scrypt mode the master key is random and the salt is generated
  by OpenSSL inside the envelope.

## Recovery with stock OpenSSL

No Encryptor installation is required. In this emergency procedure the
password and keys appear on the command line, so run it on a machine you
trust and clear your shell history afterwards.

```bash
f=backup.enc
read -rs -p "Password: " PW; echo

hdr_len=$(LC_ALL=C awk '{ n += length($0) + 1 } /^---$/ { print n; exit }' "$f")
salt=$(sed -n '/^---$/q; s/^salt: //p' "$f")
iter=$(sed -n '/^---$/q; s/^iter: //p' "$f")
cipher=$(sed -n '/^---$/q; s/^cipher: //p' "$f")
size=$(wc -c < "$f" | tr -d ' ')

# master key — "kdf: scrypt" files (the default)
master=$(sed -n '/^---$/q; s/^sealed: //p' "$f" | openssl base64 -d -A \
         | openssl pkcs8 -inform DER -outform DER -passin "pass:$PW" \
         | tail -c 32 | od -An -v -tx1 | tr -d ' \n')

# master key — "kdf: pbkdf2-hmac-sha256" files: use this line instead
# master=$(openssl enc -aes-256-ctr -pbkdf2 -iter "$iter" -md sha256 -S "$salt" -P -pass "pass:$PW" \
#          | sed -n 's/^key=//p' | tr 'A-F' 'a-f')

body_key=$(printf '%s' 'encryptor/3 body-encryption' | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$master" -r | cut -d' ' -f1)
mac_key=$(printf '%s' 'encryptor/3 authentication'  | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$master" -r | cut -d' ' -f1)

# 1. authenticate
calc=$(head -c $(( size - 64 )) "$f" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$mac_key" -r | cut -d' ' -f1)
[ "$calc" = "$(tail -c 64 "$f")" ] && echo "authentic" || { echo "WRONG PASSWORD OR MODIFIED FILE"; exit 1; }

# 2. decrypt
head -c $(( size - 64 )) "$f" | tail -c "+$(( hdr_len + 1 ))" \
  | openssl enc -d "-$cipher" -pbkdf2 -iter 1 -md sha256 -pass "pass:$body_key" > recovered.out
```

For a recipient-mode file, replace the `master=` line with:

```bash
master=$(sed -n '/^---$/q; s/^wrapped: //p' "$f" | openssl base64 -d -A \
         | openssl cms -decrypt -binary -inform DER -inkey my.key)
```

Both password variants of this recipe are executed by the test suite
(`tests/run.sh`), so they cannot silently go stale.

## Legacy formats (read-only)

Legacy files are never opened implicitly: `--legacy` must be given. Otherwise
replacing an authenticated file with 2.x-style data would bypass
authentication without any error.

| Written by | Format | Detection | Notes |
|---|---|---|---|
| Encryptor 2.1 | raw `openssl enc -pbkdf2 -iter 600000` | starts with `Salted__` | cipher not recorded; no authentication |
| Encryptor 2.0 | raw `openssl enc -pbkdf2 -iter 100000` | starts with `Salted__` | use `--legacy-iter 100000` |
| Encryptor 2.x | PEM PKCS#7 from `openssl smime -encrypt` | starts with `-----BEGIN PKCS7` | written without `-binary`: line endings in the plaintext may have been converted to CRLF |

A 2.x `.sha256` sidecar, when present, is checked. It is an unkeyed hash: it
detects accidental corruption only.
