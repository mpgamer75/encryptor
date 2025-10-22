# 🧪 GUIDE DE TEST RAPIDE

## 🎯 Test Prioritaire: Encryption/Decryption

### Test 1: Créer un fichier de test
```bash
cd ~/Desktop/encryption-tool/encryptor
echo "Secret data test 123" > test.txt
```

### Test 2: Lancer l'outil
```bash
bash encryptor.sh
```

### Test 3: Encryption (Option 2)
```
1. Choisis [2] Encrypt a File
2. Tu DEVRAIS MAINTENANT VOIR:
   :: File Selector ::
   [1] test.txt
   [2] encryptor.sh
   ... etc
3. Tape "1" pour sélectionner test.txt
4. Tu DEVRAIS VOIR:
   :: Select Encryption Algorithm ::
   [1] AES-256-GCM
   [2] ChaCha20-Poly1305
   [3] S/MIME
5. Tape "1" pour AES-256-GCM
6. Entre password: "test123"
7. Confirme: "test123"
8. Tu DEVRAIS VOIR:
   - "Encrypting with modern AEAD cipher..."
   - OU "Note: AEAD cipher not available, using AES-256-CBC"
   - ":: Encryption Report ::"
   - "—— OPERATION SUCCESSFUL ——"
   - File created: test.txt.enc
```

### Test 4: Decryption (Option 3)
```
1. Choisis [3] Decrypt a File
2. Sélectionne test.txt.enc
3. Choisis [1] AES-256-GCM (même algorithme)
4. Entre password: "test123"
5. Tu DEVRAIS VOIR:
   - "Decrypting with modern AEAD cipher..."
   - ":: Decryption Report ::"
   - "—— OPERATION SUCCESSFUL ——"
   - File created: test.txt.dec
```

### Test 5: Vérifier le contenu
```bash
cat test.txt.dec
# DEVRAIT AFFICHER: "Secret data test 123"
```

---

## ✅ SI TOUT FONCTIONNE

Tu devrais voir:
1. ✅ Les menus s'affichent (pas de curseur vide)
2. ✅ L'encryption crée un fichier .enc
3. ✅ Le decryption recrée le fichier original
4. ✅ Pas d'erreur "AEAD ciphers not supported" (ou fallback automatique)

---

## 🎨 Test des Couleurs

Lance l'outil et vérifie:
- **Cyan**: Titres de section
- **Yellow**: Options numérotées
- **Magenta**: Prompts d'input
- **Green**: Succès
- **Red**: Erreurs
- **Orange**: Avertissements (nouveau!)
- **Purple**: Options spéciales 6,7,8 (nouveau!)
- **Lime**: Succès éclatants (nouveau!)
- **Pink**: Warnings de sécurité (nouveau!)

---

## 🔐 Test Certificate Manager

### Test rapide CA professionnel
```
1. Choisis [4] Certificate Manager
2. Choisis [1] Create Root CA
3. Entre un nom: "TestCompanyCA"
4. Tu DEVRAIS VOIR des prompts pour:
   - Organization Name
   - Department
   - Country
   - State
   - City
   - Email
5. Remplis avec tes infos ou appuie sur Enter pour les défauts
6. Tu DEVRAIS VOIR:
   - "Certificate Preview" avant création
   - Détails complets après création
   - Fingerprint SHA-256
   - Next steps
```

### Test Export PKCS#12
```
1. Dans Certificate Manager, choisis [6]
2. Tu DEVRAIS VOIR liste des certificats
3. Sélectionne TestCompanyCA.pem
4. Sélectionne TestCompanyCA.key
5. Entre un password pour le .p12
6. Tu DEVRAIS VOIR:
   - "✓ PKCS#12 export successful!"
   - Fichier .p12 créé
   - Instructions Windows/Browser
```

### Test Validation
```
1. Choisis [7] Validate Certificate/Key Pair
2. Sélectionne TestCompanyCA.pem
3. Sélectionne TestCompanyCA.key
4. Tu DEVRAIS VOIR:
   - "✓ Certificate and key MATCH!"
   - Modulus MD5 affiché
```

### Test Expiration
```
1. Choisis [8] Check Certificate Expiration
2. Sélectionne TestCompanyCA.pem
3. Tu DEVRAIS VOIR:
   - Certificate Information complète
   - "✓ Certificate is VALID"
   - "Days remaining: ~3650 days"
```

---

## 🚨 SI QUELQUE CHOSE NE MARCHE PAS

### Erreur: "AEAD ciphers not supported" persiste
```bash
# Vérifie ta version d'OpenSSL
openssl version

# Si < 1.1.0, le fallback vers CBC devrait s'activer automatiquement
# Cherche le message orange: "Note: AEAD cipher not available, using AES-256-CBC"
```

### Erreur: "Command not found"
```bash
# Vérifie que bash est disponible
which bash

# Lance avec le chemin complet
/usr/bin/bash encryptor.sh
```

### Les couleurs ne s'affichent pas
```bash
# Normal sur certains terminaux
# Les fonctionnalités marchent quand même!
```

### Fichier .enc créé mais decryption échoue
```bash
# Vérifie que tu utilises le MÊME algorithme et password
# Si tu as choisi AES-256-GCM pour encrypt, choisis AES-256-GCM pour decrypt
```

---

## ✅ CHECKLIST COMPLÈTE

- [ ] Test encryption réussi
- [ ] Test decryption réussi
- [ ] Fichier décrypté = fichier original
- [ ] Menus s'affichent correctement
- [ ] Couleurs visibles (optionnel)
- [ ] CA avec champs personnalisés créé
- [ ] Export PKCS#12 fonctionne
- [ ] Validation cert/clé fonctionne
- [ ] Vérification expiration fonctionne

## 🎉 SI TOUT EST ✅

**TON OUTIL EST PRÊT POUR LA PRODUCTION!**

Tu peux maintenant:
1. Créer le package Debian: `bash build_deb.sh`
2. Faire le release GitHub v2.0.0
3. Partager avec la communauté!

---

## 📸 Screenshots Utiles

Prends des screenshots de:
1. Menu principal avec nouvelles couleurs
2. File selector (pour montrer qu'il s'affiche)
3. Encryption report (succès)
4. Certificate Manager avec options 6,7,8
5. Création CA avec champs personnalisés
6. Export PKCS#12 réussi

Ces screenshots seront parfaits pour ton README et la page GitHub release!

