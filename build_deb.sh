#!/usr/bin/env bash
# ==============================================================================
# Builds encryptor_<version>-1_all.deb without debhelper.
#
# Layout (Debian policy: packages never install into /usr/local):
#   /usr/bin/encryptor
#   /usr/lib/encryptor/*.sh
#   /usr/share/man/man1/encryptor.1.gz
#   /usr/share/bash-completion/completions/encryptor
#   /usr/share/doc/encryptor/
# ==============================================================================
set -euo pipefail
umask 022      # package contents: 755 directories, 644 files, whatever the builder's umask

cd "$(dirname "${BASH_SOURCE[0]}")"
VERSION="$(sed -n 's/^readonly ENCRYPTOR_VERSION="\(.*\)"$/\1/p' encryptor.sh)"
[[ -n "$VERSION" ]] || { echo "cannot read the version from encryptor.sh" >&2; exit 1; }
PACKAGE="encryptor_${VERSION}-1_all.deb"
STAGE="debian/tmp"
MODULES=(core ui crypto certs audit tui cli)

echo "Building $PACKAGE"
rm -rf -- "$STAGE"
rm -f -- encryptor_*.deb
mkdir -p "$STAGE/DEBIAN" "$STAGE/usr/bin" "$STAGE/usr/lib/encryptor" \
         "$STAGE/usr/share/man/man1" "$STAGE/usr/share/doc/encryptor" \
         "$STAGE/usr/share/bash-completion/completions"

install -m 755 encryptor.sh "$STAGE/usr/bin/encryptor"
for m in "${MODULES[@]}"; do
    [[ -f "lib/$m.sh" ]] || { echo "missing lib/$m.sh" >&2; exit 1; }
    install -m 644 "lib/$m.sh" "$STAGE/usr/lib/encryptor/$m.sh"
done

gzip -9 -n -c man/encryptor.1 > "$STAGE/usr/share/man/man1/encryptor.1.gz"
chmod 644 "$STAGE/usr/share/man/man1/encryptor.1.gz"
bash encryptor.sh completion bash > "$STAGE/usr/share/bash-completion/completions/encryptor"
chmod 644 "$STAGE/usr/share/bash-completion/completions/encryptor"

install -m 644 README.md SECURITY.md docs/*.md "$STAGE/usr/share/doc/encryptor/"
install -m 644 debian/copyright "$STAGE/usr/share/doc/encryptor/copyright"
gzip -9 -n -c CHANGELOG.md > "$STAGE/usr/share/doc/encryptor/changelog.gz"
chmod 644 "$STAGE/usr/share/doc/encryptor/changelog.gz"

sed "s/^Version: .*/Version: ${VERSION}-1/" debian/control > "$STAGE/DEBIAN/control"
printf 'Installed-Size: %s\n' "$(du -sk "$STAGE/usr" | cut -f1)" >> "$STAGE/DEBIAN/control"
install -m 755 debian/postinst debian/prerm "$STAGE/DEBIAN/"
( cd "$STAGE" && find usr -type f -exec md5sum {} + | sort -k 2 ) > "$STAGE/DEBIAN/md5sums"
chmod 644 "$STAGE/DEBIAN/md5sums"

# The staged program must work from its packaged layout before we ship it.
"$STAGE/usr/bin/encryptor" selftest >/dev/null || { echo "self-test of the staged package failed" >&2; exit 1; }

if command -v fakeroot >/dev/null 2>&1; then
    fakeroot dpkg-deb --build "$STAGE" "$PACKAGE" >/dev/null
else
    dpkg-deb --root-owner-group --build "$STAGE" "$PACKAGE" >/dev/null
fi
rm -rf -- "$STAGE"

echo
dpkg-deb --info "$PACKAGE" | sed -n '/Package:/,$p' | sed 's/^/  /' | head -12
echo
echo "Built $PACKAGE"
echo "Install:  sudo apt install ./$PACKAGE"
echo "Remove:   sudo apt remove encryptor"
