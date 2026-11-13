#!/usr/bin/env bash
# ==============================================================================
# Encryptor test suite — plain Bash, no framework required.
#
#   tests/run.sh            run everything
#   tests/run.sh -v         also print passing assertions
#
# Every test runs against a throw-away config directory and work directory.
# Exit status: 0 if all assertions pass, 1 otherwise.
# ==============================================================================
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ENC="$ROOT/encryptor.sh"
VERBOSE=0; [[ "${1:-}" == "-v" ]] && VERBOSE=1

WORK="$(mktemp -d "${TMPDIR:-/tmp}/encryptor-tests.XXXXXXXX")"
trap 'rm -rf "$WORK"' EXIT
export ENCRYPTOR_CONFIG_DIR="$WORK/config"
# Private temp area: the "nothing left behind" checks must not see temporary
# directories of other Encryptor processes running on the same machine.
export TMPDIR="$WORK/tmp"
mkdir -p "$TMPDIR"
export NO_COLOR=1
unset ENCRYPTOR_PBKDF2_ITER ENCRYPTOR_NO_LOG
cd "$WORK" || exit 1

PASS=0; FAIL=0; SECTION=""
section() { SECTION="$1"; printf '\n== %s\n' "$1"; }
ok()   { PASS=$((PASS+1)); (( VERBOSE )) && printf '  ok    %s\n' "$1"; return 0; }
bad()  { FAIL=$((FAIL+1)); printf '  FAIL  %s%s\n' "$1" "${2:+ — $2}"; return 0; }
# check "description" command...   → passes when the command succeeds
check() { local d="$1"; shift; if "$@" >/dev/null 2>&1; then ok "$d"; else bad "$d"; fi; }
# check_rc EXPECTED "description" command...
check_rc() { local want="$1" d="$2" rc=0; shift 2; "$@" >/dev/null 2>&1 || rc=$?; if [[ $rc -eq $want ]]; then ok "$d"; else bad "$d" "exit $rc, expected $want"; fi; }
enc() { bash "$ENC" "$@"; }
# unit FUNCTION — run a test function in a subshell with the libraries loaded.
unit() { ( set -uo pipefail; ENCRYPTOR_VERSION="test"; source "$ROOT/lib/core.sh"; source "$ROOT/lib/ui.sh"; source "$ROOT/lib/crypto.sh"; source "$ROOT/lib/certs.sh"; source "$ROOT/lib/audit.sh"; ui_init plain; core_install_traps; "$@" ); }
# flip_byte FILE OFFSET OUT — copy FILE to OUT with the byte at OFFSET (0-based)
# changed to a value that is guaranteed to differ from the original.
flip_byte() {
    local f="$1" off="$2" out="$3" size old new='\001'
    size=$(wc -c < "$f" | tr -d ' ')
    old=$(head -c $(( off + 1 )) "$f" | tail -c 1 | od -An -v -tx1 | tr -d ' \n')
    [[ "$old" == "01" ]] && new='\002'
    # shellcheck disable=SC2059
    { head -c "$off" "$f"; printf "$new"; tail -c $(( size - off - 1 )) "$f"; } > "$out"
}
# `timeout` is GNU coreutils; fall back to gtimeout (Homebrew) or no limit.
if command -v timeout >/dev/null 2>&1; then TIMEOUT="timeout"; elif command -v gtimeout >/dev/null 2>&1; then TIMEOUT="gtimeout"; else TIMEOUT=""; fi
tmo() { local secs="$1"; shift; if [[ -n "$TIMEOUT" ]]; then "$TIMEOUT" "$secs" "$@"; else "$@"; fi; }
export -f tmo; export TIMEOUT

# Fast KDF for the bulk of the suite (the default work factor is tested once).
FAST=(--iter 100000)

printf 'secret-pass\n' > pass; chmod 600 pass
printf 'wrong-pass\n'  > badpass; chmod 600 badpass
printf 'The quick brown fox\njumps over the lazy dog\n' > plain.txt
head -c 300000 /dev/urandom > random.bin
: > empty.dat

# ------------------------------------------------------------------------------
section "Start-up has no side effects"
check    "version prints"                      bash -c "bash '$ENC' version | grep -q '^Encryptor v[0-9]'"
check    "--version (legacy flag)"             bash -c "bash '$ENC' --version | grep -q '^Encryptor v[0-9]'"
check    "help prints usage"                   bash -c "bash '$ENC' help | grep -q USAGE"
check    "no config dir created by version/help" test ! -e "$ENCRYPTOR_CONFIG_DIR"
check_rc 2 "unknown command is a usage error"  enc frobnicate
check_rc 2 "interactive UI refuses a non-terminal" bash -c "bash '$ENC' </dev/null"

# ------------------------------------------------------------------------------
section "Password mode: round trips"
for c in aes-256-ctr chacha20 aes-256-cbc camellia-256-cbc aria-256-cbc; do
    if enc encrypt "${FAST[@]}" -q -a "$c" -p pass -o "r.$c.enc" random.bin 2>/dev/null &&
       enc decrypt -q -p pass -o "r.$c.out" "r.$c.enc" 2>/dev/null && cmp -s random.bin "r.$c.out"; then
        ok "round trip $c"
    else bad "round trip $c"; fi
done
check "default settings round trip"            bash -c "bash '$ENC' encrypt -q -p pass -o d.enc plain.txt && bash '$ENC' decrypt -q -p pass -o d.out d.enc && cmp -s plain.txt d.out"
if openssl version | grep -q '^OpenSSL'; then
    check "default KDF is scrypt (memory-hard)" grep -aq '^kdf: scrypt$' d.enc
    check "inspect reports the scrypt cost"     bash -c "bash '$ENC' inspect --json d.enc | grep -q '\"kdf\":\"scrypt\",\"scrypt_n\":16384,\"scrypt_r\":8,\"scrypt_p\":5'"
fi
check "--kdf pbkdf2 round trip at 600k"        bash -c "bash '$ENC' encrypt -q --kdf pbkdf2 -p pass -o dp.enc plain.txt && bash '$ENC' decrypt -q -p pass -o dp.out dp.enc && cmp -s plain.txt dp.out"
check "PBKDF2 header records 600000 iterations" grep -aq '^iter: 600000$' dp.enc
check "ENCRYPTOR_KDF=pbkdf2 selects PBKDF2"    bash -c "ENCRYPTOR_KDF=pbkdf2 bash '$ENC' encrypt -q -p pass -o de.enc plain.txt && grep -aq '^kdf: pbkdf2-hmac-sha256$' de.enc"
check_rc 2 "unknown --kdf is refused"          enc encrypt --kdf argon -p pass -o dk.enc plain.txt
check_rc 2 "--iter with --kdf scrypt is refused" enc encrypt --kdf scrypt --iter 200000 -p pass -o dk.enc plain.txt
check "empty file round trip"                 bash -c "bash '$ENC' encrypt ${FAST[*]} -q -p pass empty.dat && bash '$ENC' decrypt -q -p pass -o empty.out empty.dat.enc && cmp -s empty.dat empty.out"
cp plain.txt 'we ird "name" $x.txt'
check "file name with spaces/quotes"          bash -c "bash '$ENC' encrypt ${FAST[*]} -q -p pass 'we ird \"name\" \$x.txt' && bash '$ENC' decrypt -q -p pass -o w.out 'we ird \"name\" \$x.txt.enc' && cmp -s plain.txt w.out"
cp plain.txt ./-dash.txt
check "file name starting with a dash"        bash -c "bash '$ENC' encrypt ${FAST[*]} -q -p pass -- -dash.txt && bash '$ENC' decrypt -q -p pass -o dash.out -- -dash.txt.enc && cmp -s plain.txt dash.out"
check "default decrypt name strips .enc"      bash -c "mkdir -p sub && cp plain.txt sub/a.txt && bash '$ENC' encrypt ${FAST[*]} -q -p pass sub/a.txt && rm sub/a.txt && bash '$ENC' decrypt -q -p pass sub/a.txt.enc && cmp -s plain.txt sub/a.txt"
check "outputs are private (mode 600)"        bash -c "[[ \$(stat -c%a d.enc 2>/dev/null || stat -f%Lp d.enc) == 600 ]]"
check "two encryptions differ (random salt)"  bash -c "bash '$ENC' encrypt ${FAST[*]} -q -p pass -o s1.enc plain.txt && bash '$ENC' encrypt ${FAST[*]} -q -p pass -o s2.enc plain.txt && ! cmp -s s1.enc s2.enc"

# ------------------------------------------------------------------------------
section "Authentication"
enc encrypt "${FAST[@]}" -q -p pass -o auth.enc random.bin
check_rc 3 "wrong password is rejected (exit 3)"   enc decrypt -p badpass -o wrong.out auth.enc
check      "no output written on wrong password"   test ! -e wrong.out
size=$(wc -c < auth.enc | tr -d ' ')
# Flip one byte in the middle of the ciphertext.
flip_byte auth.enc $(( size / 2 )) t-body.enc
check_rc 3 "modified ciphertext is rejected"       enc decrypt -p pass -o t1.out t-body.enc
check      "no output written for modified file"   test ! -e t1.out
sed '1,/^---$/ s/^iter: 100000$/iter: 100001/' auth.enc > t-hdr.enc
check_rc 3 "modified header is rejected"           enc decrypt -p pass -o t2.out t-hdr.enc
sed '1,/^---$/ s/^cipher: aes-256-ctr$/cipher: aes-256-cbc/' auth.enc > t-cipher.enc
check_rc 3 "cipher downgrade/swap is rejected"     enc decrypt -p pass -o t3.out t-cipher.enc
head -c $(( size - 200 )) auth.enc > t-trunc.enc
check_rc 3 "truncated file is rejected"            enc decrypt -p pass -o t4.out t-trunc.enc
{ cat auth.enc; printf 'extra'; } > t-append.enc
check_rc 3 "appended data is rejected"             enc decrypt -p pass -o t5.out t-append.enc
check      "verify succeeds on intact file"        enc verify -p pass auth.enc
check_rc 3 "verify fails with wrong password"      enc verify -p badpass auth.enc
check_rc 6 "garbage is not accepted as a container" enc decrypt -p pass -o g.out plain.txt
printf 'ENCRYPTOR/3\nmode: password\ncipher: none\nmac: hmac-sha256\n---\n' > t-none.enc
check_rc 6 "header naming a non-allow-listed cipher is refused" enc decrypt -p pass -o n.out t-none.enc
printf 'ENCRYPTOR/9\n---\n' > t-future.enc
check_rc 6 "future format version is refused"      enc decrypt -p pass -o f.out t-future.enc
# scrypt-sealed files: same guarantees.
if grep -aq '^kdf: scrypt$' d.enc; then
    enc encrypt -q -p pass -o sc.enc random.bin
    check_rc 3 "scrypt: wrong password is rejected"    enc decrypt -p badpass -o sc1.out sc.enc
    check      "scrypt: nothing written on wrong password" test ! -e sc1.out
    ssize=$(wc -c < sc.enc | tr -d ' ')
    flip_byte sc.enc $(( ssize / 2 )) sc-body.enc
    check_rc 3 "scrypt: modified ciphertext is rejected" enc decrypt -p pass -o sc2.out sc-body.enc
    # Corrupt one character inside the sealed key envelope.
    sed '1,/^---$/ s/^\(sealed: .\{60\}\)./\1A/' sc.enc > sc-seal.enc
    if cmp -s sc.enc sc-seal.enc; then sed '1,/^---$/ s/^\(sealed: .\{60\}\)./\1B/' sc.enc > sc-seal.enc; fi
    rc=0; enc decrypt -p pass -o sc3.out sc-seal.enc >/dev/null 2>&1 || rc=$?
    if [[ $rc -eq 3 || $rc -eq 6 ]] && [[ ! -e sc3.out ]]; then ok "scrypt: modified key envelope is rejected"; else bad "scrypt: modified key envelope is rejected" "exit $rc"; fi
    printf 'ENCRYPTOR/3\nmode: password\ncipher: aes-256-ctr\nmac: hmac-sha256\nkdf: scrypt\nsealed: AAAA\n---\n%0200d' 0 > sc-junk.enc
    check_rc 6 "scrypt: malformed key envelope is refused" enc decrypt -p pass -o sc4.out sc-junk.enc
fi
# Cost parameters in a header are bounded before any derivation runs.
printf 'ENCRYPTOR/3\nmode: password\ncipher: aes-256-ctr\nmac: hmac-sha256\nkdf: pbkdf2-hmac-sha256\niter: 100000000\nsalt: 0011223344556677\n---\n%0264d' 0 > t-dos.enc
check_rc 6 "absurd PBKDF2 iteration count in a header is refused up front" tmo 20 bash "$ENC" decrypt -p pass -o dos.out t-dos.enc
sed '1,/^---$/ s/^iter: 100000$/iter: 0100000/' auth.enc > t-octal.enc
check_rc 6 "iteration count with a leading zero is refused" enc decrypt -p pass -o oct.out t-octal.enc

# The file is read once: a modification made while decrypting can never
# produce modified plaintext. Either the change came too late to be read
# (output identical to the original) or authentication fails with no output.
head -c 80000000 /dev/zero > race.bin
enc encrypt -q --kdf pbkdf2 --iter 100000 -p pass -o race.enc race.bin
( bash "$ENC" decrypt -q -p pass -o race.out race.enc >/dev/null 2>&1; echo $? > race.rc ) &
rpid=$!
sleep 0.25
rold=$(head -c 40000001 race.enc | tail -c 1 | od -An -v -tx1 | tr -d ' \n'); rnew='\377'; [[ "$rold" == "ff" ]] && rnew='\000'
# shellcheck disable=SC2059
printf "$rnew" | dd of=race.enc bs=1 seek=40000000 conv=notrunc 2>/dev/null
wait "$rpid"
rrc=$(cat race.rc)
if [[ "$rrc" == "0" ]] && cmp -s race.bin race.out; then ok "concurrent modification: output is the authentic plaintext"
elif [[ "$rrc" == "3" && ! -e race.out ]]; then ok "concurrent modification: rejected, nothing written"
else bad "concurrent modification during decryption" "exit $rrc, output $([[ -e race.out ]] && echo present || echo absent)"; fi
rm -f race.bin race.enc race.out race.rc
check      "decrypt to stdout stages a private copy and still verifies" bash -c "bash '$ENC' decrypt -q -p pass -o - auth.enc | cmp -s - random.bin"
check_rc 3 "decrypt to stdout emits nothing for a modified file" bash -c "bash '$ENC' decrypt -q -p pass -o - t-body.enc > so.out 2>/dev/null; rc=\$?; [[ -s so.out ]] && exit 99; exit \$rc"
check      "no partial files left behind"          bash -c "! ls | grep -q encryptor-part"

# ------------------------------------------------------------------------------
section "Command-line safety"
check_rc 2 "--algo none is refused"                enc encrypt -a none -p pass -o x.enc plain.txt
check_rc 2 "--algo des-ecb is refused"             enc encrypt -a des-ecb -p pass -o x.enc plain.txt
check      "refused algorithm writes nothing"      test ! -e x.enc
check_rc 2 "missing option value is a usage error" enc encrypt plain.txt --algo
check_rc 2 "no password source without a terminal" bash -c "bash '$ENC' encrypt -o y.enc plain.txt </dev/null"
check_rc 2 "--iter below the minimum is refused"   enc encrypt --iter 10 -p pass -o y.enc plain.txt
check_rc 4 "missing input file (exit 4)"           enc encrypt -p pass nope.txt
check_rc 4 "directory input is refused with advice" enc encrypt -p pass sub
echo precious > keep.enc
check_rc 5 "existing output is not overwritten (exit 5)" enc encrypt "${FAST[@]}" -p pass -o keep.enc plain.txt
check      "existing output untouched"             grep -q precious keep.enc
check      "--force overwrites"                    enc encrypt "${FAST[@]}" -q -f -p pass -o keep.enc plain.txt
check_rc 2 "input == output is refused"            enc encrypt -f -p pass -o plain.txt plain.txt
check_rc 2 "--output with several inputs is refused" enc encrypt -p pass -o z.enc plain.txt random.bin
# Data-loss regression: -o naming the input by another spelling, with --shred.
printf 'ONLY COPY\n' > only.txt
check_rc 2 "same file under another spelling is refused (./name)" enc encrypt "${FAST[@]}" --shred -f -p pass -o ./only.txt only.txt
check_rc 2 "same file under another spelling is refused (absolute path)" enc encrypt "${FAST[@]}" --shred -f -p pass -o "$PWD/only.txt" only.txt
ln only.txt only-link.txt 2>/dev/null && check_rc 2 "same file through a hard link is refused" enc encrypt "${FAST[@]}" --shred -f -p pass -o only-link.txt only.txt
check      "the only copy survived every refused attempt" bash -c "[[ \"\$(cat only.txt)\" == 'ONLY COPY' ]]"
mkdir -p outdir
check_rc 5 "a directory as --output is refused, even with --force" enc encrypt "${FAST[@]}" -f -p pass -o outdir plain.txt
check      "nothing was written into that directory" bash -c "[[ -z \"\$(ls -A outdir)\" ]]"
check_rc 5 "a directory as decrypt --output is refused" enc decrypt -f -p pass -o outdir d.enc
cp plain.txt $'esc\033]0;owned\007name.txt'
check      "control characters in file names never reach the terminal" bash -c "! bash '$ENC' encrypt ${FAST[*]} -f -p pass $'esc\033]0;owned\007name.txt' 2>&1 | grep -q \$'\033'"
check      "HOME unset gives a clear error, not a crash" bash -c "env -u HOME -u XDG_CONFIG_HOME -u ENCRYPTOR_CONFIG_DIR bash '$ENC' version 2>&1 | grep -q 'HOME is not set'"
check_rc 2 "decrypt --pass-stdin with stdin input is refused" bash -c "echo x | bash '$ENC' decrypt --pass-stdin -o - -"
check_rc 2 "password containing a line break is refused (no silent truncation)" bash -c "PW=\$'first line\nsecond line' bash '$ENC' encrypt ${FAST[*]} --pass-env PW -o nl.enc plain.txt"
check      "nothing written for a refused password" test ! -e nl.enc
check_rc 2 "over-long multi-byte password is refused by byte length" bash -c "PW=\$(printf 'é%.0s' \$(seq 1 600)) LC_ALL=C.UTF-8 bash '$ENC' encrypt ${FAST[*]} --pass-env PW -o long.enc plain.txt"
check      "--iter with a leading zero is read as decimal" bash -c "bash '$ENC' encrypt -q --iter 0100000 -p pass -o lz.enc plain.txt && grep -aq '^iter: 100000$' lz.enc"
check      "password via environment variable"     bash -c "PW=envpw bash '$ENC' encrypt ${FAST[*]} -q --pass-env PW -o env.enc plain.txt && PW=envpw bash '$ENC' decrypt -q --pass-env PW -o env.out env.enc && cmp -s plain.txt env.out"
check      "password via stdin"                    bash -c "echo stdinpw | bash '$ENC' encrypt ${FAST[*]} -q --pass-stdin -o si.enc plain.txt && echo stdinpw | bash '$ENC' decrypt -q --pass-stdin -o si.out si.enc && cmp -s plain.txt si.out"
check      "stdin → file, file → stdout"           bash -c "cat random.bin | bash '$ENC' encrypt ${FAST[*]} -q -p pass -o pipe.enc - && bash '$ENC' decrypt -q -p pass -o - pipe.enc | cmp -s - random.bin"
check      "stdin → stdout both ways"              bash -c "cat plain.txt | bash '$ENC' encrypt ${FAST[*]} -q -p pass - | bash '$ENC' decrypt -q -p pass - | cmp -s - plain.txt"
check      "multiple inputs"                       bash -c "cp plain.txt m1 && cp plain.txt m2 && bash '$ENC' encrypt ${FAST[*]} -q -p pass m1 m2 && test -f m1.enc -a -f m2.enc"
check      "--shred removes the input after verification" bash -c "cp plain.txt sh.txt && bash '$ENC' encrypt ${FAST[*]} -q -p pass --shred sh.txt && test ! -e sh.txt -a -f sh.txt.enc"
check      "legacy flag syntax still works"        bash -c "bash '$ENC' --encrypt plain.txt --algo aes-256-cbc --pass-file pass --output lf.enc ${FAST[*]} -q && bash '$ENC' --decrypt lf.enc --pass-file pass --output lf.out -q && cmp -s plain.txt lf.out"

# ------------------------------------------------------------------------------
section "JSON output"
json_ok() { if command -v python3 >/dev/null 2>&1; then python3 -c 'import sys,json; [json.loads(l) for l in sys.stdin if l.strip()]'; else grep -q '^{.*}$'; fi; }
cp plain.txt 'js"on\name.txt'
check "encrypt --json is valid JSON even with quotes/backslashes in names" bash -c "$(declare -f json_ok); bash '$ENC' encrypt ${FAST[*]} -p pass --json 'js\"on\\name.txt' | json_ok"
check "error --json is valid JSON and exit 3"  bash -c "$(declare -f json_ok); out=\$(bash '$ENC' decrypt -p badpass -o j.out --json auth.enc 2>/dev/null); rc=\$?; echo \"\$out\" | json_ok && [[ \$rc -eq 3 ]] && echo \"\$out\" | grep -q '\"status\":\"error\"'"
if cp plain.txt $'bad\xff\xfename.txt' 2>/dev/null; then     # some filesystems refuse such names
    check "--json stays valid for file names that are not valid UTF-8" bash -c "$(declare -f json_ok); bash '$ENC' encrypt ${FAST[*]} -f -p pass --json \$'bad\xff\xfename.txt' | json_ok"
fi
t_utf8() { _core_is_utf8 "héllo wörld ✓" && _core_is_utf8 "plain" && ! _core_is_utf8 $'bad\xff' && ! _core_is_utf8 $'trunc\xc3' && ! _core_is_utf8 $'overlong\xc0\xaf'; }
check "UTF-8 validity check (portable, no iconv)" unit t_utf8
check "inspect --json is valid JSON"            bash -c "$(declare -f json_ok); bash '$ENC' inspect --json auth.enc | json_ok"
check "inspect reports cipher and iterations"   bash -c "bash '$ENC' inspect --json auth.enc | grep -q '\"cipher\":\"aes-256-ctr\".*\"iterations\":100000'"
check "inspect never claims a file is verified" bash -c "bash '$ENC' inspect --json auth.enc | grep -q '\"verified\":false' && ! bash '$ENC' inspect --json auth.enc | grep -q 'authenticated'"
check "audit --json is valid JSON"              bash -c "$(declare -f json_ok); bash '$ENC' audit --json | json_ok"
check "certs --json is valid JSON"              bash -c "$(declare -f json_ok); bash '$ENC' certs --json | json_ok"

# ------------------------------------------------------------------------------
section "Certificate recipients"
openssl req -x509 -newkey rsa:2048 -days 30 -nodes -keyout rsa.key -out rsa.pem -subj "/CN=rsa-user" \
    -addext "keyUsage=digitalSignature,keyEncipherment" >/dev/null 2>&1
openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -days 30 -nodes -keyout ec.key -out ec.pem -subj "/CN=ec-user" >/dev/null 2>&1
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -aes-256-cbc -pass pass:keypw -out locked.key >/dev/null 2>&1
openssl req -x509 -new -key locked.key -passin pass:keypw -days 30 -out locked.pem -subj "/CN=locked-user" >/dev/null 2>&1
openssl genpkey -algorithm RSA -pkeyopt rsa_keygen_bits:2048 -out stranger.key >/dev/null 2>&1
printf 'keypw\n' > keypass; chmod 600 keypass

check      "encrypt for three recipients"          enc encrypt -q -r rsa.pem -r ec.pem -r locked.pem -o rcpt.enc random.bin
check      "RSA recipient decrypts"                bash -c "bash '$ENC' decrypt -q -k rsa.key -o r1.out rcpt.enc && cmp -s random.bin r1.out"
check      "EC recipient decrypts (with --cert)"   bash -c "bash '$ENC' decrypt -q -k ec.key -c ec.pem -o r2.out rcpt.enc && cmp -s random.bin r2.out"
check      "passphrase-protected key decrypts"     bash -c "bash '$ENC' decrypt -q -k locked.key --key-pass-file keypass -o r3.out rcpt.enc && cmp -s random.bin r3.out"
check_rc 3 "a non-recipient key is rejected"       enc decrypt -k stranger.key -o r4.out rcpt.enc
check      "nothing written for a non-recipient"   test ! -e r4.out
check_rc 2 "recipient file without --key is a usage error" bash -c "bash '$ENC' decrypt -o r5.out rcpt.enc </dev/null"
check      "inspect lists three recipients"        bash -c "[[ \$(bash '$ENC' inspect rcpt.enc | grep -c 'recipient: sha256:') -eq 3 ]]"
rsize=$(wc -c < rcpt.enc | tr -d ' ')
flip_byte rcpt.enc $(( rsize - 500 )) rcpt-bad.enc
check_rc 3 "modified recipient file is rejected"   enc decrypt -k rsa.key -o r6.out rcpt-bad.enc
openssl req -x509 -newkey rsa:2048 -days 30 -nodes -keyout sign.key -out sign.pem -subj "/CN=sign-only" -addext "keyUsage=critical,digitalSignature" >/dev/null 2>&1
openssl req -x509 -newkey rsa:1024 -days 30 -nodes -keyout weak.key -out weak.pem -subj "/CN=weak" >/dev/null 2>&1
check_rc 1 "signing-only certificate is refused as a recipient" enc encrypt -r sign.pem -o r8.enc plain.txt
if [[ -s weak.pem ]]; then check_rc 1 "RSA-1024 certificate is refused as a recipient" enc encrypt -r weak.pem -o r9.enc plain.txt; fi
check      "refused recipients write nothing"       bash -c "! ls r8.enc r9.enc 2>/dev/null | grep -q ."
check_rc 2 "--shred with recipients requires --key to verify" bash -c "cp plain.txt rs.txt && bash '$ENC' encrypt -q -r rsa.pem --shred rs.txt"
check      "original kept when --shred is refused"  test -f rs.txt
check      "--shred with recipients verifies with --key, then deletes" bash -c "bash '$ENC' encrypt -q -f -r rsa.pem -k rsa.key --shred rs.txt && test ! -e rs.txt && bash '$ENC' decrypt -q -k rsa.key -o rs.out rs.txt.enc && cmp -s plain.txt rs.out"
check_rc 3 "--shred keeps the original when the key cannot open the result" bash -c "cp plain.txt rs2.txt && bash '$ENC' encrypt -q -r rsa.pem -k stranger.key --shred rs2.txt; rc=\$?; test -f rs2.txt || exit 99; [[ \$rc -ne 0 ]] && exit 3"
check_rc 4 "missing recipient certificate"         enc encrypt -r nope.pem -o r7.enc plain.txt
check_rc 4 "a non-certificate recipient is refused" enc encrypt -r plain.txt -o r7.enc plain.txt
check      "v2 syntax (--algo smime --cert) maps to recipients" bash -c "bash '$ENC' --encrypt plain.txt --algo smime --cert rsa.pem --output v2s.enc -q && bash '$ENC' decrypt -q -k rsa.key -o v2s.out v2s.enc && cmp -s plain.txt v2s.out"

# ------------------------------------------------------------------------------
section "Legacy 2.x files"
openssl enc -aes-256-cbc -salt -pbkdf2 -iter 600000 -in plain.txt -out v21.enc -pass pass:secret-pass 2>/dev/null
openssl enc -aes-256-ctr -salt -pbkdf2 -iter 100000 -in plain.txt -out v20.enc -pass pass:secret-pass 2>/dev/null
check_rc 6 "legacy file is refused without --legacy"       enc decrypt -p pass -o v21.no v21.enc
check      "nothing written when a legacy file is refused" test ! -e v21.no
check_rc 6 "legacy refusal is not bypassed by -q or --algo" enc decrypt -q -a aes-256-cbc -p pass -o v21.no v21.enc
# Substitution: an attacker swaps an authenticated file for 2.x-style data.
{ printf 'Salted__'; head -c 56 /dev/urandom; } > swapped.enc
check_rc 6 "v3 file replaced by raw 'Salted__' data is refused" enc decrypt -q -a aes-256-ctr -p pass -o swapped.out swapped.enc
check      "2.1 file (aes-256-cbc, 600k) decrypts with --legacy" bash -c "bash '$ENC' decrypt --legacy -q -p pass -o v21.out v21.enc 2>/dev/null && cmp -s plain.txt v21.out"
check      "2.0 file (aes-256-ctr, 100k) decrypts with --legacy" bash -c "bash '$ENC' decrypt --legacy -q -p pass -a aes-256-ctr --legacy-iter 100000 -o v20.out v20.enc 2>/dev/null && cmp -s plain.txt v20.out"
check      "legacy warning is printed even with --quiet"   bash -c "bash '$ENC' decrypt --legacy -q -f -p pass -o v21.out v21.enc 2>&1 | grep -q 'NOT authenticated'"
check      "legacy JSON result says verified:false"        bash -c "bash '$ENC' decrypt --legacy -f --json -p pass -o v21.out v21.enc 2>/dev/null | grep -q '\"verified\":false'"
check      "v3 JSON result says verified:true"             bash -c "bash '$ENC' decrypt -f --json -p pass -o auth.jout auth.enc | grep -q '\"verified\":true'"
check_rc 3 "2.1 file with wrong password fails"    enc decrypt --legacy -p badpass -o v21w.out v21.enc
check      "inspect flags legacy as unauthenticated" bash -c "bash '$ENC' inspect v21.enc | grep -q 'NOT authenticated'"
check_rc 6 "verify refuses legacy files"           enc verify -p pass v21.enc
printf '%s  v21.enc\n' "0000000000000000000000000000000000000000000000000000000000000000" > v21.enc.sha256
check_rc 3 "legacy sidecar mismatch is detected"   enc decrypt --legacy -p pass -o v21s.out v21.enc
rm -f v21.enc.sha256
cp v21.enc 'a=b.enc'; printf '%s  a=b.enc\n' "0000000000000000000000000000000000000000000000000000000000000000" > 'a=b.enc.sha256'
check_rc 3 "sidecar check also works for names containing '='" bash -c "bash '$ENC' decrypt --legacy -p pass -o ab.out 'a=b.enc' </dev/null"
if openssl smime -encrypt -aes-256-cbc -binary -in plain.txt -out v2smime.enc -outform PEM rsa.pem 2>/dev/null && [[ -s v2smime.enc ]]; then
    check_rc 6 "2.x S/MIME file is refused without --legacy" enc decrypt -k rsa.key -c rsa.pem -o v2smime.no v2smime.enc
    check  "2.x S/MIME file decrypts with --legacy" bash -c "bash '$ENC' decrypt --legacy -q -k rsa.key -c rsa.pem -o v2smime.out v2smime.enc 2>/dev/null && cmp -s plain.txt v2smime.out"
fi

# ------------------------------------------------------------------------------
section "Engine internals"
t_hmac() {
    local i key want got
    for i in 1 2 3 4 5; do
        key=$(openssl rand -hex 32)
        want=$(openssl dgst -sha256 -mac HMAC -macopt "hexkey:$key" -r random.bin); want=${want%% *}
        got=$(_crypto_hmac "$key" < random.bin)
        [[ "$want" == "$got" ]] || return 1
    done
    # Keys containing 00, 0a, 25 (%), 5c (\) bytes.
    key="00250a5c00250a5c00250a5c00250a5c00250a5c00250a5c00250a5c00250a5c"
    want=$(openssl dgst -sha256 -mac HMAC -macopt "hexkey:$key" -r plain.txt); want=${want%% *}
    [[ "$want" == "$(_crypto_hmac "$key" < plain.txt)" ]]
}
check "HMAC-SHA256 matches OpenSSL's implementation" unit t_hmac
t_hmac_longkey() { ! printf 'x' | _crypto_hmac "$(printf 'ab%.0s' $(seq 1 65))" >/dev/null && ! printf 'x' | _crypto_hmac "zz" >/dev/null && ! printf 'x' | _crypto_hmac "" >/dev/null; }
check "HMAC refuses keys it would not handle per RFC 2104" unit t_hmac_longkey
t_pbkdf2() { [[ "$(_crypto_pbkdf2 "encryptor-selftest" "0001020304050607" 1000)" == "b62df00c273cfbe46c0e32299cc54f143709d1b0b28b6f674a2fb0d68f8a16fa" ]]; }
check "PBKDF2-HMAC-SHA256 known answer"             unit t_pbkdf2
check "built-in self-test passes"                   enc selftest
t_json() { [[ "$(json_escape $'a"b\\c\nd\te')" == 'a\"b\\c\nd\te' ]]; }
check "JSON escaping"                               unit t_json
t_trim() { [[ "$(trim $'  -n  a b \t')" == "-n  a b" ]]; }
check "trim handles option-like input"              unit t_trim
t_names() { is_safe_name "alice-1.x" && ! is_safe_name "../etc" && ! is_safe_name "a/b" && ! is_safe_name "" && ! is_safe_name "-x" && ! is_safe_name "a..b"; }
check "store names reject path traversal"           unit t_names
t_targets() {
    audit_valid_target "example.com" && audit_valid_target "example.com:8443" && audit_valid_target "10.0.0.1" && audit_valid_target "[::1]:443" &&
    ! audit_valid_target "--file=/etc/passwd" && ! audit_valid_target "-oA" && ! audit_valid_target "a b" && ! audit_valid_target 'x;id' && ! audit_valid_target 'x$(id)' && ! audit_valid_target ""
}
check "TLS scan targets cannot be option-injected"  unit t_targets
t_pwbits() { (( $(crypto_password_bits "abc") < 45 )) && (( $(crypto_password_bits "correct horse battery staple") > 90 )); }
check "password strength estimate"                  unit t_pwbits
check "passgen length and alphabet"                 bash -c "[[ \$(bash '$ENC' passgen 32) =~ ^[A-Za-z0-9]{32}\$ ]]"

t_scrypt() {
    crypto_scrypt_available || return 0
    [[ "$(_crypto_sealed_params "$CRYPTO_KAT_SCRYPT_SEALED")" == "1024:8:1" ]] || return 1
    [[ "$(_crypto_unseal_master "$CRYPTO_KAT_SCRYPT_SEALED" "encryptor-selftest")" == "$CRYPTO_KAT_SCRYPT_MASTER" ]] || return 2
    ! _crypto_unseal_master "$CRYPTO_KAT_SCRYPT_SEALED" "wrong" >/dev/null || return 3
    # Seal/unseal round trip with the production cost.
    local m b; m=$(openssl rand -hex 32)
    b=$(_crypto_seal_master "$m" "pw with spaces") || return 4
    [[ "$(_crypto_sealed_params "$b")" == "16384:8:5" ]] || return 5
    [[ "$(_crypto_unseal_master "$b" "pw with spaces")" == "$m" ]] || return 6
    # Out-of-range work factors must be refused before any derivation.
    local fmt big
    fmt=$(_crypto_hex_fmt "${ENC_SEAL_PREFIX}${m}")
    # shellcheck disable=SC2059
    # ~13x the default work (N*r*p): a crafted file must not be able to demand it.
    big=$(printf "$fmt" | openssl pkcs8 -topk8 -inform DER -outform DER -scrypt -scrypt_N 16384 -scrypt_r 8 -scrypt_p 64 -passout pass:x 2>/dev/null | openssl base64 -A)
    [[ -n "$big" ]] || return 7
    ! _crypto_sealed_params "$big" >/dev/null || return 8
    ! _crypto_sealed_params "AAAA" >/dev/null || return 9
    ! _crypto_sealed_params "" >/dev/null || return 10
}
if unit t_scrypt; then ok "scrypt envelope: fixed vector, round trip, parameter bounds"; else bad "scrypt envelope: fixed vector, round trip, parameter bounds" "step $?"; fi

# The same, for a scrypt-sealed file.
recover_scrypt() {
    local f="$1" pw="$2" hdr_len cipher master ek mk size
    hdr_len=$(LC_ALL=C awk '{ n += length($0) + 1 } /^---$/ { print n; exit }' "$f")
    cipher=$(sed -n '/^---$/q; s/^cipher: //p' "$f")
    master=$(sed -n '/^---$/q; s/^sealed: //p' "$f" | openssl base64 -d -A \
             | openssl pkcs8 -inform DER -outform DER -passin "pass:$pw" | tail -c 32 | od -An -v -tx1 | tr -d ' \n')
    ek=$(printf '%s' 'encryptor/3 body-encryption' | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$master" -r | cut -d' ' -f1)
    mk=$(printf '%s' 'encryptor/3 authentication'  | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$master" -r | cut -d' ' -f1)
    size=$(wc -c < "$f" | tr -d ' ')
    [[ "$(head -c $(( size - 64 )) "$f" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$mk" -r | cut -d' ' -f1)" == "$(tail -c 64 "$f")" ]] || return 1
    head -c $(( size - 64 )) "$f" | tail -c "+$(( hdr_len + 1 ))" | openssl enc -d "-$cipher" -pbkdf2 -iter 1 -md sha256 -pass "pass:$ek"
}
if [[ -f sc.enc ]]; then
    check "documented openssl-only recovery works for scrypt files" bash -c "$(declare -f recover_scrypt); recover_scrypt sc.enc secret-pass | cmp -s - random.bin"
fi

# The documented recovery recipe (docs/FORMAT.md) using nothing but openssl.
recover() {
    local f="$1" pw="$2" hdr_len salt iter cipher master ek mk size
    hdr_len=$(LC_ALL=C awk '{ n += length($0) + 1 } /^---$/ { print n; exit }' "$f")
    salt=$(sed -n '/^---$/q; s/^salt: //p' "$f"); iter=$(sed -n '/^---$/q; s/^iter: //p' "$f"); cipher=$(sed -n '/^---$/q; s/^cipher: //p' "$f")
    master=$(openssl enc -aes-256-ctr -pbkdf2 -iter "$iter" -md sha256 -S "$salt" -P -pass "pass:$pw" | sed -n 's/^key=//p' | tr 'A-F' 'a-f')
    ek=$(printf '%s' 'encryptor/3 body-encryption' | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$master" -r | cut -d' ' -f1)
    mk=$(printf '%s' 'encryptor/3 authentication'  | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$master" -r | cut -d' ' -f1)
    size=$(wc -c < "$f" | tr -d ' ')
    [[ "$(head -c $(( size - 64 )) "$f" | openssl dgst -sha256 -mac HMAC -macopt "hexkey:$mk" -r | cut -d' ' -f1)" == "$(tail -c 64 "$f")" ]] || return 1
    head -c $(( size - 64 )) "$f" | tail -c "+$(( hdr_len + 1 ))" | openssl enc -d "-$cipher" -pbkdf2 -iter 1 -md sha256 -pass "pass:$ek"
}
check "documented openssl-only recovery recipe works" bash -c "$(declare -f recover); recover auth.enc secret-pass | cmp -s - random.bin"

# Secrets must never appear in any process argument list.
if [[ -d /proc/self ]]; then
    openssl rand -hex 16 > canary.pass; chmod 600 canary.pass   # random: cannot collide with any command line
    head -c 60000000 /dev/zero > big.dat
    ( bash "$ENC" encrypt -q --iter 6000000 -p canary.pass -o big.enc big.dat ) &
    epid=$!; leaked=0; hit=""
    for _ in $(seq 1 60); do
        # -f keeps the canary out of grep's own argument list.
        hit=$(grep -alsF -f canary.pass /proc/[0-9]*/cmdline 2>/dev/null | head -n 1)
        if [[ -n "$hit" ]]; then leaked=1; hit=$(tr '\0' ' ' < "$hit" 2>/dev/null | cut -c1-120); break; fi
        kill -0 "$epid" 2>/dev/null || break
        sleep 0.05
    done
    wait "$epid" 2>/dev/null
    if (( leaked )); then bad "password never appears in process arguments" "seen in: $hit"; else ok "password never appears in process arguments"; fi
    check "password never written to the temp directory" bash -c "! grep -rslF -f canary.pass '${TMPDIR:-/tmp}'/encryptor.* 2>/dev/null | grep -q ."
    rm -f big.dat big.enc
fi
check "no temp directories left behind"             bash -c "! ls -d '${TMPDIR:-/tmp}'/encryptor.?????????? 2>/dev/null | grep -q ."

# ------------------------------------------------------------------------------
section "PKI engine"
t_pki() {
    core_init_state
    pki_create_identity "id-ec" "Test O'User #1" "t@example.com" ec256 30 "" || return 1
    pki_create_identity "id-rsa" "RSA User" "" rsa3072 30 "key-pass" || return 2
    [[ "$(get_file_mode "$CERT_DIR/id-ec.key")" == "400" ]] || return 3
    crypto_key_is_encrypted "$CERT_DIR/id-rsa.key" || return 4
    ! crypto_key_is_encrypted "$CERT_DIR/id-ec.key" || return 5
    pki_match "$CERT_DIR/id-ec.pem" "$CERT_DIR/id-ec.key" || return 6
    pki_match "$CERT_DIR/id-rsa.pem" "$CERT_DIR/id-rsa.key" "key-pass" || return 7
    pki_match "$CERT_DIR/id-ec.pem" "$CERT_DIR/id-rsa.key" "key-pass"; [[ $? -eq 1 ]] || return 8
    ! pki_create_identity "../evil" "x" "" ec256 30 "" || return 9
    ! pki_create_identity "id-ec" "dup" "" ec256 30 "" || return 10
    pki_create_ca "ca" "Test CA" "ACME & Sons" "FR" ec256 365 "ca-pass" || return 11
    pki_cert_info "$CERT_DIR/ca.pem" && [[ "${PKI_INFO[is_ca]}" == 1 ]] || return 12
    pki_create_csr "leaf" "leaf.example.com" "" "" ec256 "" || return 13
    ! pki_sign_csr "$CERT_DIR/leaf.csr" "$CERT_DIR/ca.pem" "$CERT_DIR/ca.key" server 90 "" "$CERT_DIR/leaf.pem" "ca-pass" || return 14     # SAN required
    ! pki_sign_csr "$CERT_DIR/leaf.csr" "$CERT_DIR/ca.pem" "$CERT_DIR/ca.key" server 90 "leaf.example.com" "$CERT_DIR/leaf.pem" "wrong" || return 15
    pki_sign_csr "$CERT_DIR/leaf.csr" "$CERT_DIR/ca.pem" "$CERT_DIR/ca.key" server 90 "leaf.example.com, 10.0.0.5" "$CERT_DIR/leaf.pem" "ca-pass" || return 16
    pki_verify_chain "$CERT_DIR/leaf.pem" "$CERT_DIR/ca.pem" || return 17
    pki_cert_info "$CERT_DIR/leaf.pem" || return 18
    [[ "${PKI_INFO[is_ca]}" == 0 && "${PKI_INFO[san]}" == *"DNS:leaf.example.com"* && "${PKI_INFO[san]}" == *"IP Address:10.0.0.5"* && "${PKI_INFO[eku]}" == *"Server Authentication"* ]] || return 19
    ! pki_sign_csr "$CERT_DIR/leaf.csr" "$CERT_DIR/id-ec.pem" "$CERT_DIR/id-ec.key" identity 90 "" "$CERT_DIR/x.pem" "" || return 20   # not a CA
    pki_export_p12 "$CERT_DIR/id-rsa.pem" "$CERT_DIR/id-rsa.key" "$CERT_DIR/id-rsa.p12" "export-pass" "key-pass" || return 21
    openssl pkcs12 -in "$CERT_DIR/id-rsa.p12" -passin pass:export-pass -nokeys >/dev/null 2>&1 || return 22
    ! pki_export_p12 "$CERT_DIR/id-ec.pem" "$CERT_DIR/id-ec.key" "$CERT_DIR/e.p12" "" || return 23           # empty password
    pki_report_json 7 >/dev/null || return 24
    return 0
}
if unit t_pki; then ok "identity / CA / CSR / signing / match / PKCS#12"; else bad "identity / CA / CSR / signing / match / PKCS#12" "step $?"; fi
t_pki_hardening() {
    core_init_state
    core_tmpdir
    local d="$TEMP_DIR/h"; mkdir -p "$d"
    # 1. Key files are protected with PBKDF2 at 600,000 iterations (0x0927C0), and detection is structural.
    # (No early-exit readers on pipelines here: with pipefail a SIGPIPE in the writer would look like a failure.)
    openssl asn1parse -in "$CERT_DIR/id-rsa.key" 2>/dev/null | grep 'INTEGER *:0927C0' >/dev/null || return 1
    cp "$CERT_DIR/id-ec.key" "$d/fake.key"; chmod 600 "$d/fake.key"
    printf '# was: -----BEGIN ENCRYPTED PRIVATE KEY-----\n' >> "$d/fake.key"
    ! crypto_key_is_encrypted "$d/fake.key" || return 2
    if [[ "$(openssl pkcs12 -help 2>&1)" == *" -iter "* ]]; then      # not available on OpenSSL 1.1.1
        openssl pkcs12 -in "$CERT_DIR/id-rsa.p12" -passin pass:export-pass -nokeys -info 2>&1 | grep 'Iteration 600000' >/dev/null || return 3
    fi
    # 2. A certificate whose subject imitates other fields must not fool the parser.
    printf '[req]\nprompt=no\ndistinguished_name=dn\n[dn]\nCN=Not a CA:TRUE authority Public Key Algorithm: rsaEncryption\n' > "$d/spoof.cnf"
    openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 -keyout "$d/spoof.key" -out "$d/spoof.pem" \
        -config "$d/spoof.cnf" -addext "basicConstraints=critical,CA:FALSE" >/dev/null 2>&1 || return 4
    pki_cert_info "$d/spoof.pem" || return 5
    [[ "${PKI_INFO[is_ca]}" == 0 && "${PKI_INFO[key_type]}" == ec && "${PKI_INFO[self_signed]}" == 1 ]] || return 6
    ! crypto_cert_is_rsa "$d/spoof.pem" || return 7
    ! pki_sign_csr "$CERT_DIR/leaf.csr" "$d/spoof.pem" "$d/spoof.key" client 30 "" "$d/x.pem" "" || return 8
    # 3. Newline / escape injection through a DN: one line per field, no control bytes.
    printf '[req]\nprompt=no\ndistinguished_name=dn\nstring_mask=utf8only\nutf8=yes\n[dn]\nCN=Mallory\nL=x\\nissuer=CN=Trusted Root CA\n' > "$d/nl.cnf"
    if openssl req -x509 -newkey ec -pkeyopt ec_paramgen_curve:P-256 -nodes -days 30 -keyout "$d/nl.key" -out "$d/nl.pem" -config "$d/nl.cnf" >/dev/null 2>&1; then
        pki_cert_info "$d/nl.pem" || return 9
        [[ "${PKI_INFO[issuer]}" != "CN=Trusted Root CA" && "${PKI_INFO[self_signed]}" == 1 ]] || return 10
        [[ "${PKI_INFO[subject]}${PKI_INFO[issuer]}" != *[$'\001'-$'\037']* ]] || return 11
    fi
    # 4. A leaf may not outlive its CA; an expired or non-signing CA is refused.
    ! pki_sign_csr "$CERT_DIR/leaf.csr" "$CERT_DIR/ca.pem" "$CERT_DIR/ca.key" client 5000 "" "$d/long.pem" "ca-pass" || return 12
    [[ "$ENC_ERR" == *"CA itself expires"* ]] || return 13
    # 5. Input validation.
    ! pki_valid_ip "999.1.1.1" || return 14
    pki_valid_ip "10.0.0.255" || return 15
    ! pki_valid_text $'evil\xc2\x9b31mname' || return 16
    pki_valid_days 030 || return 17
    ! pki_valid_days 0 || return 18
    # 6. Recipient checks come from the public key and real extensions.
    crypto_check_recipient "$CERT_DIR/id-ec.pem" || return 19
    ! crypto_check_recipient "$CERT_DIR/ca.pem" || return 20          # keyUsage: keyCertSign, cRLSign only
    # 7. Passphrases with line breaks are refused rather than truncated.
    ! pki_create_identity "nl-id" "x" "" ec256 30 $'two\nlines' || return 21
    [[ ! -e "$CERT_DIR/nl-id.key" ]] || return 22
    return 0
}
if unit t_pki_hardening; then ok "PKI hardening: key-file KDF, spoof-proof parsing, CA and recipient checks"; else bad "PKI hardening: key-file KDF, spoof-proof parsing, CA and recipient checks" "step $?"; fi
t_audit_findings() {
    core_init_state
    printf 'not a certificate\n' > "$CERT_DIR/broken.pem"
    audit_run "$PWD" >/dev/null 2>&1
    local i hit=0 leg=0
    for (( i = 0; i < ${#AUDIT_ID[@]}; i++ )); do
        [[ "${AUDIT_ID[$i]}" == "cert-unreadable" && "${AUDIT_STATUS[$i]}" == "warn" ]] && hit=1
        [[ "${AUDIT_ID[$i]}" == "legacy" && "${AUDIT_STATUS[$i]}" == "warn" ]] && leg=1
    done
    rm -f "$CERT_DIR/broken.pem"
    (( hit == 1 && leg == 1 ))
}
check "audit reports unreadable certificates and legacy files (incl. S/MIME)" unit t_audit_findings
check "identity created by the tool works as a recipient" bash -c "bash '$ENC' encrypt -q -r '$ENCRYPTOR_CONFIG_DIR/certs/id-ec.pem' -r '$ENCRYPTOR_CONFIG_DIR/certs/id-rsa.pem' -o id.enc plain.txt && bash '$ENC' decrypt -q -k '$ENCRYPTOR_CONFIG_DIR/certs/id-ec.key' -o id.out id.enc && cmp -s plain.txt id.out"
check "certs report lists the store"            bash -c "bash '$ENC' certs | grep -q 'id-ec'"
check_rc 1 "certs --warn-days flags expiring certificates (exit 1)" enc certs --warn-days 60
check      "--warn-days with a leading zero is decimal" bash -c "bash '$ENC' certs --json --warn-days 010 | grep -q '\"warn_days\":10'"
check      "--warn-days 09 is accepted"                 bash -c "bash '$ENC' certs --json --warn-days 09 | grep -q '\"warn_days\":9'"
check "state directory is private (700)"        bash -c "[[ \$(stat -c%a '$ENCRYPTOR_CONFIG_DIR' 2>/dev/null || stat -f%Lp '$ENCRYPTOR_CONFIG_DIR') == 700 ]]"
check "operation log is private (600)"          bash -c "[[ \$(stat -c%a '$ENCRYPTOR_CONFIG_DIR/encryptor.log' 2>/dev/null || stat -f%Lp '$ENCRYPTOR_CONFIG_DIR/encryptor.log') == 600 ]]"
cp plain.txt $'log\ninjection [SUCCESS] forged'
enc encrypt "${FAST[@]}" -q -f -p pass -o li.enc $'log\ninjection [SUCCESS] forged' 2>/dev/null
check "log lines cannot be forged through file names" bash -c "! grep -q '^injection' '$ENCRYPTOR_CONFIG_DIR/encryptor.log'"

# ------------------------------------------------------------------------------
section "Audit and interactive smoke test"
check    "audit runs and reports a score"       bash -c "bash '$ENC' audit | grep -q 'Score'"
check    "line-mode menu quits cleanly"         bash -c "printf 'q\n' | ENCRYPTOR_ALLOW_PIPED_UI=1 bash '$ENC' | grep -q 'Main menu'"
check    "line-mode menu survives EOF (no infinite loop)" bash -c "ENCRYPTOR_ALLOW_PIPED_UI=1 tmo 10 bash '$ENC' </dev/null"
check    "line-mode: encrypt wizard end to end" bash -c "cp plain.txt wiz.txt && printf '%s\n' e wiz.txt p wizard-password-123 wizard-password-123 n '' q | ENCRYPTOR_ALLOW_PIPED_UI=1 tmo 60 bash '$ENC' >/dev/null 2>&1; printf 'wizard-password-123\n' > wp && chmod 600 wp && bash '$ENC' decrypt -q -p wp -o wiz.out wiz.txt.enc && cmp -s plain.txt wiz.out"
check    "completion script is valid bash"      bash -c "bash '$ENC' completion bash | bash -n"

# ------------------------------------------------------------------------------
section "Installer and uninstaller"
check    "install from the checkout into a prefix"   bash -c "'$ROOT/install.sh' --prefix '$WORK/prefix' >/dev/null 2>&1 && '$WORK/prefix/bin/encryptor' version | grep -q '^Encryptor v'"
check    "installed tree is world-readable even under umask 077" bash -c "(umask 077; '$ROOT/install.sh' --prefix '$WORK/prefix77' >/dev/null 2>&1); [[ \$(stat -c%a '$WORK/prefix77/lib/encryptor' 2>/dev/null || stat -f%Lp '$WORK/prefix77/lib/encryptor') == 755 ]]"
# Files planted next to a lone install.sh in a directory others can write.
mkdir -p planted/lib planted/tests planted/man; chmod 777 planted
for m in core ui crypto certs audit tui cli; do echo ': planted' > "planted/lib/$m.sh"; done
printf '#!/bin/bash\necho PWNED >> "%s/pwned.log"\n' "$WORK" > planted/encryptor.sh
touch planted/tests/run.sh planted/man/encryptor.1; cp "$ROOT/install.sh" planted/
check_rc 1 "installer refuses sources in a directory others can write" bash -c "cd / && bash '$WORK/planted/install.sh' --prefix '$WORK/prefix-planted'"
check    "planted code was never executed"           test ! -e "$WORK/pwned.log"
check_rc 1 "--local cannot be combined with a pinned ref" bash -c "ENCRYPTOR_REF=v0.0.0 '$ROOT/install.sh' --local --prefix '$WORK/prefix-x'"
check_rc 1 "an invalid ENCRYPTOR_REF is refused"     bash -c "ENCRYPTOR_REF='../../other/repo' '$ROOT/install.sh' --prefix '$WORK/prefix-x'"
mkdir -p "$TMPDIR/encryptor.wiki" "$TMPDIR/encryptor_backup-2026"
check    "uninstall removes the prefix install"      bash -c "'$ROOT/uninstall.sh' --prefix '$WORK/prefix' </dev/null >/dev/null 2>&1; test ! -e '$WORK/prefix/bin/encryptor'"
check    "uninstall leaves unrelated 'encryptor*' directories in TMPDIR alone" test -d "$TMPDIR/encryptor.wiki" -a -d "$TMPDIR/encryptor_backup-2026"
check    "uninstall keeps user data without confirmation" test -d "$ENCRYPTOR_CONFIG_DIR/certs"

# ------------------------------------------------------------------------------
printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
(( FAIL == 0 ))
