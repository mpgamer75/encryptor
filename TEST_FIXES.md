# Corrections Effectuées - v2.0.0

## Problème 1: Menu "Invalid choice"

### Diagnostic
Le problème venait de la fonction `prompt_input` qui utilisait `echo` pour retourner la valeur via command substitution. Cela pouvait causer des problèmes avec des espaces blancs ou caractères invisibles.

### Solution Appliquée
**Dans `main_menu()` (ligne 803-807):**
- Supprimé l'utilisation de `prompt_input()` 
- Utilisé directement `read -r choice` pour une lecture propre
- Ajouté nettoyage avec `tr -d '[:space:]'` pour supprimer tous les espaces blancs

**Avant:**
```bash
local choice
choice=$(prompt_input "Your choice: ")
```

**Après:**
```bash
echo -en "\n${MAGENTA}${BOLD}Your choice: ${RESET}"
read -r choice

# Trim whitespace and normalize input
choice=$(echo "$choice" | tr -d '[:space:]')
```

### Avantages
- ✅ Lecture directe de l'input sans intermédiaire
- ✅ Suppression de tous espaces blancs (début, fin, milieu)
- ✅ Plus robuste contre les caractères invisibles
- ✅ Code plus simple et direct

## Problème 2: ASCII Art

### Diagnostic
L'ASCII art n'était pas parfaitement centré dans l'affichage.

### Solution Appliquée
**Dans `print_header()` (lignes 82-83):**
- Ajusté l'espacement pour un meilleur centrage
- Modifié "Advanced Encryption Tool v$VERSION" (enlevé espaces inutiles)
- Modifié "Config: $CONFIG_DIR" (ajout espaces pour centrage)

**Avant:**
```bash
echo -e "${CYAN}${BOLD}                    Advanced Encryption Tool v$VERSION${RESET}"
echo -e "${DIM}                      Config: $CONFIG_DIR${RESET}"
```

**Après:**
```bash
echo -e "${CYAN}${BOLD}                   Advanced Encryption Tool v$VERSION${RESET}"
echo -e "${DIM}                        Config: $CONFIG_DIR${RESET}"
```

**Dans `install.sh` (ligne 32):**
- Même correction pour le script d'installation

## Test de Validation

### Syntaxe Bash
```bash
bash -n encryptor.sh
# Résultat: ✅ Aucune erreur
```

### Version
```bash
bash encryptor.sh --version
# Résultat: Encryptor v2.0.0 ✅
```

### Tests à Effectuer sur Linux

1. **Test du menu principal:**
   ```bash
   bash encryptor.sh
   # Taper: 1 (List Files)
   # Taper: 2 (Encrypt)
   # Taper: 3 (Decrypt)
   # Taper: h (Help)
   # Taper: q (Quit)
   ```

2. **Test avec espaces:**
   ```bash
   # Taper: " 1 " (avec espaces)
   # Devrait fonctionner maintenant ✅
   ```

3. **Test ASCII art:**
   - Vérifier que le header est bien centré
   - Vérifier que les lignes sont alignées

## Modifications dans `prompt_input()`

La fonction `prompt_input()` a été améliorée mais n'est plus utilisée dans le menu principal:

```bash
# Trim whitespace
input_var=$(echo "$input_var" | xargs)
```

Cette fonction reste utilisée ailleurs dans le code pour:
- Sélection de fichiers
- Saisie de chemins
- Noms de certificats
- etc.

## Fichiers Modifiés

1. **encryptor/encryptor.sh**
   - Ligne 100-114: Amélioration `prompt_input()`
   - Ligne 82-83: Centrage ASCII art
   - Ligne 803-807: Lecture directe du choix menu

2. **encryptor/install.sh**
   - Ligne 32: Centrage ASCII art

## Résumé

| Problème | Cause | Solution | Status |
|----------|-------|----------|--------|
| Menu "Invalid choice" | `prompt_input()` avec espaces | Lecture directe + `tr -d` | ✅ Corrigé |
| ASCII art décalé | Espacement incorrect | Ajustement espaces | ✅ Corrigé |

## Prochaines Étapes

1. Tester sur Linux/WSL
2. Vérifier que tous les menus fonctionnent
3. Si OK, procéder au build du .deb
4. Créer la release GitHub

---

**Date**: 2025-10-21  
**Version**: 2.0.0  
**Testeur**: À tester sur Linux


