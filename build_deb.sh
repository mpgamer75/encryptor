#!/bin/bash

# Debian Package Builder for Encryptor v2.0.0
set -e

VERSION="2.0.0"
PACKAGE_NAME="encryptor_${VERSION}-1_all.deb"

echo "Building Debian package: $PACKAGE_NAME"

# Clean previous builds
rm -rf debian/tmp encryptor_*.deb

# Create package structure
mkdir -p debian/tmp/usr/local/bin
mkdir -p debian/tmp/usr/share/doc/encryptor
mkdir -p debian/tmp/usr/share/man/man1
mkdir -p debian/tmp/DEBIAN

# Copy main script
echo "Copying encryptor.sh to /usr/local/bin/encryptor..."
cp encryptor.sh debian/tmp/usr/local/bin/encryptor
chmod 755 debian/tmp/usr/local/bin/encryptor

# Copy documentation
echo "Copying documentation..."
cp README.md LICENSE debian/tmp/usr/share/doc/encryptor/
cp docs/*.md debian/tmp/usr/share/doc/encryptor/ 2>/dev/null || true

# Copy and compress man page
echo "Installing man page..."
cp debian/encryptor.1 debian/tmp/usr/share/man/man1/
gzip -9 -f debian/tmp/usr/share/man/man1/encryptor.1

# Copy control file
echo "Creating DEBIAN control files..."
cp debian/control debian/tmp/DEBIAN/
cp debian/copyright debian/tmp/usr/share/doc/encryptor/

# Calculate and add installed size
INSTALLED_SIZE=$(du -sk debian/tmp | cut -f1)
echo "Installed-Size: $INSTALLED_SIZE" >> debian/tmp/DEBIAN/control

# Copy maintainer scripts
cp debian/postinst debian/tmp/DEBIAN/
cp debian/prerm debian/tmp/DEBIAN/
chmod 755 debian/tmp/DEBIAN/postinst debian/tmp/DEBIAN/prerm

# Build package
echo "Building .deb package..."
fakeroot dpkg-deb --build debian/tmp "$PACKAGE_NAME"

echo ""
echo "Package built successfully: $PACKAGE_NAME"
echo ""

# Test package
echo "Package Information:"
dpkg-deb --info "$PACKAGE_NAME"
echo ""
echo "Package Contents:"
dpkg-deb --contents "$PACKAGE_NAME"

echo ""
echo "Build completed successfully!"
echo ""
echo "To install: sudo dpkg -i $PACKAGE_NAME"
echo "To remove:  sudo dpkg -r encryptor"