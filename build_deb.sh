#!/bin/bash

# Simple Debian package builder
set -e

echo "🚀 Building Debian package..."

# Clean previous builds
rm -rf debian/tmp encryptor_* *.deb

# Create package structure
mkdir -p debian/tmp/usr/local/bin
mkdir -p debian/tmp/usr/share/doc/encryptor
mkdir -p debian/tmp/usr/share/man/man1
mkdir -p debian/tmp/DEBIAN

# Copy files
cp encryptor.sh debian/tmp/usr/local/bin/encryptor
chmod 755 debian/tmp/usr/local/bin/encryptor

cp README.md LICENSE debian/tmp/usr/share/doc/encryptor/
cp docs/*.md debian/tmp/usr/share/doc/encryptor/ 2>/dev/null || true

# Copy and compress man page
cp debian/encryptor.1 debian/tmp/usr/share/man/man1/
gzip -9 debian/tmp/usr/share/man/man1/encryptor.1

# Copy control files
cp debian/control debian/tmp/DEBIAN/
cp debian/postinst debian/tmp/DEBIAN/
cp debian/prerm debian/tmp/DEBIAN/
chmod 755 debian/tmp/DEBIAN/postinst debian/tmp/DEBIAN/prerm

# Build package
fakeroot dpkg-deb --build debian/tmp encryptor_1.0.0-1_all.deb

echo "✅ Package built: encryptor_1.0.0-1_all.deb"

# Test package
echo "🧪 Testing package..."
dpkg-deb --info encryptor_1.0.0-1_all.deb
dpkg-deb --contents encryptor_1.0.0-1_all.deb

echo "🎉 Build completed successfully!"