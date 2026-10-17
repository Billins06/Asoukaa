# Notes de déploiement — backend Asoukaa

## Lot 3 — Sécurité des sessions, envois de fichiers, index, configuration

*(Section ajoutée par l'assistant du lot 3. Écrite pour être lue sans être développeur.)*

### 1. Avant de démarrer : le fichier `.env`

Le serveur **vérifie maintenant son `.env` au démarrage** (fichier `src/config/env.validation.ts`).

- **En production** (`NODE_ENV=production`) : si quelque chose est faux, le serveur **refuse de démarrer** et explique quoi corriger.
- **En développement** : le serveur démarre, mais affiche un grand encadré d'**avertissement**.
- Aucune valeur secrète n'est jamais affichée, seulement le *nom* de la variable en cause.

Le modèle à jour de toutes les variables est dans **`.env.example`** (par exemple le mot de passe e-mail s'appelle bien `MAIL_PASSWORD`, pas `MAIL_PASS`).
Pour la liste complète, copiez `.env.example` vers `.env` et remplissez-le ; **ne mettez jamais de vraies valeurs dans `.env.example`**.

### 2. La clé de chiffrement `ENCRYPTION_KEY`

Elle protège les coordonnées de paiement des vendeurs. Elle doit faire **exactement 64 caractères hexadécimaux** (chiffres 0-9 et lettres a-f).

1. Dans le dossier `backend`, lancez : `npm run generate:key`
   (ou : `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`)
2. Cela affiche une ligne de 64 caractères. Copiez-la.
3. Ouvrez votre `.env` (par exemple `nano .env`) et écrivez : `ENCRYPTION_KEY=` suivi de la ligne copiée, sans espace ni guillemets.
4. Enregistrez, puis **redémarrez** le serveur.
5. **Sauvegardez cette clé ailleurs** (gestionnaire de mots de passe). Une fois des données chiffrées, si la clé est perdue ou changée, ces données deviennent illisibles.

Les clés `JWT_SECRET` et `JWT_REFRESH_SECRET` se génèrent de la même façon, et doivent être **différentes l'une de l'autre**.

### 3. `DB_SYNCHRONIZE` : à laisser sur `false`

- `DB_SYNCHRONIZE=true` fait modifier la base automatiquement par TypeORM à chaque démarrage. Pratique au tout début, mais dangereux : TypeORM peut **supprimer** des index (ou des colonnes) qui n'existent que dans des migrations.
- **Production** : `true` est **interdit** (le serveur refuse de démarrer).
- **Développement** : un avertissement s'affiche. Recommandé : `DB_SYNCHRONIZE=false` et lancer les migrations.
- Les index ajoutés par ce lot sont aussi déclarés dans le code, donc même avec `true` ils ne sont pas supprimés. Mais mieux vaut `false`.

### 4. Migrations à lancer

Commande : `npm run typeorm:run` (elle lance, dans l'ordre, toutes les migrations pas encore exécutées).

Migration ajoutée par ce lot : **`1791810000000-AddPerformanceIndexes`** — crée les index de performance manquants (catalogue produits, messages du chat, boutiques, notifications...). Elle est *idempotente* : on peut la relancer sans risque, elle ne crée pas de doublon. Sur une grosse base, la lancer **hors heures de pointe** (la création d'un index bloque brièvement l'écriture sur la table). Pour l'annuler : `npm run typeorm:revert` (retire seulement les index nouvellement ajoutés).

### 5. Sessions (connexion) — ce qui change

- Nouvelle route **`POST /api/v1/auth/refresh`** : l'appli envoie `{ "refreshToken": "..." }` et reçoit `{ "accessToken": "...", "refreshToken": "..." }`. Elle renvoie 401 si le jeton est invalide, expiré, ou si le compte est bloqué.
- Les **anciens jetons de rafraîchissement** (émis avant ce lot) ne sont plus acceptés : chaque utilisateur devra **se reconnecter une fois**.
- **Changer** ou **réinitialiser** son mot de passe déconnecte tous les appareils. Pour « changer » (`PATCH /users/me/password`), la réponse contient de nouveaux jetons (`accessToken`, `refreshToken`) que l'appli doit enregistrer à la place des anciens (sinon l'utilisateur est renvoyé à l'écran de connexion). Bloquer un compte coupe aussi ses sessions.
- Limite actuelle : un ancien jeton de rafraîchissement reste utilisable jusqu'à son expiration ou jusqu'à la prochaine révocation (pas de détection de réutilisation).

### 6. Envois de fichiers — limites

- Taille maximale **par fichier**, appliquée pendant la réception : images et PDF **5 Mo** (`MAX_FILE_SIZE`), vidéos produit **50 Mo** (`MAX_VIDEO_FILE_SIZE`). Au-delà : erreur 413.
- Le contenu réel est vérifié (pas seulement l'extension) : images JPEG/PNG/WEBP, PDF, vidéos MP4/MOV/WEBM.
- Quota **par utilisateur** : 60 fichiers par heure (`UPLOAD_MAX_PER_HOUR`), 300 pour un administrateur (`UPLOAD_ADMIN_MAX_PER_HOUR`). Au-delà : erreur 429. Ce compteur est en mémoire : il repart de zéro au redémarrage du serveur.
- Images de boutique (logo, bannière), de chat et logos de partenaires : l'adresse doit venir de **notre** stockage (`/upload/shop`, `/upload/chat`, `/upload/vitrine`).

### 7. Fuseau horaire

Ajoutez `TZ=Africa/Lagos` dans le `.env` (ou dans l'environnement Docker) pour que le serveur et la base utilisent la même heure (Bénin).

---

## Installer sur un serveur vide (migration de base « C7 »)

*(Section ajoutée par l'assistant « migration de base ». Écrite pour être lue sans être développeur.)*

**L'idée en une image.** Jusqu'ici, les migrations étaient comme des *travaux de rénovation* (« ajouter une fenêtre », « poser une étagère »), mais **personne n'avait gardé le plan de la maison**. Sur un terrain vide (nouveau serveur), les ouvriers arrivaient pour poser l'étagère… dans une maison qui n'existait pas, et le chantier s'arrêtait.
La migration **`1700000000000-BaselineSchema`** est ce plan de départ : elle construit toute la maison sur un terrain vide, puis les anciennes migrations passent derrière sans rien changer. **Si la maison existe déjà (votre base actuelle), elle ne touche à rien.**

### A. Installer sur un serveur VIDE

1. **Créer la base PostgreSQL vide** (version 13 ou plus récente conseillée). Exemple en ligne de commande, à adapter (avec Docker Compose : `docker compose exec <nom-du-service-postgres> psql -U postgres`) :
   ```
   sudo -u postgres psql
   CREATE ROLE asoukaa LOGIN PASSWORD 'CHOISISSEZ_UN_MOT_DE_PASSE_SOLIDE';
   CREATE DATABASE asoukaa OWNER asoukaa;
   \q
   ```
   La migration de base a besoin de deux « extensions » PostgreSQL (`uuid-ossp` et `pg_trgm`). Le propriétaire de la base peut les créer tout seul depuis PostgreSQL 13. Sur une version plus ancienne, ou un Postgres géré (hébergeur) qui refuse, faites-le une fois en super-utilisateur :
   ```
   \c asoukaa
   CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
   CREATE EXTENSION IF NOT EXISTS pg_trgm;
   ```
2. **Récupérer le code et installer les paquets** dans le dossier `backend` : `npm ci`
   (installez *tous* les paquets, y compris ceux de développement : la commande des migrations utilise `ts-node`).
3. **Créer le fichier `.env`** : `cp .env.example .env` puis `nano .env`. Variables à renseigner (noms seulement, **les valeurs sont à vous**, ne les mettez jamais dans un fichier partagé) :
   - base de données : `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME` (et `DB_SSL_CA` si votre hébergeur l'exige) ;
   - sécurité : `JWT_SECRET`, `JWT_REFRESH_SECRET` (deux valeurs différentes), `JWT_EXPIRES_IN`, `JWT_REFRESH_EXPIRES_IN`, `ENCRYPTION_KEY` (64 caractères hexadécimaux : `npm run generate:key`) ;
   - serveur : `NODE_ENV` (`production` sur le serveur en ligne), `APP_PORT`, `APP_URL`, `FRONTEND_WEB_URL`, `TZ` ;
   - fichiers : `STORAGE_DRIVER` (+ `SUPABASE_URL`, `SUPABASE_SERVICE_ROLE_KEY` si Supabase) ;
   - e-mail : `MAIL_HOST`, `MAIL_PORT`, `MAIL_USER`, `MAIL_PASSWORD`, `MAIL_FROM`, `SUPPORT_TEAM_EMAIL` ;
   - paiement : les variables `FEEXPAY_…` listées dans `.env.example`.
   - **`DB_SYNCHRONIZE` : ne pas le mettre à `true`** (voir la section 3 plus haut).
4. **Créer toutes les tables** : `npm run typeorm:run`
   Résultat attendu : une longue liste, qui commence par `Migration BaselineSchema1700000000000 has been executed successfully.` puis les autres migrations, sans aucune erreur. Relancer la même commande affiche `No migrations are pending` : c'est normal, il n'y a plus rien à faire.
5. **(Recommandé) Charger les catégories** : `npm run seed:categories` (le catalogue complet des catégories ; sans risque à relancer, aucun doublon).
   ⚠️ **N'utilisez PAS `npm run seed` sur un serveur en ligne** : cette commande crée aussi des comptes de démonstration (admins `…@asoukaa.com`, clients, vendeurs, commandes) avec des mots de passe connus de tous.
6. **Créer le premier superadmin.** Le code ne prévoit pas de commande pour ça : un superadmin ne peut normalement être créé que par un autre superadmin (invitation par e-mail), donc le *tout premier* se crée directement dans la base :
   1. Dans le dossier `backend`, fabriquez le mot de passe « haché » (le mot de passe n'est jamais stocké en clair) :
      ```
      read -s -p "Mot de passe du superadmin : " MDP; export MDP; echo
      node -e "require('bcrypt').hash(process.env.MDP,12).then(h=>console.log(h))"
      unset MDP
      ```
      Cela affiche une ligne qui commence par `$2b$12$…` : copiez-la.
   2. Ouvrez `psql` sur la base (`psql -h <hôte> -U asoukaa -d asoukaa`), **collez** (ne pas passer par `-c "…"` : le `$` serait mal interprété) en remplaçant les valeurs entre `< >` :
      ```
      INSERT INTO admin_accounts (prenom, name, email, "passwordHash", role, "isActive", "isPasswordSet")
      VALUES ('<Prénom>', '<Nom>', '<votre-email>', '<la ligne $2b$12$… copiée>', 'superadmin', true, true);
      ```
   3. Connectez-vous ensuite sur le tableau de bord admin avec cet e-mail et ce mot de passe, puis créez les autres admins depuis le tableau de bord (ils reçoivent une invitation par e-mail).
7. **Démarrer** : `npm run build` puis `npm run start:prod` (ou votre Docker Compose habituel). Vérification rapide : ouvrir `http://<serveur>:<APP_PORT>/api/v1/products` doit afficher du JSON (`"data":[]` tant qu'il n'y a pas de produit).

### B. Sur la base ACTUELLE (celle qui existe déjà)

Rien de spécial à faire : `npm run typeorm:run` comme d'habitude. Vous verrez :

`BaselineSchema1700000000000 : la table "users" existe déjà, le schéma est supposé installé - aucune modification.`

puis `Migration BaselineSchema1700000000000 has been executed successfully.` : **la migration de base s'est simplement notée comme « faite », sans créer, modifier ni supprimer quoi que ce soit** (c'est vérifié par le test ci-dessous : schéma et nombre de lignes de chaque table identiques avant/après).

### C. À savoir

- **Annuler (`npm run typeorm:revert`)** : sur une base installée, la migration de base est enregistrée en dernier si rien d'autre n'était à exécuter en même temps. Un premier `typeorm:revert` tombe alors sur elle : il **ne supprime rien** et le dit (« rien à supprimer ici ») ; relancez-le pour annuler la vraie dernière migration. La migration de base ne peut effacer les tables **que** sur une base de test, hors production, avec `BASELINE_DOWN_CONFIRM=OUI`, et seulement si c'est la seule migration enregistrée.
- **Ne modifiez jamais la migration de base** : les évolutions futures se font par de **nouvelles** migrations (`npm run typeorm:generate`, puis relecture).
- Les noms d'index et de contraintes des tables créées par des migrations (retraits, preuves de livraison, tickets, vitrine…) suivent ceux des migrations. Avec `DB_SYNCHRONIZE=true`, TypeORM les renommerait au démarrage : encore une raison de le laisser à `false`.

### D. Vérifier que tout fonctionne (test automatique)

`scripts/test-baseline.sh` rejoue toute la vérification sur des bases **jetables** (il ne touche jamais à votre vraie base) : base vide → migrations sans erreur → deuxième passage sans effet → schéma identique à celui des entités ; base déjà installée → rien ne bouge ; annulation sans danger. Mode d'emploi dans l'en-tête du script (il suffit d'un PostgreSQL de test, par exemple `docker run --rm -d --name pg-bltest -e POSTGRES_PASSWORD=test -p 55432:5432 postgres:16`, puis `BL_DB_PORT=55432 BL_DB_PASSWORD=test bash scripts/test-baseline.sh`).

---

## Webhook et rattrapage des paiements FeexPay

**L'idée en une image.** Avant, après avoir demandé le paiement, l'appli « regardait par la fenêtre » pendant environ 2 minutes pour voir si le client avait validé son code PIN. Si le client était lent, l'appli abandonnait : le paiement restait inconnu de nous, même si le client était ensuite débité. Maintenant il y a deux filets de sécurité :

- **Le webhook** = le *facteur* : FeexPay sonne chez nous dès qu'un paiement est terminé (si FeexPay propose ce service, ce n'est pas certain).
- **Le rattrapage** = l'*employé qui repasse* : toutes les 5 minutes, il revérifie auprès de FeexPay les paiements restés « en attente ». **Il fonctionne même sans webhook.**

**Règles de sécurité (à retenir).**
- Un paiement ne passe « échoué » que si **FeexPay le dit explicitement**, ou si **24 h** se sont écoulées sans succès. Un abandon côté appli ne suffit plus : le paiement reste « en attente » et le client voit « Paiement en cours de vérification, ne payez pas une seconde fois ».
- Le webhook ne croit jamais ce qu'il reçoit : il s'en sert seulement pour retrouver la référence, puis **redemande l'état réel à FeexPay**.
- Si FeexPay indique un montant différent de celui de la commande, le paiement n'est **pas** confirmé automatiquement : un avertissement est écrit dans les logs et le paiement apparaît dans « paiements à examiner » (menu admin).
- Le client est prévenu (notification dans l'appli) quand son paiement est confirmé par le webhook ou le rattrapage.

**Adresse à donner à FeexPay** (si le service existe), à remplacer `<domaine>` et `<secret>` :

```
https://<domaine>/api/v1/payments/webhook/feexpay?token=<secret>
```

Le `<secret>` est une longue chaîne aléatoire que **vous** choisissez, et que vous mettez dans le `.env` du serveur : `FEEXPAY_WEBHOOK_SECRET=<secret>` (variable facultative ; ne la partagez jamais dans un fichier du dépôt). Sans cette variable, le webhook accepte tout appel (sans danger, car FeexPay est toujours re-interrogé, mais un avertissement s'affiche au démarrage). Après modification du `.env`, redémarrez le serveur.

**À demander au support FeexPay :**
1. Proposez-vous un **webhook** (notification automatique) pour les paiements Mobile Money ? Où le configurer (tableau de bord, par boutique) ?
2. Y a-t-il un **en-tête de signature** (ou un secret) pour vérifier que l'appel vient bien de vous ? Lequel, et comment est-il calculé ?
3. Quel est le **format exact** du message (champs, nom du champ qui contient la référence de transaction, montant, statut) ?
4. En cas d'échec de notre part, **réessayez-vous** l'envoi ? Combien de fois, à quel rythme ?
5. Le champ « montant » du statut d'une transaction inclut-il les frais, ou est-ce exactement le montant demandé ?

**Pour découvrir le vrai format.** Chaque appel reçu sur le webhook est écrit dans les logs du serveur (ligne `Webhook FeexPay reçu | ip=… | clés=[…] | corps=…`, corps tronqué à 2000 caractères, secrets masqués). Faites un petit paiement test, puis cherchez cette ligne : `docker compose logs backend | grep "Webhook FeexPay"` (adaptez le nom du service). Si FeexPay n'appelle jamais, rien ne casse : le rattrapage prend le relais.

**Rattrapage : ce qu'il fait exactement.** Toutes les 5 minutes, jusqu'à 50 paiements « en attente » (avec référence FeexPay, créés depuis plus de 5 minutes) : moins d'1 h → vérifiés à chaque passage ; entre 1 h et 24 h → une fois par heure ; plus de 24 h → une dernière vérification, puis « échoué » si FeexPay ne confirme pas le succès. Un panier de plusieurs boutiques n'est vérifié qu'une seule fois. Si FeexPay est injoignable, rien n'est modifié. Les actions apparaissent dans les logs (`Rattrapage des paiements : …`).

**Si un client relance un paiement alors qu'un autre est « en attente »** (moins de 15 minutes) : le serveur interroge FeexPay ; si c'est réussi il confirme, si c'est échoué il laisse réessayer, sinon il répond « Un paiement est déjà en cours de vérification pour cette commande, patientez quelques minutes. » (pas de double débit).
