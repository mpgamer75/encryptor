# 🔐 OpenSSL Compatibility Guide

## Gestion Intelligente des Versions OpenSSL

Encryptor gère automatiquement toutes les versions d'OpenSSL avec un système de fallback intelligent.

---

## 🎯 Versions OpenSSL Supportées

### OpenSSL 3.x (Recommandé) ✅
- **Support**: Complet
- **Algorithmes AEAD**: ✅ AES-256-GCM, ChaCha20-Poly1305
- **CMS**: ✅ Complet
- **Performance**: Excellent avec accélération matérielle
- **Sécurité**: Dernier niveau de sécurité

**Distributions avec OpenSSL 3.x par défaut**:
- Ubuntu 22.04+ (Jammy Jellyfish)
- Debian 12+ (Bookworm)
- Fedora 36+
- Rocky Linux 9+
- AlmaLinux 9+
- Arch Linux (rolling)
- macOS (via Homebrew)

### OpenSSL 1.1.x (Recommandé) ✅
- **Support**: Complet
- **Algorithmes AEAD**: ✅ Via CMS
- **CMS**: ✅ Complet
- **Performance**: Très bon
- **Sécurité**: Excellent

**Distributions avec OpenSSL 1.1.x par défaut**:
- Ubuntu 18.04 - 21.10
- Debian 10-11 (Buster, Bullseye)
- CentOS 8
- RHEL 8
- Fedora 26-35

### OpenSSL 1.0.2 (Fallback Automatique) ⚠️
- **Support**: Partiel avec fallback
- **Algorithmes AEAD**: ❌ Non supporté
- **Fallback**: ✅ Utilise AES-256-CBC automatiquement
- **Performance**: Bon
- **Sécurité**: Toujours sécurisé (AES-256-CBC)

**Distributions avec OpenSSL 1.0.2 par défaut**:
- Ubuntu 16.04 (EOL mais encore utilisé)
- Debian 9 (Stretch)
- CentOS 7
- RHEL 7

---

## 🔄 Système de Fallback

### Hiérarchie d'Algorithmes

Quand tu choisis **AES-256-GCM** ou **ChaCha20-Poly1305**:

```
1. Essai avec openssl cms -encrypt -aes256-gcm
   ✅ Si réussi → Utilise AEAD moderne
   ❌ Si échoue → Passe à l'étape 2

2. Fallback vers openssl enc -aes-256-cbc
   ✅ Utilise AES-256-CBC (toujours très sécurisé!)
   📢 Message à l'utilisateur: "Note: AEAD cipher not available, using AES-256-CBC"
```

### Messages Utilisateur

**Avec OpenSSL 3.x / 1.1.x:**
```
Encrypting with modern AEAD cipher...
✓ Encryption successful!
Algorithm: AES-256-GCM
```

**Avec OpenSSL 1.0.2:**
```
Encrypting with modern AEAD cipher...
Note: AEAD cipher not available, using AES-256-CBC (still very secure)
✓ Encryption successful!
Algorithm: AES-256-CBC
```

---

## 📋 Vérification lors de l'Installation

### Ce que `install.sh` vérifie:

```bash
1. Détecte la distribution Linux/macOS
2. Vérifie la version d'OpenSSL installée
3. Teste les capacités CMS
4. Vérifie le support AEAD
5. Affiche le niveau de support:
   ✅ OpenSSL 3.x → Full modern cryptography support
   ✅ OpenSSL 1.1.x → AEAD ciphers supported
   ⚠️  OpenSSL 1.0.x → Modern AEAD ciphers not fully supported
```

### Recommandations Automatiques

Si OpenSSL 1.0.x détecté, `install.sh` propose:

**Ubuntu/Debian**:
```bash
sudo apt update
sudo apt install --upgrade openssl libssl-dev
```

**CentOS/RHEL 8+**:
```bash
sudo dnf update openssl openssl-libs
```

**Fedora**:
```bash
sudo dnf update openssl openssl-libs
```

**Arch Linux**:
```bash
sudo pacman -Syu openssl
```

**macOS** (Homebrew):
```bash
brew update
brew install openssl@3
brew link --force openssl@3
export PATH="/usr/local/opt/openssl@3/bin:$PATH"
```

---

## 🔬 Tester Manuellement

### Vérifier ta Version OpenSSL

```bash
openssl version
# Exemple: OpenSSL 3.0.2 15 Mar 2022
```

### Tester Support CMS

```bash
openssl cms -help 2>&1 | grep encrypt
# Si des options s'affichent → CMS supporté ✅
# Si erreur → CMS non supporté ❌
```

### Tester Support AEAD

```bash
echo "test" | openssl enc -aes-256-gcm -out test.enc -pass pass:test123 2>&1
# Si réussite → AEAD supporté ✅
# Si "unknown option" → AEAD non supporté ❌
```

### Test Complet avec Encryptor

```bash
# Créer fichier test
echo "Test OpenSSL compatibility" > test.txt

# Lancer encryptor
encryptor

# Choisir [2] Encrypt
# Sélectionner test.txt
# Choisir [1] AES-256-GCM
# Entrer password

# Observer le message:
# - "Encrypting with modern AEAD cipher..." → Essai AEAD
# - "Note: ... using AES-256-CBC" → Fallback activé
# - Sinon → AEAD utilisé avec succès!
```

---

## 🎯 Algorithmes et Compatibilité

| Algorithme | OpenSSL 3.x | OpenSSL 1.1.x | OpenSSL 1.0.2 | Sécurité |
|------------|-------------|---------------|---------------|----------|
| **AES-256-GCM** | ✅ Natif | ✅ Via CMS | ⚠️ Fallback → CBC | Excellent |
| **ChaCha20-Poly1305** | ✅ Natif | ✅ Via CMS | ⚠️ Fallback → CBC | Excellent |
| **S/MIME (Certificat)** | ✅ Complet | ✅ Complet | ✅ Complet | Excellent |
| **AES-256-CBC** (fallback) | ✅ Disponible | ✅ Disponible | ✅ Natif | Très bon |

### Notes de Sécurité

- **AES-256-GCM**: AEAD (Authenticated Encryption), protection intégrité + confidentialité
- **ChaCha20-Poly1305**: AEAD moderne, résistant aux attaques par canal auxiliaire
- **AES-256-CBC**: Mode traditionnel mais toujours très sécurisé avec PBKDF2
- **Tous utilisent PBKDF2** avec 100,000 itérations pour dériver les clés

---

## 🚀 Mise à Niveau Recommandée

### Pourquoi Upgrade?

✅ **Avantages OpenSSL 3.x:**
- Algorithmes AEAD modernes (GCM, ChaCha20)
- Accélération matérielle (AES-NI)
- Performance améliorée
- Support long terme (LTS jusqu'en 2026)
- Dernières corrections de sécurité

⚠️ **Sans Upgrade:**
- Encryptor fonctionne toujours parfaitement
- Utilise AES-256-CBC (toujours sécurisé)
- Performance légèrement inférieure
- Pas d'accélération matérielle moderne

### Guide de Mise à Niveau

#### Ubuntu/Debian Modern (20.04+)
```bash
sudo apt update
sudo apt install --upgrade openssl libssl-dev
openssl version  # Vérifier
```

#### CentOS/RHEL 8+
```bash
sudo dnf update openssl openssl-libs
openssl version  # Vérifier
```

#### Arch Linux
```bash
sudo pacman -Syu openssl
openssl version  # Vérifier
```

#### macOS (Homebrew)
```bash
brew update
brew install openssl@3
brew link --force openssl@3

# Ajouter au PATH
echo 'export PATH="/usr/local/opt/openssl@3/bin:$PATH"' >> ~/.zshrc
source ~/.zshrc

openssl version  # Vérifier
```

#### Compilation depuis Source (Si nécessaire)
```bash
# Télécharger OpenSSL 3.0.12 (dernière stable)
wget https://www.openssl.org/source/openssl-3.0.12.tar.gz
tar -xzf openssl-3.0.12.tar.gz
cd openssl-3.0.12

# Configurer
./config --prefix=/usr/local/ssl --openssldir=/usr/local/ssl shared zlib

# Compiler (utilise tous les cores)
make -j$(nproc)

# Tester
make test

# Installer
sudo make install

# Mettre à jour les liens dynamiques
sudo ldconfig

# Vérifier
/usr/local/ssl/bin/openssl version

# Créer lien symbolique (optionnel)
sudo ln -sf /usr/local/ssl/bin/openssl /usr/bin/openssl
```

---

## 🔍 Debugging

### Problème: Encryptor utilise toujours CBC

**Diagnostic:**
```bash
# Vérifier version
openssl version

# Tester CMS
echo "test" | openssl cms -encrypt -aes256-gcm -out test.enc 2>&1

# Si erreur "unknown option" → CMS pas supporté
```

**Solution:**
Upgrade OpenSSL vers 1.1.1+ ou 3.x

### Problème: Après upgrade, toujours vieille version

**Diagnostic:**
```bash
# Vérifier quel OpenSSL est utilisé
which openssl

# Voir toutes les versions
find /usr -name "openssl" 2>/dev/null

# Vérifier la version
openssl version
```

**Solution:**
```bash
# Mettre à jour le PATH
export PATH="/usr/local/ssl/bin:$PATH"

# Ou créer alias
alias openssl="/usr/local/ssl/bin/openssl"

# Ou créer lien symbolique
sudo ln -sf /usr/local/ssl/bin/openssl /usr/bin/openssl
```

### Problème: Librairies partagées introuvables

**Erreur:**
```
openssl: error while loading shared libraries: libssl.so.3
```

**Solution:**
```bash
# Mettre à jour ldconfig
sudo ldconfig /usr/local/ssl/lib

# Ou ajouter aux libraries
echo "/usr/local/ssl/lib" | sudo tee /etc/ld.so.conf.d/openssl-3.conf
sudo ldconfig
```

---

## 📊 Tableau de Compatibilité Complet

| Distribution | Version par Défaut | Support Natif AEAD | Upgrade Recommandé |
|--------------|-------------------|---------------------|-------------------|
| Ubuntu 22.04+ | OpenSSL 3.0 | ✅ Complet | Non nécessaire |
| Ubuntu 20.04-21.10 | OpenSSL 1.1.1 | ✅ Via CMS | Optionnel |
| Ubuntu 18.04-19.10 | OpenSSL 1.1.0 | ⚠️ Partiel | Recommandé |
| Ubuntu 16.04 | OpenSSL 1.0.2 | ❌ Non | **Nécessaire** |
| Debian 12+ | OpenSSL 3.0 | ✅ Complet | Non nécessaire |
| Debian 11 | OpenSSL 1.1.1 | ✅ Via CMS | Optionnel |
| Debian 10 | OpenSSL 1.1.1 | ✅ Via CMS | Optionnel |
| Debian 9 | OpenSSL 1.0.2 | ❌ Non | **Nécessaire** |
| CentOS 8+ | OpenSSL 1.1.1 | ✅ Via CMS | Optionnel |
| CentOS 7 | OpenSSL 1.0.2 | ❌ Non | **Nécessaire** |
| Fedora 36+ | OpenSSL 3.0 | ✅ Complet | Non nécessaire |
| Fedora 26-35 | OpenSSL 1.1.x | ✅ Via CMS | Optionnel |
| Arch Linux | OpenSSL 3.x | ✅ Complet | Non nécessaire |
| macOS 13+ | Varie* | ⚠️ Voir Homebrew | Homebrew recommandé |

*macOS inclut LibreSSL par défaut, utiliser Homebrew pour OpenSSL moderne

---

## ✅ Résumé

### ✅ Ce qui Fonctionne TOUJOURS
- Encryption/Decryption de fichiers
- Gestion de certificats X.509
- S/MIME
- Export PKCS#12
- Toutes les fonctionnalités du Certificate Manager

### 🎯 Ce qui Change selon la Version
- **OpenSSL 3.x / 1.1.x**: Utilise AES-256-GCM et ChaCha20-Poly1305 (AEAD)
- **OpenSSL 1.0.2**: Utilise AES-256-CBC automatiquement (toujours sécurisé)

### 📝 Recommandation Finale
**Pour usage professionnel**: Upgrade vers OpenSSL 3.x  
**Pour usage personnel**: OpenSSL 1.1.1+ suffit  
**Si upgrade impossible**: Encryptor fonctionne quand même avec fallback CBC!

**👉 L'outil s'adapte automatiquement à ton système!**

