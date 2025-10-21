# 🧪 TEST NOW - Quick Testing Guide

## ⚡ Quick Start (2 minutes)

```bash
# 1. Check version
bash encryptor.sh --version
# Should show: Encryptor v2.0.0

# 2. Launch and test menu
bash encryptor.sh
# Try: 1, 2, 3, 4, 5, h, l, q
# All should work perfectly!
```

---

## 🔥 Critical Tests (Must Pass)

### Test 1: Encryption Works ✅
```bash
# Create test file
echo "Hello World" > test.txt

# Launch encryptor
bash encryptor.sh

# Workflow:
1. Choose: 2 (Encrypt a File)
2. Select: test.txt (type 1 or filename)
3. Choose algorithm: 1 (AES-256-GCM)
4. Enter password: test123
5. Confirm password: test123

# ✅ Should create: test.txt.enc
# ✅ Should show success report
```

### Test 2: Decryption Works ✅
```bash
bash encryptor.sh

# Workflow:
1. Choose: 3 (Decrypt a File)
2. Select: test.txt.enc
3. Choose algorithm: 1 (AES-256-GCM)
4. Enter password: test123

# ✅ Should create: test.txt.dec
# ✅ Content should be: "Hello World"
```

### Test 3: Certificate Manager Enhanced ✅
```bash
bash encryptor.sh

# Workflow:
1. Choose: 4 (Certificate Manager)
2. Choose: 1 (Create Root CA)
3. Enter name: TestCA (or press Enter for default)

# ✅ Should show explanations
# ✅ Should create TestCA.key and TestCA.pem
# ✅ Should show "Next steps"

# Then test:
4. Choose: 5 (List managed files)

# ✅ Should show organized listing
# ✅ Files grouped by category
# ✅ Permission indicators shown
```

---

## 📋 Feature Checklist

### Main Menu
- [ ] Option 1 (List Files) - Shows directory files
- [ ] Option 2 (Encrypt) - **MUST WORK** 🔥
- [ ] Option 3 (Decrypt) - **MUST WORK** 🔥
- [ ] Option 4 (Certificate Manager) - Shows submenu
- [ ] Option 5 (Security Audit) - Runs audits
- [ ] Option h (Help) - Shows help
- [ ] Option l (Logs) - Shows logs
- [ ] Option q (Quit) - Exits cleanly

### Certificate Manager
- [ ] Option 1 - Shows "What is a Root CA?"
- [ ] Option 2 - Shows "What is this?"
- [ ] Option 3 - **Lists available CSRs** before asking
- [ ] Option 4 - **Lists available files** before asking
- [ ] Option 5 - **Organized by category** (not raw ls)

### User Experience
- [ ] File listings appear before prompts
- [ ] Can type just filename (auto-completion works)
- [ ] Error messages show tips
- [ ] "Next steps" appear after operations
- [ ] Security warnings prominent
- [ ] Colors and formatting clear

---

## 🎯 Success Criteria

All of these MUST be TRUE:
- ✅ No "Invalid choice" errors
- ✅ Encryption creates .enc file
- ✅ Decryption creates .dec file
- ✅ Certificate Manager shows file listings
- ✅ Inspect option lists available files
- ✅ List option shows organized output
- ✅ Error messages have helpful tips
- ✅ No crashes or hangs

---

## 📸 What to Look For

### Good Signs ✅
- Clear explanations before actions
- Files listed before prompts
- "What is this?" sections
- "Next steps" guidance
- Organized file listings
- Permission indicators (✓/⚠)
- Helpful error messages

### Bad Signs ❌
- "Invalid choice" errors
- "File not found" without help
- Raw `ls` output
- No explanations
- Cryptic error messages
- Unorganized listings

---

## 🐛 If Something Fails

### Problem: Option 2 or 3 still not working
**Check**:
```bash
# Verify version
bash encryptor.sh --version
# Must be: v2.0.0

# Check bash version
bash --version
# Must be: 4.0+

# Check OpenSSL
openssl version
# Must be: 1.1.1+
```

### Problem: Certificate options confusing
**Expected**: Each option should show:
1. Clear title (":: Create Root CA ::")
2. Explanation ("What is a Root CA?")
3. File listings (if applicable)
4. Helpful prompts
5. "Next steps" after success

If not seeing this → file not updated correctly

### Problem: Menus still show "Invalid choice"
**Solution**: 
```bash
# Re-download the file
wget https://raw.githubusercontent.com/mpgamer75/encryptor/main/encryptor.sh
chmod +x encryptor.sh
bash encryptor.sh
```

---

## ✅ Final Verification

After all tests pass:

```bash
# 1. Clean test
rm -f test.txt* TestCA.*

# 2. Full workflow
bash encryptor.sh

# Create CA
4 → 1 → "MyCA" → [Enter]

# Generate Key
[q] → 4 → 2 → "user1" → [Enter]

# Sign CSR
[q] → 4 → 3 → "user1.csr" → "MyCA.pem" → "MyCA.key" → [Enter]

# Inspect
[q] → 4 → 4 → "MyCA.pem" → [Enter]

# List all
[q] → 4 → 5 → [Enter]

# Should all work smoothly with clear guidance!
```

---

## 🚀 If All Tests Pass

**Congratulations!** The tool is ready!

Next steps:
1. Build .deb: `./build_deb.sh`
2. Follow `RELEASE_STEPS.md`
3. Create GitHub release

---

## 📞 Report Results

Please test and report:
- ✅ What works perfectly
- ⚠️ What needs minor tweaks
- ❌ What still doesn't work

**Priority**: Options 2 and 3 MUST work!

---

**Happy Testing!** 🎉

