# 🔐 Encryptor v2.0.0 - Professional File Encryption Tool

## LinkedIn Post (Version Française)

---

**🚀 Nouveau Projet Open Source : Encryptor v2.0.0**

Après plusieurs mois de développement, je suis fier de présenter **Encryptor**, un outil professionnel de chiffrement de fichiers en ligne de commande que j'ai développé depuis début août 2024 en parallèle de mon projet **Security Scanner**.

### 🎯 Qu'est-ce qu'Encryptor ?

Encryptor est une solution complète de chiffrement conçue pour protéger vos fichiers sensibles avec les algorithmes cryptographiques les plus modernes. Développé en Bash pur et s'appuyant sur OpenSSL 3.x, il offre une interface interactive intuitive et colorée pour une expérience utilisateur optimale.

### 💡 MES MOTIVATIONS
• Approfondir mes connaissances en cryptographie moderne et gestion PKI
• Développer mes compétences en scripting Bash avancé et automatisation
• Maîtriser les aspects pratiques de la sécurité des données et du chiffrement
• Créer un outil utilisable en production pour la communauté open source
• Compléter mes compétences offensives (Security Scanner) par des compétences défensives

### ✨ Fonctionnalités Principales

**Chiffrement Multi-Algorithmes**
- AES-256 (CBC/CTR) - Standard industriel approuvé NSA
- ChaCha20 - Chiffrement moderne ultra-rapide
- Camellia-256 - Standard japonais (NTT)
- ARIA-256 - Standard coréen (NSRI)
- S/MIME - Chiffrement asymétrique par certificats

**Gestion Complète de Certificats X.509**
- Création de Certificats Autorité (CA)
- Génération de clés privées et CSR
- Signature de certificats
- Export PKCS#12 (Windows, navigateurs, clients email)
- Validation des paires certificat/clé
- Vérification d'expiration

**Sécurité Renforcée**
- PBKDF2 avec 100,000 itérations pour dérivation de clés
- Suppression sécurisée des fichiers (3 passes avec shred)
- Audit de sécurité système intégré
- Intégration testssl.sh pour analyse SSL/TLS
- Gestion automatique des permissions (400/600)
- Logging complet des opérations

**Expérience Utilisateur**
- Interface interactive avec menus colorés
- Navigateur de fichiers intégré
- Rapports détaillés après chaque opération
- Instructions de déchiffrement contextuelles
- Gestion d'erreur robuste avec conseils de dépannage
- Support multi-plateforme (Linux, macOS, WSL)

### 💡 Cas d'Usage

- **Entreprises** : Sécurisation de documents confidentiels
- **Développeurs** : Protection de secrets et credentials
- **Administrateurs Système** : Gestion PKI et certificats
- **Utilisateurs** : Chiffrement de fichiers personnels sensibles
- **DevOps** : Intégration dans pipelines CI/CD pour secrets management

### 🛠️ Installation en Une Ligne

```bash
curl -fsSL https://raw.githubusercontent.com/mpgamer75/encryptor/main/install.sh | bash
```

L'installateur détecte automatiquement votre OS, vérifie les dépendances (OpenSSL, Bash, Git), configure le PATH, et vérifie la compatibilité avec les algorithmes modernes.

### 🤝 Contributions Bienvenues

Encryptor est un projet **open source** sous licence MIT. Vos contributions sont les bienvenues !

**Comment contribuer ?**
- 🐛 Signaler des bugs ou problèmes de sécurité
- 💡 Proposer de nouvelles fonctionnalités
- 📖 Améliorer la documentation
- 🌐 Ajouter des traductions
- 🧪 Soumettre des tests et cas d'usage
- ⭐ Mettre une étoile sur le projet si vous le trouvez utile

**Guidelines de Contribution**
- Fork le dépôt et créez une branche pour vos modifications
- Suivez les conventions de code existantes (Bash best practices)
- Ajoutez des tests si applicable
- Documentez les nouvelles fonctionnalités
- Soumettez une Pull Request détaillée

### 🔮 Prochaines Étapes & Roadmap

**Version 2.1.0 - Court Terme**
- 🔄 Support du chiffrement par lots (batch encryption)
- 📦 Compression automatique avant chiffrement (gzip/bzip2)
- 🔑 Génération de mots de passe sécurisés intégrée
- 📊 Statistiques d'utilisation et tableaux de bord
- 🌍 Interface multilingue (français, espagnol, allemand)

**Version 2.5.0 - Moyen Terme**
- 🛡️ Support des algorithmes post-quantiques (CRYSTALS-Kyber, CRYSTALS-Dilithium)
- 🔐 Intégration avec gestionnaires de mots de passe (KeePass, 1Password)
- 📱 Application mobile compagnon (Android/iOS)
- ☁️ Intégration cloud storage (chiffrement avant upload)
- 🔔 Notifications pour expiration de certificats

**Version 3.0.0 - Long Terme**
- 🖥️ Interface graphique (GUI) avec Electron ou Tauri
- 🔗 API REST pour intégration dans applications tierces
- 👥 Gestion multi-utilisateurs avec rôles et permissions
- 📝 Signature numérique de fichiers
- 🔍 Détection automatique de fichiers sensibles (ML-based)
- 🏢 Mode entreprise avec HSM (Hardware Security Module) support

**Améliorations Continues**
- 🧪 Suite de tests automatisés complète (unit, intégration, end-to-end)
- 📦 Packages pour plus de distributions (Fedora, Arch, Alpine)
- 🐳 Image Docker officielle
- 📚 Documentation interactive et tutoriels vidéo
- 🔒 Audits de sécurité réguliers par des tiers

### 🔗 Liens

- 📂 **Repository** : github.com/mpgamer75/encryptor
- 📖 **Documentation** : README complet avec guides détaillés
- 🐛 **Issues** : Signaler un problème ou suggérer une fonctionnalité
- 💬 **Discussions** : Rejoignez la communauté

### 🏆 Technologies Utilisées

`Bash` `OpenSSL 3.x` `X.509 PKI` `AES-256` `ChaCha20` `S/MIME` `PBKDF2` `testssl.sh` `Git` `Debian Packaging`

---

**Votre feedback est précieux ! N'hésitez pas à tester l'outil, partager vos retours, et contribuer au projet.**

#Cybersecurity #OpenSource #Encryption #DevSecOps #InfoSec #DataProtection #CLI #Linux #Bash #PKI #CyberSécurité #DéveloppementLogiciel #OpenSourceProject

---

## LinkedIn Post (English Version)

**🚀 New Open Source Project: Encryptor v2.0.0**

After several months of development, I'm proud to present **Encryptor**, a professional command-line file encryption tool that I've been developing since early August 2024 alongside my **Security Scanner** project.

### 🎯 What is Encryptor?

Encryptor is a comprehensive encryption solution designed to protect your sensitive files using the most modern cryptographic algorithms. Built with pure Bash and leveraging OpenSSL 3.x, it offers an intuitive, color-coded interactive interface for an optimal user experience.

### 💡 MY MOTIVATIONS
• Deepen my knowledge of modern cryptography and PKI management
• Develop my skills in advanced Bash scripting and automation
• Master practical aspects of data security and encryption
• Create a production-ready tool for the open source community
• Complement my offensive skills (Security Scanner) with defensive capabilities

### ✨ Key Features

**Multi-Algorithm Encryption**
- AES-256 (CBC/CTR) - NSA-approved industry standard
- ChaCha20 - Modern ultra-fast encryption
- Camellia-256 - Japanese standard (NTT)
- ARIA-256 - Korean standard (NSRI)
- S/MIME - Certificate-based asymmetric encryption

**Complete X.509 Certificate Management**
- Certificate Authority (CA) creation
- Private key and CSR generation
- Certificate signing
- PKCS#12 export (Windows, browsers, email clients)
- Certificate/key pair validation
- Expiration monitoring

**Enhanced Security**
- PBKDF2 with 100,000 iterations for key derivation
- Secure file deletion (3-pass shred)
- Integrated system security audit
- testssl.sh integration for SSL/TLS analysis
- Automatic permission management (400/600)
- Comprehensive operation logging

**User Experience**
- Interactive interface with color-coded menus
- Built-in file browser
- Detailed reports after each operation
- Contextual decryption instructions
- Robust error handling with troubleshooting tips
- Multi-platform support (Linux, macOS, WSL)

### 💡 Use Cases

- **Enterprises**: Securing confidential documents
- **Developers**: Protecting secrets and credentials
- **System Administrators**: PKI and certificate management
- **End Users**: Encrypting sensitive personal files
- **DevOps**: CI/CD pipeline integration for secrets management

### 🛠️ One-Line Installation

```bash
curl -fsSL https://raw.githubusercontent.com/mpgamer75/encryptor/main/install.sh | bash
```

The installer automatically detects your OS, checks dependencies (OpenSSL, Bash, Git), configures PATH, and verifies compatibility with modern algorithms.

### 🤝 Contributions Welcome

Encryptor is an **open source** project under MIT license. Your contributions are welcome!

**How to Contribute?**
- 🐛 Report bugs or security issues
- 💡 Propose new features
- 📖 Improve documentation
- 🌐 Add translations
- 🧪 Submit tests and use cases
- ⭐ Star the project if you find it useful

**Contribution Guidelines**
- Fork the repository and create a branch for your changes
- Follow existing code conventions (Bash best practices)
- Add tests where applicable
- Document new features
- Submit a detailed Pull Request

### 🔮 Next Steps & Roadmap

**Version 2.1.0 - Short Term**
- 🔄 Batch encryption support
- 📦 Automatic compression before encryption (gzip/bzip2)
- 🔑 Built-in secure password generator
- 📊 Usage statistics and dashboards
- 🌍 Multilingual interface (French, Spanish, German)

**Version 2.5.0 - Medium Term**
- 🛡️ Post-quantum algorithm support (CRYSTALS-Kyber, CRYSTALS-Dilithium)
- 🔐 Password manager integration (KeePass, 1Password)
- 📱 Mobile companion app (Android/iOS)
- ☁️ Cloud storage integration (encrypt before upload)
- 🔔 Certificate expiration notifications

**Version 3.0.0 - Long Term**
- 🖥️ Graphical interface (GUI) with Electron or Tauri
- 🔗 REST API for third-party integration
- 👥 Multi-user management with roles and permissions
- 📝 Digital file signing
- 🔍 Automatic sensitive file detection (ML-based)
- 🏢 Enterprise mode with HSM (Hardware Security Module) support

**Continuous Improvements**
- 🧪 Complete automated test suite (unit, integration, e2e)
- 📦 Packages for more distributions (Fedora, Arch, Alpine)
- 🐳 Official Docker image
- 📚 Interactive documentation and video tutorials
- 🔒 Regular third-party security audits

### 🔗 Links

- 📂 **Repository**: github.com/mpgamer75/encryptor
- 📖 **Documentation**: Complete README with detailed guides
- 🐛 **Issues**: Report a problem or suggest a feature
- 💬 **Discussions**: Join the community

### 🏆 Technologies Used

`Bash` `OpenSSL 3.x` `X.509 PKI` `AES-256` `ChaCha20` `S/MIME` `PBKDF2` `testssl.sh` `Git` `Debian Packaging`

---

**Your feedback is valuable! Feel free to test the tool, share your thoughts, and contribute to the project.**

#Cybersecurity #OpenSource #Encryption #DevSecOps #InfoSec #DataProtection #CLI #Linux #Bash #PKI #SoftwareDevelopment #OpenSourceProject

---

## Notes pour le Post

### Conseils de Publication
1. **Timing**: Publier en semaine (mardi-jeudi) entre 8h-10h ou 17h-19h
2. **Images**: Ajouter des captures d'écran de l'interface colorée
3. **Vidéo**: Courte démo (30-60s) montrant l'installation et une encryption
4. **Engagement**: Répondre aux commentaires dans les 24h premières heures
5. **Cross-post**: Partager aussi sur Reddit (r/opensource, r/bash, r/linux)

### Hashtags Recommandés
- **Primaires** (10): #Cybersecurity #OpenSource #Encryption #InfoSec #CLI #Linux #Bash #DataProtection #DevSecOps #PKI
- **Secondaires** (5): #SoftwareDevelopment #CyberSécurité #OpenSourceProject #Security #Programming

### Call-to-Action
- "⭐ Star le projet si vous le trouvez utile"
- "🔗 Lien vers le repo en commentaire"
- "💭 Partagez vos cas d'usage en commentaire"
- "🤝 Les contributions sont bienvenues"

