# Configuration des comptes et des secrets

Guide pas à pas pour permettre à la CI de signer l'app et de l'envoyer sur TestFlight.
Les valeurs secrètes ne doivent **jamais** être commitées, collées dans un ticket ou dans une conversation.
Les conserver dans un gestionnaire de mots de passe.

**Signature gérée par Apple** (même méthode qu'Accessplayer) : aucun certificat ni profil n'est stocké.
Avec `-allowProvisioningUpdates` et la clé API App Store Connect, Xcode crée ou renouvelle lui-même le
certificat de distribution et le profil à chaque build, puis l'export envoie le build sur TestFlight.

État du dépôt `Nael-Sayegh/telegram-access` :
- Environnement `release` **créé**, limité à la branche `main` et aux tags `v*`. Les secrets y sont rangés.
- Relecteur obligatoire **indisponible** avec le forfait actuel (réservé aux forfaits payants pour les dépôts privés) : un tag `v*` déclenche donc l'envoi sans validation.
- Protection de branche, règles sur les tags et secret scanning également **indisponibles** (forfait gratuit, dépôt privé). Ne jamais ajouter de collaborateur ayant les droits d'écriture : il pourrait déclencher une release signée.

---

## 1. Apple Developer — identifiant d'équipe et bundle id

Prérequis :
- adhésion **Apple Developer Program** active ;
- dernière version du contrat de licence acceptée sur developer.apple.com (sinon l'archive échoue avec « PLA Update available ») ;
- accords **actifs** dans App Store Connect → Business (sinon l'envoi échoue avec `REQUIRED_AGREEMENTS_MISSING_OR_EXPIRED`).

1. https://developer.apple.com/account → **Membership details** → noter le **Team ID** (10 caractères).
   → secret `APPSTORE_TEAM_ID` (même valeur que pour Accessplayer)
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

La clé d'équipe d'Accessplayer (rôle **App Manager**) vaut pour toutes les apps du compte : on peut **réutiliser
les mêmes valeurs**. Pour pouvoir révoquer chaque app séparément, on peut aussi créer une clé dédiée :
**Utilisateurs et accès** → **Intégrations** → **App Store Connect API** → **Clés d'équipe** → **+**,
nom `GitHub Actions telegram-access`, accès **App Manager**.

| Donnée | Secret |
|---|---|
| Key ID (10 caractères) | `APPSTORE_KEY_ID` |
| Issuer ID (UUID en haut de la page) | `APPSTORE_ISSUER_ID` |
| Contenu complet du fichier `AuthKey_XXXXXXXXXX.p8`, tel quel (téléchargeable une seule fois) | `APPSTORE_PRIVATE_KEY` |

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

## 5. Enregistrer les secrets

Les commandes ci-dessous (PowerShell) demandent chaque valeur sans l'afficher ni la garder dans l'historique.

```powershell
$R = "Nael-Sayegh/telegram-access"

gh secret set APPSTORE_TEAM_ID   --env release --repo $R
gh secret set APPSTORE_KEY_ID    --env release --repo $R
gh secret set APPSTORE_ISSUER_ID --env release --repo $R
gh secret set TG_API_ID          --env release --repo $R
gh secret set TG_API_HASH        --env release --repo $R
```

Clé `.p8` (adapter le chemin) :

```powershell
Get-Content -Raw "$HOME\Downloads\AuthKey_XXXXXXXXXX.p8" | gh secret set APPSTORE_PRIVATE_KEY --env release --repo $R
```

Ou par l'interface : dépôt → **Settings** → **Environments** → `release` → **Add environment secret**
(coller le contenu du `.p8` tel quel, lignes `BEGIN` / `END` comprises).

Vérification (affiche les noms, jamais les valeurs) :

```powershell
gh secret list --env release --repo $R
```

Attendu : `APPSTORE_ISSUER_ID`, `APPSTORE_KEY_ID`, `APPSTORE_PRIVATE_KEY`, `APPSTORE_TEAM_ID`, `TG_API_HASH`, `TG_API_ID`.

## 6. Premier envoi sur TestFlight

1. `main` poussé sur GitHub et CI verte.
2. Taguer et pousser (ou onglet **Actions** → **Release TestFlight** → **Run workflow**) :
   ```powershell
   git tag v0.1.0
   git push origin v0.1.0
   ```
3. Après traitement par Apple (10 à 30 min), s'ajouter comme testeur interne dans
   App Store Connect → TestFlight et installer via l'app **TestFlight**. La question sur le
   chiffrement n'est plus posée (voir ci-dessous).

## 7. Chiffrement (export compliance) et France

`Sources/App/Info.plist` déclare `ITSAppUsesNonExemptEncryption = NO` : App Store Connect ne
demande plus le type de chiffrement à chaque build.

Ce choix correspond aux réponses suivantes au questionnaire d'Apple :
- type d'algorithmes : **standard** (TDLib embarque OpenSSL : AES, RSA, Diffie-Hellman, SHA-256 ;
  ni « aucun », ni « propriétaires ») ;
- disponible en France sur l'App Store : **non** → aucune documentation requise.

Il n'est donc valable que si la France reste **décochée** dans App Store Connect → Tarifs et
disponibilité. Avant de rendre l'app disponible en France :

1. Déposer la « Déclaration relative à un moyen de cryptologie » auprès de l'ANSSI
   (démarche en ligne sur demarche.numerique.gouv.fr, gratuite, jusqu'à 2 mois).
2. Envoyer le document obtenu dans App Store Connect → l'app → Informations sur l'app →
   documentation de chiffrement. Apple l'examine (environ 2 jours ouvrés) et fournit une clé.
3. Dans `Info.plist` : `ITSAppUsesNonExemptEncryption` à `YES` et ajouter
   `ITSEncryptionExportComplianceCode` avec cette clé.
4. Seulement ensuite, cocher la France dans la disponibilité.

## Rotation et révocation

| Élément | Action |
|---|---|
| Certificat de distribution | renouvelé automatiquement par Xcode |
| Clé API ASC | révoquer immédiatement en cas de fuite, puis mettre à jour `APPSTORE_*` (ici et dans Accessplayer si la clé est partagée) |
