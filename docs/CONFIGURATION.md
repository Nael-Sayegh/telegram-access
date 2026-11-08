# Configuration des comptes et des secrets

Guide pas à pas pour permettre à la CI de signer l'app et de l'envoyer sur TestFlight.
Les valeurs secrètes ne doivent **jamais** être commitées, collées dans un ticket ou dans une conversation.
Les conserver dans un gestionnaire de mots de passe.

État du dépôt `Nael-Sayegh/telegram-access` :
- Environnement `release` **créé**, limité à la branche `main` et aux tags `v*`.
- Relecteur obligatoire **indisponible** avec le forfait actuel (réservé aux forfaits payants pour les dépôts privés) : un tag `v*` déclenche donc l'envoi sans validation.

---

## 1. Apple Developer — identifiant d'équipe et bundle id

Prérequis : adhésion **Apple Developer Program** active (99 $/an).

1. https://developer.apple.com/account → **Membership details** → noter le **Team ID** (10 caractères, ex. `AB12CD34EF`).
   → secret `APPLE_TEAM_ID`
2. **Certificates, Identifiers & Profiles** → **Identifiers** → **+** → **App IDs** → **App** :
   - Description : `Telegram Access`
   - Bundle ID : **Explicit** → `com.nael.telegramaccess`
   - Aucune capacité à cocher pour l'instant (les notifications push viendront en phase 6).

## 2. App Store Connect — fiche de l'app

https://appstoreconnect.apple.com → **Apps** → **+** → **Nouvelle app** :

| Champ | Valeur |
|---|---|
| Plateformes | iOS |
| Nom | nom public sur l'App Store, **unique** dans tout le Store. Ne doit pas laisser croire à une app officielle Telegram (ex. « Accessigram – client Telegram accessible ») |
| Langue principale | Français |
| Bundle ID | `com.nael.telegramaccess` |
| SKU | identifiant interne libre, ex. `telegramaccess` |
| Accès utilisateur | Accès complet |

## 3. Clé API App Store Connect

**Utilisateurs et accès** → onglet **Intégrations** → **App Store Connect API** → **Clés d'équipe** → **+** :
- Nom : `GitHub Actions`
- Accès : **Admin** pour la génération initiale des certificats (`certs-init`). Une fois les certificats créés,
  on peut révoquer cette clé et en créer une **App Manager**, suffisante pour l'envoi sur TestFlight.

Noter :
- **Key ID** (10 caractères) → secret `ASC_KEY_ID`
- **Issuer ID** (UUID affiché en haut de la page) → secret `ASC_ISSUER_ID`
- Télécharger `AuthKey_XXXXXXXXXX.p8` — **téléchargeable une seule fois**. Son contenu encodé en base64 → secret `ASC_KEY_P8`

## 4. Telegram — api_id et api_hash

1. https://my.telegram.org → se connecter avec son numéro → **API development tools**.
2. Créer l'application :
   - App title : `Accessigram` (ou le nom retenu)
   - Short name : 5 à 32 caractères alphanumériques, ex. `accessigram`
   - URL : facultatif
   - Platform : **iOS**
   - Description : « Client Telegram non officiel, accessible avec VoiceOver ».
3. Noter **api_id** (nombre) → secret `TG_API_ID`, et **api_hash** (32 caractères hexadécimaux) → secret `TG_API_HASH`.

Conseil : utiliser un compte secondaire pour les essais (les nouveaux `api_id` sont parfois restreints).

## 5. Dépôt des certificats (fastlane match)

1. Créer un dépôt **privé et vide** `Nael-Sayegh/telegram-access-certs` :
   ```powershell
   gh repo create Nael-Sayegh/telegram-access-certs --private
   ```
2. Créer un **jeton fine-grained** : https://github.com/settings/personal-access-tokens/new
   - Nom : `match telegram-access`
   - Expiration : 1 an (à renouveler)
   - Resource owner : `Nael-Sayegh`
   - Repository access : **Only select repositories** → `telegram-access-certs`
   - Permissions → Repository → **Contents : Read and write** (écriture nécessaire pour `certs-init` ; on pourra ensuite créer un jeton **Read-only** pour les builds)
3. Le secret `MATCH_GIT_BASIC_AUTHORIZATION` est le base64 de `Nael-Sayegh:<jeton>` (commande à l'étape 6).
4. `MATCH_PASSWORD` : phrase de passe forte **générée par le gestionnaire de mots de passe**. Elle chiffre
   les certificats dans le dépôt : la perdre oblige à tout régénérer.

## 6. Enregistrer les secrets

Les commandes ci-dessous (PowerShell) demandent chaque valeur sans l'afficher ni la garder dans l'historique.
`gh secret set` sans valeur demande la saisie de façon masquée.

```powershell
$R = "Nael-Sayegh/telegram-access"

gh secret set APPLE_TEAM_ID  --env release --repo $R
gh secret set ASC_KEY_ID     --env release --repo $R
gh secret set ASC_ISSUER_ID  --env release --repo $R
gh secret set TG_API_ID      --env release --repo $R
gh secret set TG_API_HASH    --env release --repo $R
gh secret set MATCH_PASSWORD --env release --repo $R
```

Clé `.p8` encodée en base64 (adapter le chemin) :

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("$HOME\Downloads\AuthKey_XXXXXXXXXX.p8")) | gh secret set ASC_KEY_P8 --env release --repo $R
```

Jeton du dépôt de certificats :

```powershell
$s = Read-Host "Jeton GitHub" -AsSecureString
$t = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
[Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes("Nael-Sayegh:$t")) | gh secret set MATCH_GIT_BASIC_AUTHORIZATION --env release --repo $R
Remove-Variable s, t
```

Vérification (affiche les noms, jamais les valeurs) :

```powershell
gh secret list --env release --repo $R
```

Attendu : `APPLE_TEAM_ID`, `ASC_ISSUER_ID`, `ASC_KEY_ID`, `ASC_KEY_P8`, `MATCH_GIT_BASIC_AUTHORIZATION`,
`MATCH_PASSWORD`, `TG_API_HASH`, `TG_API_ID`.

Ensuite, supprimer le fichier `.p8` de Téléchargements après l'avoir rangé dans le gestionnaire de mots de passe.

## 7. Premier envoi sur TestFlight

1. `main` poussé sur GitHub et CI verte.
2. Onglet **Actions** → **Initialisation des certificats (match)** → **Run workflow** (une seule fois).
   Vérifier que `telegram-access-certs` contient maintenant des fichiers chiffrés.
3. Optionnel : remplacer le jeton d'écriture par un jeton en lecture seule, et la clé Admin par une clé App Manager
   (mettre à jour les secrets correspondants).
4. Taguer et pousser :
   ```powershell
   git tag v0.1.0
   git push origin v0.1.0
   ```
5. Le workflow **Release TestFlight** envoie le build. Après traitement par Apple (10 à 30 min),
   répondre à la question sur le chiffrement dans App Store Connect → TestFlight, puis s'ajouter comme testeur interne
   et installer via l'app **TestFlight** sur l'iPhone.

## Rotation et expiration

| Élément | Durée | Action |
|---|---|---|
| Certificat de distribution | 1 an | relancer `certs-init` |
| Jeton fine-grained | durée choisie | régénérer, mettre à jour `MATCH_GIT_BASIC_AUTHORIZATION` |
| Clé API ASC | illimitée | révoquer immédiatement en cas de fuite |
