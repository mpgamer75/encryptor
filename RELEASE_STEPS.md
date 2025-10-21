# Quick Release Steps for Encryptor v2.0.0

## 1. Build the Debian Package

```bash
cd encryptor
chmod +x build_deb.sh
./build_deb.sh
```

✅ This creates: `encryptor_2.0.0-1_all.deb`

## 2. Calculate Checksum

```bash
sha256sum encryptor_2.0.0-1_all.deb
```

📋 **Copy this checksum** - you'll need it for the release notes!

## 3. Commit and Push

```bash
git add .
git commit -m "Release v2.0.0"
git push origin main
```

## 4. Create Git Tag

```bash
git tag -a v2.0.0 -m "Encryptor v2.0.0 - Modern AEAD Encryption"
git push origin v2.0.0
```

## 5. Create GitHub Release

1. Go to: https://github.com/mpgamer75/encryptor/releases
2. Click **"Draft a new release"**
3. Fill in the form:
   - **Tag**: `v2.0.0`
   - **Title**: `Encryptor v2.0.0 - Modern AEAD Encryption`
   - **Description**: Copy from `RELEASE_TEMPLATE.md` (and add checksum!)
4. **Upload file**: Drag and drop `encryptor_2.0.0-1_all.deb`
5. ✅ Check "Set as the latest release"
6. Click **"Publish release"**

## 6. Verify Installation

Test that everything works:

```bash
# Test one-line install
curl -fsSL https://raw.githubusercontent.com/mpgamer75/encryptor/main/install.sh | bash

# Test .deb download
wget https://github.com/mpgamer75/encryptor/releases/download/v2.0.0/encryptor_2.0.0-1_all.deb
sudo dpkg -i encryptor_2.0.0-1_all.deb

# Verify version
encryptor --version

# Test basic functionality
encryptor --help
```

## 7. Announce (Optional)

- Post in GitHub Discussions
- Share on social media
- Update project website

---

## Quick Checklist

Before release:
- [ ] Version is 2.0.0 in all files
- [ ] `./build_deb.sh` completes successfully
- [ ] Package tests: `dpkg-deb --info encryptor_2.0.0-1_all.deb`
- [ ] Local install works: `sudo dpkg -i encryptor_2.0.0-1_all.deb`
- [ ] Script runs: `encryptor --version`

For release:
- [ ] Git tag created and pushed
- [ ] GitHub release created
- [ ] .deb file uploaded to release
- [ ] Checksum added to release notes
- [ ] Installation tested from GitHub

---

## Troubleshooting

**Problem**: Build fails with "fakeroot: command not found"
```bash
sudo apt-get install fakeroot dpkg-dev build-essential
```

**Problem**: Tag already exists
```bash
git tag -d v2.0.0
git push origin :refs/tags/v2.0.0
git tag -a v2.0.0 -m "Release message"
git push origin v2.0.0
```

**Problem**: Package won't install
```bash
# Check dependencies
dpkg-deb --info encryptor_2.0.0-1_all.deb

# Fix missing dependencies
sudo apt-get install -f
```

---

**Need help?** See `.github-release-guide.md` for detailed instructions.

