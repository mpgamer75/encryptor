# 📦 Guide: Créer la Release v2.0.0 sur GitHub

## Étape 1: Préparer les Fichiers

### 1.1 Build le Package Debian
```bash
cd encryptor
chmod +x build_deb.sh
./build_deb.sh
```

Cela créera: `encryptor_2.0.0-1_all.deb`

### 1.2 Calculer les Checksums
```bash
# Dans le dossier encryptor
sha256sum encryptor_2.0.0-1_all.deb > checksums.txt
echo "" >> checksums.txt
echo "Source archives will be generated automatically by GitHub" >> checksums.txt
```

### 1.3 Tester le Package (Optionnel mais Recommandé)
```bash
# Sur une machine Linux
sudo dpkg -i encryptor_2.0.0-1_all.deb
encryptor --version
encryptor  # Tester rapidement
sudo dpkg -r encryptor  # Désinstaller après test
```

---

## Étape 2: Commit et Tag sur Git

### 2.1 Vérifier les Modifications
```bash
git status
git diff
```

### 2.2 Commit les Changements Finaux
```bash
git add .
git commit -m "Release v2.0.0 - Major release with modern algorithms and PKI management"
```

### 2.3 Créer le Tag
```bash
git tag -a v2.0.0 -m "Encryptor v2.0.0 - Professional file encryption tool"
```

### 2.4 Push vers GitHub
```bash
git push origin main
git push origin v2.0.0
```

---

## Étape 3: Créer la Release sur GitHub

### 3.1 Aller sur GitHub
1. Ouvre ton navigateur: https://github.com/mpgamer75/encryptor
2. Clique sur **"Releases"** (dans la sidebar droite)
3. Clique sur **"Draft a new release"**

### 3.2 Configurer la Release

**Tag version:**
- Sélectionne `v2.0.0` (le tag que tu viens de push)

**Release title:**
```
🔐 Encryptor v2.0.0 - Professional File Encryption
```

**Description:**
- Copie le contenu de `RELEASE_SHORT.md` (pour une description concise)
- OU copie `RELEASE_v2.0.0.md` (pour une description complète)

**Conseil:** Utilise RELEASE_SHORT.md pour GitHub, garde RELEASE_v2.0.0.md dans le repo pour référence

### 3.3 Uploader les Assets

Clique sur **"Attach binaries by dropping them here or selecting them"**

Uploads ces fichiers:
1. `encryptor_2.0.0-1_all.deb`
2. `checksums.txt`
3. `install.sh` (optionnel, déjà dans le repo)

### 3.4 Configurer les Options

- ✅ **Set as the latest release** (coché)
- ⬜ **Set as a pre-release** (décoché)
- ✅ **Create a discussion for this release** (optionnel, recommandé)

### 3.5 Publier
Clique sur **"Publish release"**

---

## Étape 4: Mettre à Jour les Checksums (Après Publication)

### 4.1 GitHub Génère Automatiquement
Après publication, GitHub crée automatiquement:
- `Source code (zip)`
- `Source code (tar.gz)`

### 4.2 Télécharger et Calculer
```bash
# Télécharge les archives générées par GitHub
wget https://github.com/mpgamer75/encryptor/archive/refs/tags/v2.0.0.tar.gz
wget https://github.com/mpgamer75/encryptor/archive/refs/tags/v2.0.0.zip

# Calcule les checksums
sha256sum v2.0.0.tar.gz v2.0.0.zip encryptor_2.0.0-1_all.deb
```

### 4.3 Mettre à Jour la Release
1. Va sur la page de la release
2. Clique **"Edit release"**
3. Ajoute les checksums dans la description:

```
### Checksums (SHA-256)
```
[checksum_deb]  encryptor_2.0.0-1_all.deb
[checksum_tar]  v2.0.0.tar.gz
[checksum_zip]  v2.0.0.zip
```

Verify: `sha256sum -c checksums.txt`
```

4. Sauvegarde

---

## Étape 5: Vérifications Post-Release

### 5.1 Tester l'Installation One-Line
```bash
# Sur une machine fraîche ou VM
curl -fsSL https://raw.githubusercontent.com/mpgamer75/encryptor/main/install.sh | bash
encryptor --version
```

### 5.2 Vérifier les Liens
- ✅ Badge version dans README.md pointe vers v2.0.0
- ✅ Lien de download dans README fonctionne
- ✅ Assets de la release sont accessibles

### 5.3 Tester le Download du .deb
```bash
wget https://github.com/mpgamer75/encryptor/releases/download/v2.0.0/encryptor_2.0.0-1_all.deb
sha256sum encryptor_2.0.0-1_all.deb  # Comparer avec checksums.txt
```

---

## Étape 6: Annonces (Optionnel)

### 6.1 LinkedIn
- Publie le message préparé dans `LINKEDIN_POST.md`
- Ajoute des screenshots de l'interface
- Lien vers la release GitHub

### 6.2 Reddit (si applicable)
- r/opensource
- r/bash
- r/linux
- r/commandline

### 6.3 Twitter/X
```
🔐 Encryptor v2.0.0 is out!

✨ Modern encryption (AES-256, ChaCha20, Camellia, ARIA)
🔑 Complete PKI/X.509 management
🛡️ Enhanced security & UX

Get it: https://github.com/mpgamer75/encryptor

#OpenSource #Encryption #Linux #Bash #Cybersecurity
```

---

## 📋 Checklist Complète

### Avant la Release
- [ ] Tous les fichiers commitués et pushés
- [ ] Package Debian buildé (`encryptor_2.0.0-1_all.deb`)
- [ ] Checksums calculés
- [ ] Package testé localement
- [ ] Tag créé et pushé (`v2.0.0`)
- [ ] README.md à jour avec version correcte

### Pendant la Release
- [ ] Release créée sur GitHub
- [ ] Tag `v2.0.0` sélectionné
- [ ] Description ajoutée (RELEASE_SHORT.md)
- [ ] Assets uploadés (.deb, checksums.txt)
- [ ] "Latest release" coché
- [ ] Release publiée

### Après la Release
- [ ] Checksums des archives GitHub calculés
- [ ] Checksums ajoutés à la description
- [ ] Installation one-line testée
- [ ] Tous les liens vérifiés
- [ ] Annonces publiées (LinkedIn, etc.)

---

## 🆘 En Cas de Problème

### Si tu dois corriger quelque chose après publication:

1. **Petites corrections (typos dans description)**:
   - Clique "Edit release" et modifie directement

2. **Corrections de code**:
   ```bash
   # Fix le code
   git add .
   git commit -m "Fix: [description]"
   git push
   
   # Supprime le tag local et remote
   git tag -d v2.0.0
   git push origin :refs/tags/v2.0.0
   
   # Recrée le tag
   git tag -a v2.0.0 -m "Encryptor v2.0.0"
   git push origin v2.0.0
   
   # Supprime la release sur GitHub et recrée-la
   ```

3. **Gros problèmes**:
   - Marque la release comme "pre-release"
   - Crée une v2.0.1 avec le fix

---

## 📝 Notes

- Les archives `.tar.gz` et `.zip` sont générées automatiquement par GitHub à partir du tag
- Le fichier `.deb` doit être uploadé manuellement
- Les checksums doivent être recalculés après que GitHub génère les archives
- La description de la release supporte le Markdown
- Tu peux éditer la release après publication sans problème

---

**Bonne release! 🚀**

