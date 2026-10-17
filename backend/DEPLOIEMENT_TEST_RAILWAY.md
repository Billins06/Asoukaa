# Guide complet — serveur de test Asoukaa sur Railway

Image : aujourd'hui tes collègues entrent chez toi (ton PC). Après ce guide, le serveur est dans un local ouvert jour et nuit, avec une adresse fixe.

**Ce qu'on met en ligne (3 « services » Railway dans UN projet)**

| Service | Rôle | Adresse |
|---|---|---|
| Postgres | la base de données (vide au départ) | interne (invisible) |
| backend | le serveur Asoukaa | `https://api-test.asoukaa.com` |
| web-test | la version web de l'appli (pour l'iPhone) | `https://test.asoukaa.com` |

⚠️ Ne colle JAMAIS un mot de passe ou une clé dans une conversation : tu les tapes toi-même dans Railway.
⚠️ Sur ce serveur, **ne lance JAMAIS `npm run seed`** : il crée des administrateurs au mot de passe public `Admin1234!`. Utilise `create-admin` (étape 13).

---
## PARTIE 1 — Avant Railway (≈ 20 min)

### 1. Envoyer ton code sur GitHub
Railway lit ton code sur GitHub. Dans CHAQUE projet (appli, backend, dashboard) :
1. Ouvre PowerShell dans le dossier du projet.
2. `powershell -ExecutionPolicy Bypass -File .\publier-github.ps1`
3. Le script montre la branche et l'adresse GitHub, refuse d'envoyer `.env`, clés et sauvegardes, cherche des clés secrètes, puis te demande de taper **o**. Il fait ensuite commit + push.
4. Si GitHub demande de te connecter, une fenêtre s'ouvre : c'est normal (ton mot de passe reste dans Windows).
Le backend est dans le dépôt `Billins06/Asoukaa` (dossier racine `C:\PROJET\Asoukaa\Asoukaa`, sous-dossier `backend`).

### 2. Fabriquer 3 secrets neufs (pour le serveur de test)
Dans le dossier `backend`, lance 3 fois : `npm run generate:key`. Note les 3 lignes dans un fichier bloc-notes **à toi** :
- la 1re → `JWT_SECRET`
- la 2e → `JWT_REFRESH_SECRET`
- la 3e → `ENCRYPTION_KEY`
(La base de test est vide et séparée : des clés neuves sont normales.)

### 3. Rassembler les valeurs de ton `.env` local
Ouvre ton `.env` (toi, pas moi) et repère : `MAIL_*`, `SUPPORT_TEAM_EMAIL`, `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY`, les deux noms de buckets, `FEEXPAY_API_KEY`, `FEEXPAY_SHOP_ID`. Tu les recopieras à l'étape 7. Supabase : on garde le même projet.

---
## PARTIE 2 — Railway

### 4. Créer le compte
1. railway.com → *Login* → *Login with GitHub* (le plus simple : Railway voit alors tes dépôts).
2. Un essai de 30 jours avec 5 $ de crédit démarre. Une carte bancaire peut être demandée : si oui, saisis-la toi-même.
3. Avant la fin de l'essai (ou quand le crédit est épuisé), choisis la formule **Hobby** (5 $/mois) dans *Settings → Billing*, sinon le serveur s'arrête.

### 5. Créer le projet et le backend
1. *New Project* → *Deploy from GitHub repo* → choisis `Billins06/Asoukaa` (autorise Railway si on te le demande).
2. Un service se crée. Clique dessus → *Settings* → *Source* → **Root Directory** : `/backend`. (Le dépôt contient plusieurs dossiers ; Railway doit regarder dans `backend`.)
3. Si le *Branch* proposé n'est pas la bonne branche, choisis celle de ton backend.
4. Le `Dockerfile` et `railway.json` sont reconnus tout seuls.

### 6. Ajouter la base de données
Sur le projet : *+ New* → *Database* → *Add PostgreSQL*. Laisse le nom **Postgres**. Railway crée la base et ses variables (`PGHOST`, `PGPORT`, `PGUSER`, `PGPASSWORD`, `PGDATABASE`).

### 7. Les variables du backend
Service backend → onglet **Variables** → *Raw Editor* → colle le contenu de `.env.railway.example` et remplis les valeurs vides :
- `APP_URL` : pour l'instant l'adresse `https://…up.railway.app` de l'étape 9 (tu la changeras ensuite).
- Les 3 secrets de l'étape 2, les valeurs de l'étape 3.
- Les lignes `${{Postgres.PGHOST}}` etc. se copient telles quelles (le nom entre accolades = le nom du service base). Si une ligne est refusée, utilise le bouton d'ajout de référence de Railway.
Enregistre : Railway relance le service.

### 8. Premier démarrage
*Deployments* → clique le déploiement → *View logs*. Au démarrage le serveur crée les tables (migrations) puis affiche « 🚀 Asoukaa API lancée ». Un message qui nomme une variable manquante = ajoute-la (jamais la valeur affichée).

### 9. L'adresse
1. Service backend → *Settings* → *Networking* → *Public Networking* → **Generate Domain** → tu obtiens `…up.railway.app`.
2. Test : ouvre `https://…up.railway.app/api/v1/categories/flat` → tu dois voir `[]`.
3. Ton adresse à toi : même endroit → *Custom Domain* → `api-test.asoukaa.com`. Railway affiche **un CNAME et un TXT** à ajouter chez l'hébergeur du domaine `asoukaa.com` (zone DNS : *Ajouter un enregistrement*, recopie nom et valeur exactement). Si le DNS est chez Cloudflare, mets le nuage en « DNS seulement » (gris).
4. Attends que Railway affiche la coche verte (quelques minutes à quelques heures) ; le HTTPS est automatique.
5. Retourne dans *Variables* : `APP_URL=https://api-test.asoukaa.com`.

### 10. Vérification
`https://api-test.asoukaa.com/api/v1/categories/flat` répond `[]`. La base est vide : c'est normal.

### 11. Installer l'outil Railway sur ton PC (une fois)
`npm i -g @railway/cli` puis `railway login` (une page web s'ouvre) puis, dans le dossier `backend` : `railway link` (choisis le projet et le service backend).

### 12. Remplir les catégories
`railway ssh` (tu arrives dans le serveur), puis :

    node dist/database/seed-categories-runner.js

### 13. Créer TON compte administrateur
Toujours dans `railway ssh` :

    node dist/database/create-admin-runner.js

Tape ton e-mail, prénom, nom, puis le mot de passe (12 caractères minimum, invisible). Quitte avec `exit`. Tu te connecteras avec ce compte au site admin.

### 14. Importer les produits sur le serveur de test
Sur ton PC, dans `backend` (le serveur doit avoir des vendeurs approuvés : crée les deux comptes vendeur dans l'appli en ligne, puis approuve-les depuis le site admin) :

    node scripts/import-produits/import-produits.js --shop "Boutique Annette" --api https://api-test.asoukaa.com/api/v1

---
## PARTIE 3 — Site admin (dashboard) en ligne
Même principe qu'un 2e service Railway (dépôt `asoukaa-dashboard`, Next.js). On le fera dans un second temps ; dis-moi quand le backend répond.

---
## PARTIE 4 — Téléphones Android avec Firebase (mises à jour en un clic)
**Une fois**
1. console.firebase.google.com → *Ajouter un projet* (nom : Asoukaa Test, Analytics non nécessaire).
2. *Ajouter une appli → Android*, nom du paquet : `com.asoukaa.app`. Tu peux sauter le fichier de configuration proposé (inutile pour distribuer).
3. Menu *Release & Monitor → App Distribution* → *Get started*.
4. Onglet *Testers & Groups* → crée le groupe **testeurs** et ajoute les e-mails (Gmail) de tes collègues Android.

**À chaque nouvelle version**
1. Dans `pubspec.yaml`, **augmente le numéro** : `version: 1.0.0+2`, puis `+3`… (sans ça Android refuse la mise à jour).
2. `.\preparer-apk-ligne.ps1` (APK branché sur `https://api-test.asoukaa.com`).
3. Firebase → App Distribution → *Releases* → glisse `app-release.apk` → ajoute le groupe **testeurs** → *Distribute*.
4. Tes collègues reçoivent un e-mail ; la 1re fois ils installent l'application « App Tester » puis installent la version en un clic.
⚠️ Garde TOUJOURS le même `keystore/release.keystore` (sauvegarde-le dans un endroit sûr). Une autre clé = mise à jour refusée, il faudrait désinstaller.
Quand tu changes seulement le **serveur**, tes collègues n'ont rien à faire.

---
## PARTIE 5 — Version web (iPhone et navigateurs)
1. Dossier de l'appli : `.\preparer-web-test.ps1` (crée `deploiement-web`).
2. Railway : projet → *+ New* → *Empty Service* → nomme-le **web-test**.
3. Dans `deploiement-web` : `railway link` (choisis web-test) puis `railway up`.
4. Service web-test → *Settings → Networking* → *Custom Domain* → `test.asoukaa.com` (CNAME + TXT, comme à l'étape 9).
5. Ton collègue iPhone ouvre `https://test.asoukaa.com` dans Safari. Pour une mise à jour : refais 1 et `railway up`.
6. Dans les variables du backend : `FRONTEND_WEB_URL=https://test.asoukaa.com`.

---
## PARTIE 6 — FeexPay (APRÈS que le serveur répond)
1. Choisis un secret du webhook (longue chaîne, `npm run generate:key`) → variable Railway `FEEXPAY_WEBHOOK_SECRET`.
2. L'adresse à donner à FeexPay : `https://api-test.asoukaa.com/api/v1/payments/webhook/feexpay?token=TON_SECRET`.
3. Envoie l'e-mail au support (avec ton `SHOP_ID`, jamais la clé `fp_…`).
4. Fais un petit paiement réel et note le montant demandé, débité et crédité.

---
## PARTIE 7 — Problèmes fréquents
- *Le déploiement échoue* : lis les logs ; une variable manquante est nommée.
- *`/categories/flat` ne répond pas* : domaine pas encore validé (attends), ou service en erreur (logs).
- *CORS / la version web ne charge pas* : vérifie `FRONTEND_WEB_URL` et `CORS_EXTRA_ORIGINS` (adresses exactes, sans `/` final).
- *Mise à jour Android refusée* : numéro de version pas augmenté, ou clé de signature différente.
- *Facture* : onglet *Usage* du projet ; arrête les services inutiles pendant les pauses.
