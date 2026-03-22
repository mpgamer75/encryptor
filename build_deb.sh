#!/usr/bin/env bash

# Debian Package Builder for Encryptor v2.1.0
set -eo pipefail

VERSION="2.1.0"
PACKAGE_NAME="encryptor_${VERSION}-1_all.deb"

echo "════════════════════════════════════════════════════════════════"
echo "  Building Debian package: $PACKAGE_NAME"
echo "════════════════════════════════════════════════════════════════"
echo

# Clean previous builds
rm -rf debian/tmp encryptor_*.deb 2>/dev/null || true

# Create package structure
echo "[1/8] Creating package directory structure..."
mkdir -p debian/tmp/usr/local/bin
mkdir -p debian/tmp/usr/local/lib/encryptor
mkdir -p debian/tmp/usr/share/doc/encryptor
mkdir -p debian/tmp/usr/share/man/man1
mkdir -p debian/tmp/DEBIAN

# Copy main script and patch LIB_DIR to installed path
echo "[2/8] Installing encryptor binary..."
sed 's|LIB_DIR="$SCRIPT_DIR/lib"|LIB_DIR="/usr/local/lib/encryptor"|' \
    encryptor.sh > debian/tmp/usr/local/bin/encryptor
chmod 755 debian/tmp/usr/local/bin/encryptor
echo "       ✓ Installed encryptor → /usr/local/bin/encryptor (LIB_DIR patched)"

# Copy lib/ modules
echo "[2b/8] Installing library modules..."
for mod in lib/ui.sh lib/crypto.sh lib/certs.sh lib/audit.sh; do
    if [[ -f "$mod" ]]; then
        cp "$mod" debian/tmp/usr/local/lib/encryptor/
        chmod 644 "debian/tmp/usr/local/lib/encryptor/$(basename "$mod")"
        echo "       ✓ Copied $mod → /usr/local/lib/encryptor/"
    else
        echo "       ⚠ WARNING: $mod not found — package may be incomplete"
    fi
done

# Copy documentation
echo "[3/8] Installing documentation..."
cp README.md LICENSE CHANGELOG.md debian/tmp/usr/share/doc/encryptor/
echo "       ✓ Copied README.md, LICENSE, CHANGELOG.md"

# Copy additional docs if they exist
if [[ -d docs ]]; then
    cp docs/*.md debian/tmp/usr/share/doc/encryptor/ 2>/dev/null || true
    echo "       ✓ Copied docs/*.md"
else
    echo "       ⚠ docs/ directory not found (optional)"
fi

# Copy and compress man page
echo "[4/8] Installing man page..."
cp debian/encryptor.1 debian/tmp/usr/share/man/man1/
gzip -9 -f debian/tmp/usr/share/man/man1/encryptor.1
echo "       ✓ Compressed and installed man page"

# Copy control file
echo "[5/8] Creating DEBIAN control files..."
cp debian/control debian/tmp/DEBIAN/
cp debian/copyright debian/tmp/usr/share/doc/encryptor/

# Calculate and add installed size
INSTALLED_SIZE=$(du -sk debian/tmp | cut -f1)
echo "Installed-Size: $INSTALLED_SIZE" >> debian/tmp/DEBIAN/control
echo "       ✓ Calculated installed size: ${INSTALLED_SIZE}KB"

# Copy maintainer scripts
cp debian/postinst debian/tmp/DEBIAN/
cp debian/prerm debian/tmp/DEBIAN/
chmod 755 debian/tmp/DEBIAN/postinst debian/tmp/DEBIAN/prerm
echo "       ✓ Installed maintainer scripts"

# Build package
echo "[6/8] Building .deb package..."
fakeroot dpkg-deb --build debian/tmp "$PACKAGE_NAME" >/dev/null 2>&1
echo "       ✓ Package built successfully"

echo
echo "════════════════════════════════════════════════════════════════"
echo "  Package built: $PACKAGE_NAME"
echo "════════════════════════════════════════════════════════════════"
echo

# Test package
echo "[7/8] Package Information:"
echo "────────────────────────────────────────────────────────────────"
dpkg-deb --info "$PACKAGE_NAME" | grep -E "Package:|Version:|Architecture:|Maintainer:|Description:" | sed 's/^/  /'
echo

echo "[8/8] Package Contents:"
echo "────────────────────────────────────────────────────────────────"
dpkg-deb --contents "$PACKAGE_NAME" | grep -E "(bin/encryptor|man|doc)" | awk '{print "  " $6}' | head -10
echo "  ... (use 'dpkg-deb --contents $PACKAGE_NAME' for full list)"

echo
echo "════════════════════════════════════════════════════════════════"
echo "  Build completed successfully!"
echo "════════════════════════════════════════════════════════════════"
echo
echo "Installation:"
echo "  sudo dpkg -i $PACKAGE_NAME"
echo
echo "Removal:"
echo "  sudo dpkg -r encryptor"
echo
echo "Testing:"
echo "  lintian $PACKAGE_NAME  # Check package quality (if lintian installed)"
echo