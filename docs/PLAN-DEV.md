# Plan de développement — Client Telegram accessible VoiceOver (iPhone)

> Dernière mise à jour : 2026-11-08
> Objectifs : connexion par numéro de téléphone, accessibilité lecteur d'écran prioritaire, sécurité des communications.
> Contraintes : dépôt Git **privé** sur GitHub, développement sous Windows, **compilation / signature / upload via GitHub Actions macOS**.

---

## Décisions structurantes

| Sujet | Choix | Raison |
|---|---|---|
| Langage / UI | **Swift + SwiftUI**, UIKit pour l'écran de conversation | Meilleur support VoiceOver natif |
| Accès Telegram | **TDLib** via [TDLibKit](https://github.com/Swiftgram/TDLibKit) (SPM) | MTProto, chiffrement, synchro, base locale chiffrée gérés officiellement |
| Architecture | MVVM, `actor TelegramClient`, async/await, `AsyncStream` des updates | Isolation, testabilité |
| Projet Xcode | **XcodeGen** (`project.yml`), `.xcodeproj` non versionné | Éditable sous Windows |
| CI/CD | **GitHub Actions macOS** + **fastlane** (match, gym, pilot) | Pas de Mac local nécessaire |
| Dépendances | Minimum, aucun SDK analytics/tracking tiers | Confidentialité |

Telegram : obtenir `api_id` / `api_hash` sur https://my.telegram.org, respecter les [API Terms](https://core.telegram.org/api/terms) (client non officiel clairement indiqué, pas de logo officiel, nom non trompeur). Tester avec un compte secondaire (risque de restriction des nouveaux `api_id`).

---

## Phase 0 — Dépôt, CI/CD et signature (1 à 1,5 semaine)

### 0.1 Prérequis
- Compte GitHub, dépôt **privé**.
- **Apple Developer Program** (99 $/an) — obligatoire pour signer et TestFlight.
- App Store Connect : fiche de l'app + bundle id (ex. `com.nael.telegramaccess`).
- **Clé API App Store Connect** (rôle App Manager) → upload sans Apple ID ni 2FA.
- `api_id` / `api_hash` Telegram → uniquement dans les secrets GitHub.

### 0.2 Dépôt privé
```bash
gh repo create telegram-access --private --source . --remote origin
```
- Protection de `main` : PR obligatoire + CI verte.
- Dependabot (Swift packages + GitHub Actions), secret scanning + push protection.
- `.gitignore` : `*.xcodeproj`, `build/`, `*.p12`, `*.mobileprovision`, `Config/Secrets.xcconfig`.
- Secrets injectés à la compilation via un `.xcconfig` généré par la CI.

### 0.3 Signature sans Mac : fastlane match
- Certificats + profils stockés **chiffrés** dans un **second dépôt privé** (`telegram-access-certs`).
- Génération initiale via un workflow manuel `certs-init.yml` (`match appstore`) avec la clé API ASC.
- Builds suivants en `readonly: true`.

### 0.4 Secrets GitHub (environment `release`, approbation manuelle optionnelle)
| Secret | Usage |
|---|---|
| `APPLE_TEAM_ID` | Identifiant d'équipe Apple Developer (signature) |
| `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8` (base64) | Clé API App Store Connect |
| `MATCH_PASSWORD` | Déchiffrement du dépôt de certificats |
| `MATCH_GIT_BASIC_AUTHORIZATION` | Jeton lecture du dépôt certificats |
| `TG_API_ID`, `TG_API_HASH` | API Telegram |

Les builds de PR n'ont pas accès aux secrets de signature.

### 0.5 Workflows
**`ci.yml`** (push + PR) : `xcodegen generate` → build simulateur sans signature → tests unitaires + UI (dont `performAccessibilityAudit()`) → cache SPM / TDLib.

**`release.yml`** (tag `v*` ou manuel) : `match` → `gym` (build number = `github.run_number`) → **`upload_to_testflight`** → artefacts IPA + dSYM (rétention courte).

```yaml
name: Release TestFlight
on:
  push:
    tags: ['v*']
  workflow_dispatch:

permissions:
  contents: read

jobs:
  testflight:
    runs-on: macos-26          # Xcode 26.6 : SDK iOS 26 exigé pour l'envoi App Store
    environment: release
    timeout-minutes: 60
    steps:
      - uses: actions/checkout@<sha>   # épingler les actions par SHA
      - run: sudo xcode-select -s /Applications/Xcode_26.6.app
      - run: brew install xcodegen && xcodegen generate
      - name: Secrets.xcconfig
        run: |
          echo "TG_API_ID=${{ secrets.TG_API_ID }}"    >  Config/Secrets.xcconfig
          echo "TG_API_HASH=${{ secrets.TG_API_HASH }}" >> Config/Secrets.xcconfig
      - run: bundle install && bundle exec fastlane beta
        env:
          ASC_KEY_ID: ${{ secrets.ASC_KEY_ID }}
          ASC_ISSUER_ID: ${{ secrets.ASC_ISSUER_ID }}
          ASC_KEY_P8: ${{ secrets.ASC_KEY_P8 }}
          MATCH_PASSWORD: ${{ secrets.MATCH_PASSWORD }}
          MATCH_GIT_BASIC_AUTHORIZATION: ${{ secrets.MATCH_GIT_BASIC_AUTHORIZATION }}
```
Lane `beta` : `setup_ci` → `app_store_connect_api_key` → `match(readonly: true)` → `increment_build_number` → `gym` → `upload_to_testflight`.

### 0.6 Coût en minutes
- Dépôt privé : **1 min macOS = 10 min décomptées** → forfait gratuit ≈ 200 min macOS/mois (10–15 builds).
- Économies : cache, tests UI seulement sur PR vers `main`, `paths-ignore` pour la doc, `concurrency: cancel-in-progress`.
- Si insuffisant : forfait payant ou runner macOS auto-hébergé.

### 0.7 Limites
- VoiceOver **ne se teste pas en CI** : les audits détectent libellés manquants, contraste, tailles de cibles, pas l'ergonomie.
- Boucle : push → TestFlight (15–30 min) → test VoiceOver sur iPhone.
- Tests unitaires des générateurs de libellés (message → chaîne attendue) pour accélérer le feedback.

---

## Phase 1 — Socle et authentification par téléphone (2 à 3 semaines)

1. Projet iOS 17+, TDLibKit, `actor TelegramClient` exposant les updates en `AsyncStream`.
2. Machine à états TDLib :
   - `WaitTdlibParameters` → `setTdlibParameters` (clé de chiffrement de la base, cf. phase 4)
   - `WaitPhoneNumber` → champ téléphone + sélecteur de pays
   - `WaitCode` → code (app Telegram / SMS / appel)
   - `WaitEmailAddress` / `WaitEmailCode` (parfois imposé)
   - `WaitPassword` → 2FA avec indice
   - `WaitRegistration` → prénom / nom
   - `Ready`
3. Accessibilité des écrans :
   - Pays avec recherche, annoncé « France, plus 33 ».
   - `textContentType = .telephoneNumber` et `.oneTimeCode`.
   - Erreurs annoncées (`AccessibilityNotification.Announcement`) + focus sur le champ fautif.
   - Délai de renvoi annoncé une fois en texte, pas de décompte bavard.
   - Bouton « Recevoir le code par SMS / appel » toujours atteignable.
4. Déconnexion / logout.

## Phase 2 — Liste des conversations (2 semaines)

- Liste paginée (`loadChats`), mise à jour en temps réel.
- Chaque ligne = **un seul élément VoiceOver** : « Marie Dupont, 3 non lus, dernier message : On se voit demain ?, 14 h 32 ». Infos secondaires (épinglé, muet, brouillon) en `accessibilityCustomContent`.
- **Actions personnalisées** : marquer lu, épingler, muet, archiver, supprimer.
- **Rotor personnalisé** : Non lus, Mentions, Épinglées.
- Filtres (Tous, Non lus, Personnes, Groupes, Canaux) en onglets correctement annoncés.
- Recherche globale.

## Phase 3 — Conversation (4 à 5 semaines, cœur de l'app)

**Rendu**
- `UICollectionView` (stabilité du focus lors du chargement de l'historique).
- Libellé : « [Auteur | Vous], [contenu], [heure], [envoyé / lu / modifié] » ; auteur omis en tête-à-tête.
- Réponses : « En réponse à Paul : … ».
- Médias : « Photo », « Vidéo, 1 minute 20 », « Message vocal, 12 secondes », « Fichier PDF, 2 Mo » ; stickers → émoji associé.
- **Description d'image sur l'appareil** (Vision : OCR + classification), rien n'est envoyé à un tiers.

**Interactions**
- Actions personnalisées : répondre, réagir, copier, transférer, modifier, supprimer, épingler, ouvrir le lien.
- Rotor : Messages non lus, Liens, Mentions, Médias.
- **Magic Tap** : lecture/pause du vocal en cours ou envoi.
- **Geste Escape** (Z à deux doigts) : retour.
- Bouton « Aller au premier message non lu ».

**Messages entrants**
- Annonce réglable (toujours / conversation ouverte / jamais), en file d'attente sans interrompre.
- Le focus ne saute **jamais** automatiquement.

**Rédaction**
- Champ multiligne, bouton Envoyer à position fixe, confirmation « Message envoyé ».
- Vocal : bouton bascule (pas d'appui maintenu), retours haptiques/sonores, réécoute avant envoi.
- Lecteur : vitesse réglable, `accessibilityAdjustableAction` ±5 s.

## Phase 4 — Sécurité (1 semaine dédiée + en continu)

**Transparence sur le chiffrement**
- Conversations normales : chiffrées client ↔ serveur Telegram, **pas de bout en bout**.
- **Conversations secrètes** (E2E, MTProto 2.0) : création mise en avant, **vérification de clé accessible** (empreinte lue en émojis / caractères), messages éphémères.

**Données sur l'appareil**
- Clé de base TDLib aléatoire (32 octets) dans le **Keychain**, `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`.
- Dossier TDLib en `FileProtectionType.completeUnlessOpen` + `isExcludedFromBackup`. (`complete` écarté : la base SQLite ouverte par TDLib deviendrait inaccessible au verrouillage, avec risque de corruption ; la base est déjà chiffrée par TDLib.)
- Clé absente du trousseau (nouvel appareil, trousseau effacé) : le dossier TDLib est vidé avant initialisation, la session est perdue (reconnexion).
- Verrouillage optionnel Face ID / Touch ID / code (`LocalAuthentication`).
- Écran de confidentialité dans le sélecteur d'apps.
- Aucun log contenant messages ou numéros, même en debug.
- Écran **Appareils connectés** (`getActiveSessions` / `terminateSession`).
- Incitation à activer la 2FA.
- `api_hash` : obfuscation légère (extraction inévitable, non critique).
- Secrets de build uniquement via GitHub Secrets (cf. phase 0).

**Push chiffrées (phase 6)** : `registerDevice` + Notification Service Extension avec base partagée en App Group.

## Phase 5 — Accessibilité transversale et réglages (2 semaines)

- **Dynamic Type** jusqu'à AX5, mises en page adaptatives sans troncature.
- Respect de : contraste élevé, réduction des animations / transparence, formes des boutons, Contrôle de sélection.
- Réglages : verbosité (heure, statut), sons distincts envoi / réception / erreur, ordre de lecture.
- Écran d'aide listant gestes et rotors.
- Voice Control : libellés courts et uniques.

## Phase 6 — Fonctions complémentaires (3 à 4 semaines)

Push chiffrées, groupes et canaux (admin de base), recherche dans une conversation, envoi de fichiers / photos avec légende, contacts, profil, confidentialité Telegram, réactions.

## Phase 7 — Tests et publication (1,5 à 2 semaines)

- Tests unitaires (machine à états, générateurs de libellés) et UI avec `performAccessibilityAudit()` en CI.
- Serveur de test Telegram (`use_test_dc = true`).
- Tests manuels VoiceOver avec rideau d'écran ; Accessibility Inspector.
- **Tests avec des utilisateurs VoiceOver** (AVH, FAF…) via **TestFlight externe**.
- Audit du stockage (rien en clair dans le conteneur / les sauvegardes), revue des dépendances.
- Soumission App Store via lane fastlane `release` (`deliver`), déclenchée manuellement avec approbation de l'environnement `release` ; métadonnées dans `fastlane/metadata/`.
- Privacy manifest, étiquettes de confidentialité, règle 1.2 (signaler / bloquer), mention « client non officiel ».

---

## Calendrier

| Phase | Durée |
|---|---|
| 0. Dépôt, CI/CD, signature | 1 à 1,5 semaine |
| 1. Socle et connexion | 2 à 3 semaines |
| 2. Liste des conversations | 2 semaines |
| 3. Conversation | 4 à 5 semaines |
| 4. Sécurité | 1 semaine + continu |
| 5. Accessibilité transversale | 2 semaines |
| 6. Fonctions complémentaires | 3 à 4 semaines |
| 7. Tests et publication | 1,5 à 2 semaines |
| **Total** | **≈ 4,5 à 5 mois** |

**MVP (~2 mois)** : phases 0 à 3 + essentiel de la phase 4 (connexion, liste, conversations texte et vocales, conversations secrètes).

---

## Arborescence cible

```
telegram-access/                  # dépôt GitHub privé
├── .github/
│   ├── workflows/
│   │   ├── ci.yml                # build + tests à chaque push / PR
│   │   ├── release.yml           # archive signée → TestFlight
│   │   └── certs-init.yml        # manuel : génération initiale match
│   └── dependabot.yml
├── project.yml                   # XcodeGen
├── Config/
│   ├── Base.xcconfig
│   └── Secrets.xcconfig.example  # Secrets.xcconfig généré en CI, ignoré
├── fastlane/
│   ├── Fastfile                  # lanes test, beta, release
│   ├── Matchfile
│   └── metadata/
├── Gemfile
├── docs/
│   └── PLAN-DEV.md               # ce document
├── Sources/
│   ├── App/
│   ├── Core/{TDLib,Security,Accessibility}/
│   └── Features/{Auth,ChatList,Conversation,SecretChats,Settings}/
└── Tests/{Unit,UI}/
```

## Avancement

**Fait (2026-11-08)**
- Phase 0 : arborescence, `project.yml` (TDLibKit épinglé au commit du tag `1.5.2-tdlib-1.8.69-fb464979`), `Config/*.xcconfig`, `fastlane/` (lanes `test`, `beta`, `certs_init`), workflows `ci.yml`, `release.yml`, `certs-init.yml` (actions épinglées par SHA), Dependabot (actions + bundler ; TDLibKit à mettre à jour à la main), icône provisoire.
- Phase 1 (première version, **non compilée** faute de Mac — la CI fera foi) : `actor TelegramClient`, machine à états (`AuthStep`), écrans téléphone + sélecteur de pays (liste TDLib `getCountries`), code, e-mail, code e-mail, mot de passe 2FA, inscription, déconnexion ; clé de base dans le trousseau ; libellés VoiceOver et messages d'erreur testés unitairement ; audit d'accessibilité en test UI.

**Reste à faire côté compte (manuel)**
- Créer le dépôt privé `telegram-access` et le dépôt `telegram-access-certs`.
- Apple Developer : bundle id `com.nael.telegramaccess`, fiche App Store Connect, clé API ASC.
- Renseigner les secrets de l'environnement `release`, lancer `certs-init`, puis taguer `v0.1.0`.

**Décisions en attente**
- Nom affiché définitif (provisoire : « Accessigram », dans `Config/Base.xcconfig`) — doit respecter les conditions de Telegram.
- `ITSAppUsesNonExemptEncryption` (déclaration export du chiffrement) à trancher avant TestFlight externe.

**Prochaine étape** : faire passer la CI au vert, premier build TestFlight, test VoiceOver sur iPhone, puis phase 2 (liste des conversations).
