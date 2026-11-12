# Plan de développement — Client Telegram accessible VoiceOver (iPhone)

> Dernière mise à jour : 2026-11-11
> Objectifs : connexion par numéro de téléphone, accessibilité lecteur d'écran prioritaire, sécurité des communications.
> Contraintes : dépôt Git **privé** sur GitHub, développement sous Windows, **compilation / signature / upload via GitHub Actions macOS**.

---

## Décisions structurantes

| Sujet | Choix | Raison |
|---|---|---|
| Langage / UI | **Swift + SwiftUI** (y compris la liste des messages : une `UICollectionView` essayée donnait sous VoiceOver un parcours désordonné, 2026-11-11) | Meilleur support VoiceOver natif |
| Accès Telegram | **TDLib** via [TDLibKit](https://github.com/Swiftgram/TDLibKit) (SPM) | MTProto, chiffrement, synchro, base locale chiffrée gérés officiellement |
| Architecture | MVVM, `actor TelegramClient`, async/await, `AsyncStream` des updates | Isolation, testabilité |
| Projet Xcode | **XcodeGen** (`project.yml`), `.xcodeproj` non versionné | Éditable sous Windows |
| CI/CD | **GitHub Actions macOS** + `xcodebuild`, signature gérée par Apple | Pas de Mac local, aucun certificat à stocker |
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
- Dependabot (GitHub Actions).
- Protection de `main`, règles sur les tags et secret scanning : **indisponibles** pour un dépôt privé avec le forfait gratuit (vérifié le 2026-11-09), et GitHub Pro n'est pas retenu. Conséquences acceptées : push direct sur `main`, et tout tag `v*` déclenche la release sans relecture. Compensations : 2FA sur le compte GitHub, aucun collaborateur, secrets uniquement dans l'environnement `release`.
- `.gitignore` : `*.xcodeproj`, `build/`, `*.p12`, `*.mobileprovision`, `Config/Secrets.xcconfig`.
- Secrets injectés à la compilation via un `.xcconfig` généré par la CI.

### 0.3 Signature sans Mac : signature gérée par Apple
- Pas de certificat ni de profil stocké (ni dépôt secondaire, ni fastlane) : même méthode qu'Accessplayer.
- `xcodebuild archive` / `-exportArchive` avec `-allowProvisioningUpdates` et la clé API ASC (rôle App Manager) : Xcode crée ou renouvelle certificat de distribution et profil, et l'export (`destination: upload`) envoie le build sur TestFlight.

### 0.4 Secrets GitHub (environment `release`, limité à `main` et aux tags `v*`)
Approbation manuelle (relecteur obligatoire) indisponible avec le forfait gratuit pour un dépôt privé. Procédure détaillée : [CONFIGURATION.md](CONFIGURATION.md).

| Secret | Usage |
|---|---|
| `APPSTORE_TEAM_ID` | Identifiant d'équipe Apple Developer (signature) |
| `APPSTORE_KEY_ID`, `APPSTORE_ISSUER_ID`, `APPSTORE_PRIVATE_KEY` (contenu du `.p8`) | Clé API App Store Connect (mêmes noms qu'Accessplayer) |
| `TG_API_ID`, `TG_API_HASH` | API Telegram |

Les builds de PR n'ont pas accès aux secrets de signature.

### 0.5 Workflows
XcodeGen est téléchargé dans une version figée et vérifié par empreinte SHA-256 (pas de `brew install`).

**`ci.yml`** (push, PR, manuel) : `xcodegen generate` → `xcodebuild test` sur simulateur sans signature → tests unitaires ; tests UI (`performAccessibilityAudit()` sur chaque écran de connexion, affiché par un service factice) sur les PR et les lancements manuels → cache SPM / TDLib.

**`release.yml`** (tag `v*` ou manuel) : `xcodegen generate` → `Secrets.xcconfig` + clé `.p8` écrits dans le runner → `xcodebuild archive` (signature automatique, build number = `github.run_number`, paquets résolus à neuf, sans cache) → `xcodebuild -exportArchive` (envoi TestFlight) → suppression des secrets → artefact dSYM (rétention courte).

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
   - `WaitPassword` → 2FA avec indice ; « Mot de passe oublié » (code envoyé à l'e-mail de récupération, nouveau mot de passe obligatoire)
   - `WaitRegistration` → prénom / nom + conditions d'utilisation de Telegram (fenêtre bloquante si Telegram l'exige, âge minimum)
   - `Ready`
3. Accessibilité des écrans :
   - Pays avec recherche, annoncé « France, plus 33 ».
   - `textContentType = .telephoneNumber` et `.oneTimeCode`.
   - Erreur ajoutée au libellé du champ fautif + focus VoiceOver sur ce champ (annonce `AccessibilityNotification.Announcement` si le focus y est déjà).
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
- Liste SwiftUI à identifiants stables (focus conservé lors du chargement de l'historique), titres de jour en lignes ordinaires : parcours VoiceOver dans l'ordre chronologique, sans saut, comme WhatsApp. (Une `UICollectionView`, prévue à l'origine, donnait à l'essai un parcours désordonné.)
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
- Clé absente du trousseau (nouvel appareil, trousseau effacé) : le dossier TDLib est vidé **avant** la création d'une nouvelle clé, la session est perdue (reconnexion). Trousseau verrouillé : erreur, rien n'est effacé.
- Déconnexion (locale ou session révoquée à distance) : dossier TDLib effacé et clé supprimée ; la session suivante utilise une clé neuve.
- Journaux TDLib : aucun en Release (`logStreamEmpty`), erreurs seules en Debug.
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
- Soumission App Store depuis App Store Connect à partir d'un build TestFlight (métadonnées et captures saisies dans App Store Connect).
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
│   │   └── release.yml           # archive signée (gérée par Apple) → TestFlight
│   └── dependabot.yml
├── project.yml                   # XcodeGen
├── Config/
│   ├── Base.xcconfig
│   └── Secrets.xcconfig.example  # Secrets.xcconfig généré en CI, ignoré
├── docs/
│   ├── PLAN-DEV.md               # ce document
│   └── CONFIGURATION.md          # comptes Apple / Telegram et secrets
├── Sources/
│   ├── App/
│   ├── Core/{TDLib,Security,Accessibility}/
│   └── Features/{Auth,ChatList,Conversation,SecretChats,Settings}/
└── Tests/{Unit,UI}/
```

## Avancement

**Fait (2026-11-08)**
- Phase 0 : arborescence, `project.yml` (TDLibKit épinglé au commit du tag `1.5.2-tdlib-1.8.69-fb464979`), `Config/*.xcconfig`, workflows `ci.yml` et `release.yml` (actions épinglées par SHA), environnement `release`, Dependabot (actions ; TDLibKit à mettre à jour à la main), icône provisoire.
- 2026-11-09 : fastlane match remplacé par la signature gérée par Apple (comme Accessplayer) — plus de dépôt de certificats ni de fastlane.
- Phase 1 : `actor TelegramClient` (derrière le protocole `AuthService`), machine à états (`AuthStep`), écrans téléphone + sélecteur de pays (liste TDLib `getCountries`), code, e-mail, code e-mail, mot de passe 2FA, inscription, déconnexion ; clé de base dans le trousseau. CI verte et build `v0.1.1` envoyé sur TestFlight le 2026-11-09.
- 2026-11-09, revue de la phase 1 : conditions d'utilisation affichées à l'inscription, « Mot de passe oublié », longueur de code inconnue (0) gérée, erreur rattachée au champ fautif (pays, nom…) avec annonce si le focus y est déjà, « Déconnexion… » pendant la déconnexion, « Réessayer » sans recréer de client TDLib, clé créée après l'effacement du dossier, effacement du dossier et de la clé à la déconnexion, journaux TDLib coupés en Release, chiffres saisis normalisés en ASCII, `SWIFT_STRICT_CONCURRENCY: complete`, XcodeGen épinglé, release sans cache ; tests unitaires de `AuthViewModel` (service factice) et audits UI de chaque écran.
- 2026-11-09 : `ITSAppUsesNonExemptEncryption = NO` dans `Info.plist` → App Store Connect ne pose plus la question du chiffrement à chaque build. Valable tant que l'app n'est pas disponible en France sur l'App Store (algorithmes standard via TDLib/OpenSSL : seule la déclaration française serait exigée). Détails : `docs/CONFIGURATION.md`.

- 2026-11-10, phase 2 (branche `phase-2`) : liste des conversations alimentée par les updates TDLib (store créé avec le client, aucun `updateNewChat` perdu), une ligne = un élément VoiceOver (« Marie Dupont, 3 non lus, dernier message : …, 14 h 32 », « conversation secrète » dans le libellé, médias décrits), contenu secondaire (épinglée, sourdine, brouillon, type) dans « Plus de contenu », pagination, état de connexion annoncé seulement s'il dure ; actions personnalisées (lu / non lu, épingler, notifications, archiver, supprimer ou quitter avec confirmation), balayage hors VoiceOver ; écran Archives ; filtres Tous / Non lus / Personnes / Groupes / Chaînes dans un menu « Filtre » (« Filtre : Non lus ») ; rotors Non lus, Mentions, Épinglées ; recherche sur un écran dédié ouvert par le bouton « Rechercher », dans les messages (par défaut, paginés) ou parmi les conversations (y compris groupes et chaînes publics), résultat annoncé une fois. Barre du haut lue dans un ordre constant : Options, Discussions, Rechercher, Filtre (titre toujours dans la barre ; pas de `.searchable`, placé en bas de l'écran par iOS 26). Mention « client non officiel » dans le menu Options. Tests unitaires (réducteur, libellés, modèles de vue) et tests UI avec conversations factices. Conversation : écran provisoire (phase 3).

- 2026-11-11 : phase 2 fusionnée dans `main` ; confirmations (suppression, déconnexion) en alertes pour que « Annuler » reste visible sous iOS 26.
- 2026-11-11, phase 3 (branche `phase-3`), lot 1 : plomberie des messages — flux `messageEvents` né avec le client et redistribué par `MessageHub` (aucun message perdu entre l'abonnement d'un écran et le chargement de son historique), conversion TDLib (contenu, liens en UTF-16, mentions, médias, réponse, transfert, réactions, état d'envoi), service `ConversationService` (historique, envoi, modification, suppression, transfert, épinglage, réactions, lien, renvoi, téléchargement, vocal, « écrit… »), réducteur `ConversationState` (fenêtre contiguë paginée dans les deux sens, message provisoire remplacé à l'envoi), libellés VoiceOver d'un message (« Paul Martin, D'accord, en réponse à votre message : …, 14 h 32, lu, modifié, réactions : 👍 2 dont vous »), en-têtes de jour, activité ; liens : action nommée d'après la vraie destination, web / Telegram / courriel ouverts directement, autre app (`tel:`, `sms:`, raccourcis…) après confirmation montrant la destination complète, `javascript:` / `file:` / `data:` jamais ouverts ; tests unitaires. CI : lancement manuel possible sans tests UI.

- 2026-11-11, phase 3, lot 2 : écran de conversation — `UICollectionView` à identifiants stables (focus conservé quand l'historique s'insère au-dessus ou qu'un message arrive, position visuelle conservée), en-têtes de jour annoncés comme en-têtes, un message = un élément VoiceOver, ouverture au premier non lu (fenêtre autour du dernier lu) ou en bas avec focus sur ce message, pagination dans les deux sens, messages vus signalés après 0,5 s d'immobilité, boutons « Aller au premier message non lu » / « Aller au dernier message », barre de rédaction (champ multiligne, Envoyer estompé tant que le champ est vide, « écrit… » au-dessus du champ), annonce « Message envoyé. » ou raison de l'échec (texte conservé), jamais de défilement automatique sous VoiceOver. Tests unitaires du modèle de vue et tests UI (libellés, audit, envoi). CI : attente d'un simulateur iPhone avant les tests.

- 2026-11-11, essai sur iPhone du lot 2 : parcours VoiceOver de la liste des messages désordonné, différent selon le sens. Liste refaite en SwiftUI (`List`) : ordre de lecture = ordre chronologique, y compris hors de l'écran, titres de jour en lignes ordinaires (plus d'en-têtes collants), premier titre lu « Hier, début de la conversation » une fois tout l'historique chargé, position conservée quand l'historique s'insère au-dessus. Test UI de l'ordre de lecture ajouté ; audit d'accessibilité complet de l'écran (taille du texte comprise). CI verte et parcours VoiceOver validé sur iPhone le 2026-11-12.

**Reste à faire côté compte (manuel)**
- Rien de bloquant pour TestFlight (secrets `release` en place, envoi fonctionnel).
- Avant de rendre l'app disponible en France sur l'App Store : déclaration ANSSI, envoi dans App Store Connect, puis `ITSAppUsesNonExemptEncryption = YES` + `ITSEncryptionExportComplianceCode` (voir `docs/CONFIGURATION.md`).

**Décisions en attente**
- Nom affiché définitif (provisoire : « Accessigram », dans `Config/Base.xcconfig`) — doit respecter les conditions de Telegram.
- Push chiffrées (phase 6) : l'extension de notification doit lire la base TDLib appareil verrouillé, ce qui est incompatible avec `completeUnlessOpen` et la clé `WhenUnlockedThisDeviceOnly` → choisir avant la phase 6 (ex. `completeUntilFirstUserAuthentication` + `AfterFirstUnlockThisDeviceOnly` en App Group, avec migration de la clé).

**Prochaine étape** : phase 3, lot 3 : actions sur les messages (répondre, réagir, copier, transférer, modifier, épingler, liens avec confirmation pour une autre app, renvoyer, supprimer), rotors (non lus, liens, mentions, médias), Magic Tap et Escape.
