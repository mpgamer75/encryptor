# Encryptor usage guide

- [Interactive UI](#interactive-ui)
- [Command line](#command-line)
- [Passwords and other secrets](#passwords-and-other-secrets)
- [Certificate recipients](#certificate-recipients)
- [Certificates and keys](#certificates-and-keys)
- [Inspect and verify](#inspect-and-verify)
- [Audit and monitoring](#audit-and-monitoring)
- [Legacy 2.x files](#legacy-2x-files)
- [JSON output](#json-output)
- [Exit codes](#exit-codes)
- [Environment and files](#environment-and-files)
- [Troubleshooting](#troubleshooting)

## Interactive UI

Run `encryptor` with no arguments in a terminal.

| Key | Action |
|---|---|
| `↑` `↓` / `j` `k` | Move |
| `Enter` / `→` | Select |
| `q` / `Esc` / `←` | Back |
| letter or digit shown next to an item | Jump straight to it |
| `PgUp` `PgDn` `Home` `End` | Scroll long lists |
| typing (file browser) | Filter the list; `Esc` clears the filter |

**Encrypt** walks through four steps: pick a file (browse, filter, or *Type a
path* with TAB completion) → choose password or certificate recipients →
enter the secret → result. Leave the password prompt empty to have a strong
one generated and shown once. A strength meter warns about weak passwords.
At the end you may securely delete the original; the encrypted copy is
verified first.

**Decrypt** detects the format, cipher and key type from the file. For
recipient files it finds your matching private key in the store
automatically. You get three attempts at the password.

**Inspect & verify** shows what a file is and who can open it, and can check
its integrity without writing plaintext.

The UI uses the terminal's alternate screen, so your scrollback is restored
when you quit. `Ctrl-C` exits cleanly at any point.

Without a terminal (piped input) the menu refuses to start and points to the
command line. For scripted UI tests set `ENCRYPTOR_ALLOW_PIPED_UI=1`: menus
then become numbered prompts read from standard input.

## Command line

```
encryptor encrypt [options] FILE...
encryptor decrypt [options] FILE...
encryptor inspect [--json] FILE
encryptor verify  [options] FILE
encryptor certs   [--json] [--warn-days N]
encryptor audit   [--json]
encryptor selftest
encryptor passgen [LENGTH]
encryptor completion bash|zsh
encryptor help | version
```

### Encrypt

```bash
encryptor encrypt notes.txt                      # → notes.txt.enc, password prompted twice
encryptor encrypt -p pass.txt a.txt b.txt        # several files, same password
encryptor encrypt -p pass.txt -o out.enc in.dat  # explicit output
encryptor encrypt -a chacha20 -p pass.txt in.dat # another cipher
encryptor encrypt -p pass.txt --shred in.dat     # verify the copy, then delete the original
```

- An existing output is never overwritten unless `--force` is given (exit 5).
- Output files are created with mode 0600.
- A directory is refused with the `tar` one-liner to use instead:

```bash
tar cz project/ | encryptor encrypt -p pass.txt -o project.tgz.enc -
```

### Decrypt

```bash
encryptor decrypt notes.txt.enc                  # → notes.txt
encryptor decrypt -p pass.txt -o - x.enc | less  # to standard output
cat x.enc | encryptor decrypt -p pass.txt -      # from standard input
```

The default output name strips `.enc` (or appends `.dec` if there is no such
suffix). Nothing is written unless authentication succeeds.

### Streams

`-` as FILE reads standard input; `-o -` writes to standard output. Because
the authentication tag is checked before decrypting, input from a pipe is
first spooled to a private temporary file (it contains ciphertext only).

## Passwords and other secrets

Secrets are never accepted as command-line arguments. Sources, in order of
precedence:

| Option | Source |
|---|---|
| `-p`, `--pass-file FILE` | First line of FILE. A warning is printed if the file is readable by others. |
| `--pass-env VAR` | Environment variable VAR. |
| `--pass-stdin` | First line of standard input (not combinable with `-` as input). |
| *(none)* | Prompt on the terminal, without echo. |

With no source and no terminal the command fails with exit 2 rather than
hanging. Passwords may be up to 1000 characters; the first line is used and a
trailing carriage return is removed.

```bash
encryptor passgen          # 24 random characters, ~142 bits
encryptor passgen 40 > pass.txt && chmod 600 pass.txt
```

## Certificate recipients

Encrypt for the holders of X.509 certificates instead of sharing a password:

```bash
encryptor encrypt -r alice.pem -r bob.pem contract.docx
```

Each recipient decrypts with their own private key:

```bash
encryptor decrypt -k alice.key contract.docx.enc
encryptor decrypt -k alice.key --key-pass-file kp.txt contract.docx.enc   # encrypted key
encryptor decrypt -k alice.key -c alice.pem contract.docx.enc             # optional: name the certificate
```

RSA and EC (P-256/P-384) certificates are supported. Expired certificates are
refused. A certificate whose `keyUsage` forbids key encipherment/agreement
(for example a CA certificate) cannot be a recipient.

Recipient mode proves the file was not modified, not who created it.

## Certificates and keys

All objects live in `~/.config/encryptor/certs/` as `NAME.pem` (certificate),
`NAME.key` (private key, mode 0400), `NAME.csr`, `NAME.p12`. The interactive
menu **Certificates & keys** offers:

1. **Quick identity** — a key and a self-signed certificate (825 days) with
   the right extensions to receive encrypted files. Send the `.pem` to your
   correspondents and tell them its SHA-256 fingerprint over another channel.
2. **Import a recipient certificate** — shows the subject and fingerprint and
   asks for confirmation before adding it to the store.
3. **Dashboard** — certificates with days until expiry, key type and whether
   you hold the private key; private keys with mode and passphrase protection.
4. **Inspect** — details plus findings (key size, signature algorithm,
   validity), optionally the full OpenSSL dump.
5. **Create a root CA** — `CA:TRUE, pathlen:0`, `keyCertSign, cRLSign`.
6. **Create key + CSR.**
7. **Sign a CSR** with a profile:
   - *identity*: key encipherment/agreement, e-mail protection, client auth
   - *server*: `serverAuth`; at least one DNS name or IP is required (SAN)
   - *client*: `clientAuth`
   Serial numbers are random 128-bit values.
8. **Check** — does a key belong to a certificate (works for RSA and EC), and
   does the certificate chain to a CA in the store.
9. **Export to PKCS#12** — AES-256-CBC with PBKDF2 and a SHA-256 MAC.

Key types: ECDSA P-256 (default) and P-384, RSA 3072 and 4096. When creating
a key you are asked whether to protect it with a passphrase (recommended;
AES-256).

## Inspect and verify

```bash
$ encryptor inspect contract.docx.enc
File:        contract.docx.enc (48.3 KiB)
Format:      ENCRYPTOR/3 (authenticated, encrypt-then-MAC)
Cipher:      AES-256-CTR + HMAC-SHA256
Key:         2 certificate recipient(s), CMS key wrap
  recipient: sha256:7a38bc15…
  recipient: sha256:b0f274d0…
Payload:     48.0 KiB

$ encryptor verify -p pass.txt backup.enc && echo intact
```

`inspect` needs no secret. `verify` needs the password or key and exits 3 on
any mismatch; it never writes plaintext, which makes it suitable for checking
backups.

## Audit and monitoring

```bash
encryptor audit            # human-readable, with a score
encryptor audit --json     # for CI; exit 1 if any check fails
encryptor certs --warn-days 45 --json   # exit 1 if a certificate expires within 45 days
encryptor selftest         # known-answer tests against the installed OpenSSL
```

The audit checks: OpenSSL and Bash versions, the cryptographic self-test,
cipher availability, the KDF work factor, permissions of the state directory,
private keys and the log, passphrase protection of keys, certificate expiry
and strength, stale temporary directories, legacy unauthenticated files in the
current directory, and core-dump settings.

The interactive audit menu can also run a remote TLS scan with
[testssl.sh](https://testssl.sh) (a pinned release is downloaded on request).
Only host names, IP addresses and `host:port` are accepted as targets. Scan
only systems you are authorised to test.

Cron example:

```cron
0 7 * * 1  encryptor certs --warn-days 30 --json > /var/log/encryptor-certs.json || mail -s "certificates expiring" ops@example.com < /var/log/encryptor-certs.json
```

## Legacy 2.x files

Files written by Encryptor 2.0/2.1 are recognised automatically and can be
decrypted, with a warning that they carry no authentication:

```bash
encryptor decrypt -p pass.txt old.enc                                   # 2.1, aes-256-cbc
encryptor decrypt -p pass.txt -a chacha20 old.enc                       # 2.1, another cipher
encryptor decrypt -p pass.txt -a aes-256-ctr --legacy-iter 100000 old.enc   # written by 2.0
encryptor decrypt -k my.key -c my.pem old-smime.enc                     # 2.x S/MIME
```

The cipher was not stored in 2.x files, so it has to be supplied (default
`aes-256-cbc`). To migrate, decrypt and encrypt again; `encryptor audit`
reports legacy files in the current directory.

## JSON output

With `--json`, one object per processed file is written to standard output
(to standard error when the data itself goes to standard output):

```json
{"status":"success","operation":"encrypt","input":"db.sql","output":"db.sql.enc","format":"encryptor/3","mode":"password","algo":"aes-256-ctr","bytes_in":1048576,"bytes_out":1048768,"ms":612}
{"status":"error","operation":"decrypt","input":"db.sql.enc","code":3,"error":"Authentication failed: wrong password, or the file has been modified or corrupted."}
```

Strings are escaped according to RFC 8259, including file names containing
quotes, backslashes or newlines. The exit status is the first non-zero code
encountered.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Failure |
| 2 | Usage error (bad option, no password source, unknown cipher) |
| 3 | Wrong password or key, or the data failed authentication |
| 4 | Input not found or unreadable |
| 5 | Output exists (without `--force`) or cannot be written |
| 6 | Unsupported or unrecognised format |
| 130 | Interrupted |

## Environment and files

| Variable | Effect |
|---|---|
| `ENCRYPTOR_CONFIG_DIR` | State directory (default `$XDG_CONFIG_HOME/encryptor`, i.e. `~/.config/encryptor`) |
| `ENCRYPTOR_PBKDF2_ITER` | Default iteration count for new files |
| `ENCRYPTOR_NO_LOG=1` | Disable the operation log |
| `NO_COLOR` | Disable colors (`--no-color` does the same) |
| `ENCRYPTOR_ASCII=1` | Force ASCII glyphs in the UI |
| `TMPDIR` | Where the private temporary directory is created |

| Path | Content |
|---|---|
| `~/.config/encryptor/certs/` | Certificates, private keys, CSRs, PKCS#12 bundles (directory mode 0700) |
| `~/.config/encryptor/encryptor.log` | Operation log, mode 0600, rotated at 1 MiB. Operations and file names only. |
| `~/.config/encryptor/tools/` | testssl.sh, if installed from the audit menu |

Shell completion:

```bash
source <(encryptor completion bash)      # add to ~/.bashrc
source <(encryptor completion zsh)       # add to ~/.zshrc
```

## Troubleshooting

**"Authentication failed: wrong password, or the file has been modified or corrupted."**
The tag did not verify. By design the tool cannot tell these cases apart.
Check the password (keyboard layout, trailing spaces in a password file), and
compare the file's size or checksum with the original.

**"Could not unwrap the file key."**
The private key is not one of the recipients, or its passphrase is wrong.
`encryptor inspect FILE` lists recipient fingerprints; compare with
`openssl x509 -in my.pem -noout -fingerprint -sha256`.

**"Could not encrypt the file key for the recipient certificate(s)."**
The certificate does not permit encryption (for example `keyUsage` is limited
to signing, or it is a CA certificate). Use an identity certificate.

**"Algorithm … is not available in this OpenSSL build."**
Some builds (LibreSSL, minimal distributions) omit ARIA or Camellia. Use
`aes-256-ctr`.

**The UI shows `?` or misaligned boxes.**
The terminal is not in a UTF-8 locale. Set `LANG` to a UTF-8 locale or use
`ENCRYPTOR_ASCII=1`.

**Bash too old on macOS.**
`brew install bash openssl@3` and make sure both come first in `PATH`.

**Lost password.**
There is no recovery and no back door.
