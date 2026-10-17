# Rapport d'audit Asoukaa — serveur, application mobile, site admin

Date : 11 octobre 2026. Audit en **lecture seule** : aucun fichier du projet n'a été modifié.

## Comment lire ce rapport

- 7 relecteurs indépendants (qui n'ont pas écrit le code) ont lu le code du serveur (NestJS), de l'application (Flutter) et du site admin (Next.js).
- Rien n'a été exécuté en vrai (pas de test sur téléphone, pas de requête sur un serveur lancé). Les points marqués **« à tester »** dépendent du comportement réel.
- Sur les points les plus graves, j'ai relu moi-même le code : commission sur les frais de livraison, QR de livraison, corps de `/coupons/validate`, tri des remboursements, statuts du site admin, absence de migration de base. Les autres constats viennent des relecteurs, qui citent fichier et ligne.
- Résultats de compilation : serveur `tsc` = 0 erreur ; site admin `tsc` = 0 erreur (mais les types ne correspondent pas aux réponses réelles, voir plus bas). L'application n'a pas pu être analysée dans cet environnement (`flutter analyze` à lancer chez toi).

## Verdict en une page

Le socle est sain : prix recalculés côté serveur, stock verrouillé, contrôles de propriétaire sur la plupart des données, mots de passe et jetons bien traités, e-mails protégés. Les problèmes sont ailleurs :

1. **L'argent** : la plateforme paie le vendeur sur les frais de livraison, un remboursement ne reprend pas le gain du vendeur, et il n'y a ni webhook ni rattrapage pour les paiements Mobile Money.
2. **Le site admin ne parle pas la même langue que le serveur** : les statuts y sont en MAJUSCULES anglaises, le serveur les a en français. Commandes, avis, remboursements, commissions et livreurs sont en partie inutilisables.
3. **Des fonctions entières sont orphelines** : course express, import assisté, écran admin intégré à l'application, retraits vendeurs et paiements livreurs côté admin.
4. **Le déploiement** : aucune migration ne crée le schéma initial, `.env.example` est inutilisable, une clé de chiffrement est invalide.

---

## 1. CRITIQUE — à corriger avant toute mise en production

**C1. Le vendeur est payé sur les frais de livraison, en plus du livreur** — `payments/payments.service.ts:1148` *(vérifié)*
La commission est calculée sur `order.total`, qui inclut `fraisLivraison`. Le livreur reçoit en plus 80 % des mêmes frais. Exemple : 10 000 de produits + 2 000 de livraison = 12 000 encaissés ; vendeur crédité 10 800, livreur 1 600, soit 12 400 versés. Correctif : base de commission = sous-total moins remise, frais de livraison exclus.

**C2. Un remboursement n'enlève pas le gain du vendeur** — `payments.service.ts:984`, `vendor-withdrawals.service.ts:125`
`processRefund` marque seulement le paiement « remboursé ». Le solde vendeur est calculé sur les commandes livrées, sans exclure les paiements remboursés. Le vendeur peut retirer l'argent déjà rendu au client. Aucun délai maximum pour demander un remboursement, aucun appel FeexPay de remboursement (l'argent est rendu à la main), et le statut « traité » n'est jamais utilisé.

**C3. Pas de webhook FeexPay, pas de rattrapage des paiements** — `payments.service.ts:538, 794`
Un paiement n'est confirmé que si l'application revient demander son état. Si le client valide sur son téléphone puis ferme l'application, il est débité mais la commande reste « en attente ». Pire, l'application annule automatiquement le paiement après 2 minutes (`checkout_screen.dart:474, 547`) et le serveur le passe en « échoué » sans demander à FeexPay : un client qui valide à la 3e minute perd son argent. Le montant renvoyé par FeexPay n'est jamais comparé. Correctif : webhook signé et idempotent + tâche qui relit les paiements en attente + vérification FeexPay avant tout passage en « échoué ».

**C4. Le site admin utilise des statuts qui n'existent pas** — `asoukaa-dashboard/src/lib/{orders,reviews,refunds,commissions,agents}/types.ts` *(vérifié)*
Le site admin parle de `PENDING`, `APPROVED`, `PAID`… alors que le serveur renvoie `en attente`, `approuvé`, `payé`, `livré`… (seule la page Vendeurs est correcte). Conséquences :
- Commandes : badges vides, filtres qui envoient une valeur invalide, changement de statut refusé (400). Les statuts « livreur affecté » et « en transit » n'existent pas dans le site.
- Avis : la modération est refusée (400) → **aucun avis ne peut devenir visible dans l'application**.
- Remboursements et commissions : les boutons Approuver / Refuser / Marquer payée n'apparaissent jamais.
- Livreurs : dans l'onglet « Tous », Valider / Bloquer n'apparaissent jamais.
- Tableau de bord : le compteur « en cours » est toujours 0, plusieurs liens de cartes pointent vers des filtres invalides.
Correctif : un seul fichier de statuts aligné sur le serveur, partagé par toutes les pages.

**C5. Le « QR de preuve » de livraison est le numéro de commande** — `delivery/delivery.service.ts:623`, `orders/orders.service.ts:1050` *(vérifié)*
Le numéro (`ASK-2026-00123`) est visible du vendeur et du livreur, et se devine. Un livreur peut valider la remise sans le client ; un vendeur peut valider un retrait en boutique sans le client. Cela débloque les gains. Correctif : code aléatoire par commande, visible uniquement dans l'application du client, comparé en temps constant.

**C6. Une commande Mobile Money payée passe directement en « en cours » — le vendeur n'est pas prévenu** — `payments.service.ts:705`
Conséquences : la tâche de rappel à 24 h / alerte admin à 48 h que nous avons écrite **ne se déclenche jamais** (elle cherche « en attente » + payé, combinaison qui n'existe pas) ; le bouton « Confirmer » du vendeur échoue ; et `notifyNewOrder` n'est appelée nulle part, donc le vendeur ne reçoit aucune notification de nouvelle commande. Si une commande est annulée par l'admin pendant que le client valide, elle repasse en « en cours » (pas de contrôle du statut). Décision à prendre : garder « en cours » automatique (alors supprimer le rappel et ajouter la notification) ou imposer la confirmation vendeur (alors changer `confirmPayment`).

**C7. Aucune migration ne crée le schéma initial** — `backend/src/database/migrations/` *(vérifié)*
La première migration crée un index sur `products` ; aucune ne crée `users`, `orders`, `products`, etc. Sur une base vierge (nouveau serveur, reprise après panne), `migration:run` échoue et le serveur ne démarre pas. La production actuelle n'est pas touchée si sa base existe déjà. Correctif : générer une migration de base à partir d'un `pg_dump --schema-only` de ta base actuelle.

---

## 2. ÉLEVÉE

### Argent et commandes
- **E1. Double retrait simultané** — `vendor-withdrawals.service.ts:204`. Pas de transaction. Une migration crée bien un index unique « une seule demande en attente », mais `DB_SYNCHRONIZE=true` dans ton `.env` de développement le supprime au démarrage. Aucun contrôle que le vendeur est « approuvé » à la création. Le numéro Mobile Money du retrait est libre à chaque demande (risque après vol de compte).
- **E2. Paiement débité mais stock insuffisant** — `payments.service.ts:730`. Exception levée alors que le client est débité, sans remboursement automatique. Panier groupé : les commandes sœurs sont confirmées une par une, sans transaction globale.
- **E3. Commandes bloquées sans issue** — `orders.service.ts:1589`. Depuis « livreur affecté », « expédié » et « en transit », aucune annulation possible ; une livraison échouée laisse la commande « en transit » à vie avec l'argent bloqué ; les litiges ne sont jamais clos (aucune route admin).
- **E4. `cash_on_delivery` et `card` acceptés par le serveur** — `initiate-payment.dto.ts`. Le flux n'est pas géré : pas de stock décrémenté, pas de commission, aucun encaissement tracé. Correctif : n'accepter que Mobile Money pour l'instant.
- **E5. Produit ou variante désactivé encore commandable** — `orders.service.ts:159`. Le panier ne vérifie qu'à l'ajout. `createVendorInitiated` ne vérifie ni activité ni boutique visible.
- **E6. Coupon d'un vendeur utilisable chez un autre** — `orders.service.ts:1629`. `coupon.vendorId` n'est jamais lu ; la remise réduit le gain d'une boutique qui n'a rien offert. Le coupon est « consommé » à la création de la commande et jamais rendu si elle n'est pas payée ; aucune tâche n'annule les commandes impayées.
- **E7. Deux livreurs acceptent la même course express** — `delivery.service.ts:809`. Le dernier écrase le premier. Le livreur peut aussi remettre n'importe quel statut et gonfler son compteur de livraisons.
- **E8. Frais de livraison** : à 0 si la commune est inconnue (accents non normalisés, `Ségbana` ≠ `Segbana`) ; multipliés par le nombre de boutiques d'un panier alors que l'application n'en montre qu'un ; le mode de transport (bus/taxi) n'est pas validé contre la commune.

### Sécurité du serveur
- **E9. `POST /coupons/validate` sans validation** — `coupons.controller.ts:96` *(vérifié)*. Corps typé « en ligne » donc non validé : un client qui envoie `{}` reçoit un coupon actif au hasard, code compris. Il peut énumérer tous les codes.
- **E10. Jetons non révoqués après changement ou réinitialisation de mot de passe** — `auth.service.ts:306`, `users.service.ts:189`. Un compte volé reste exploitable jusqu'à 24 h. Le mécanisme (`tokensValidAfter`) existe déjà, il suffit de l'appeler.
- **E11. Les vendeurs peuvent chercher dans tous les clients** — `orders.service.ts:399-488`. Recherche par téléphone / e-mail / nom dès 3 caractères, adresses de n'importe quel client. Limité à 15 requêtes/minute, mais cela permet de moissonner un annuaire.
- **E12. Contrôle « URL issue de notre stockage » oublié** sur logo/bannière de boutique, images de chat, documents et selfies vendeurs, images de variantes, partenaires. Une URL externe peut être affichée chez d'autres utilisateurs.
- **E13. Upload sans limite côté serveur** — `upload.controller.ts:64`. Le fichier entier est lu en mémoire avant le contrôle des 5 Mo ; les vidéos n'ont pas de contrôle des octets réels ; pas de quota par utilisateur.
- **E14. Un vendeur bloqué garde l'accès** à la modification de ses produits, au changement de statut de commande et aux preuves : seul le rôle est testé, jamais son statut.
- **E15. Route des fichiers privés** `GET /upload/file/:type/:filename` : n'importe quel compte connecté qui connaît le nom (UUID) lit un document ou selfie. *(déjà connu)*

### Configuration et déploiement
- **E16. `ENCRYPTION_KEY` invalide dans ton `.env`** : 60 caractères au lieu de 64. Résultat : l'enregistrement des coordonnées de paiement d'un vendeur donne une erreur 500. À vérifier sur le `.env` de production.
- **E17. Index de performance** déclarés dans les entités mais créés par aucune migration, et plusieurs index utiles absents (`products(status, createdAt)`, `products(vendorId)`, `messages(conversationId, createdAt)`, `vendor_profiles(status)`). Les pages publiques (produits, vitrine, annuaire) feront des lectures complètes de table avec le volume.
- **E18. `DB_SYNCHRONIZE=true`** dans le `.env` de développement : supprime au démarrage les index créés seulement par migration (dont celui qui protège des doubles retraits).

### Application mobile
- **E19. Le jeton de rafraîchissement n'est jamais utilisé** : après 24 h le tableau de bord vendeur / livreur / client s'affiche vide (« 0 commande ») sans retour à la connexion. Le serveur n'a d'ailleurs pas de route `/auth/refresh`.
- **E20. Notifications locales jamais démarrées après connexion** : seulement au démarrage à froid. De plus, le serveur ignore le paramètre `since` : toutes les 30 secondes, les 10 dernières notifications sont réaffichées (spam). L'application lit `notificationType` alors que le serveur envoie `type`. Toucher une notification de commande ne mène nulle part. Pas de vrai push (Firebase) pour l'instant.
- **E21. Chat : en cas d'erreur à la création d'une conversation, l'application ouvre la dernière conversation existante** (autre vendeur) et le message y part.
- **E22. L'écran « adresse du serveur » est accessible en production** (appui long sur le logo). Il accepte n'importe quel tunnel `trycloudflare.com` ou `ngrok` : un escroc peut envoyer « colle cette adresse » et récupérer identifiants, OTP et numéros Mobile Money.
- **E23. Panier jamais vidé après un paiement réussi** : le client retrouve ses articles et peut payer deux fois. Chaque nouveau clic sur « Commander » recrée des commandes en double.
- **E24. Code promo validé mais jamais envoyé à la commande** (`couponCode` omis) : le total affiché diffère du total facturé.
- **E25. Numéro de téléphone avec espaces refusé par le serveur**, alors que l'application affiche l'exemple « +229 97 000 000 ». Même défaut au paiement et à l'adresse de livraison.
- **E26. Liste de souhaits : le bouton « Ajouter au panier » est toujours désactivé** (le serveur ne renvoie ni stock ni variante).
- **E27. Décimaux reçus en texte puis lus comme nombres** : note moyenne produit à 0, et sur le profil livreur le chargement s'interrompt (interrupteur « disponible » désynchronisé).
- **E28. Photos et vidéos de produit envoyées sans type de fichier** — `publier_produit_screen.dart:476, 577`. Si Dio envoie `application/octet-stream` (comportement par défaut selon les relecteurs), le serveur refuse tout : **à tester en publiant un produit avec photo**. Si ça marche chez toi, ne touche à rien.

### Site admin
- **E29. Pagination cassée** (Commissions : seules 20 lignes visibles ; Admins : « undefined administrateur ») : le serveur renvoie `{ data, pagination }`, le site lit `total` / `pages` à la racine. Même piège à prévoir pour les futures pages retraits et gains livreurs.
- **E30. Statistiques de commissions** : mauvaise forme de réponse, les 3 cartes affichent 0.
- **E31. Création d'un admin impossible** : le site envoie `ADMIN` / `SUPERADMIN`, le serveur attend `admin` / `superadmin` ; dans la liste, tout le monde s'affiche « Admin ».
- **E32. Le lien d'invitation admin mène à une page qui n'existe pas** (`/set-password`) : un admin invité ne peut jamais activer son compte.
- **E33. Boucle de redirection possible après 1 jour** : le cookie vit 7 jours mais le jeton 1 jour. À tester.
- **E34. « Top produits / vendeurs » probablement en erreur 400** (paramètre `limit` non prévu côté serveur). *(à tester)*
- **E35. Page Remboursements en erreur 500 probable** : le serveur trie sur `refund.requestedAt`, colonne inexistante (`dateDemande`) — `payments.service.ts:1105` *(vérifié)*.
- **E36. Journal d'activité** : filtres invalides, tous les résultats affichés « Erreur », colonnes description / métadonnées toujours vides.
- **E37. Page Livreurs : plantage** dès qu'un livreur a des livraisons (`noteMoyenne.toFixed` sur du texte). **Page Avis** : nom du produit vide, et la recherche plante (`product.name` au lieu de `prod_name`).
- **E38. Pièces d'identité, selfies et photos invisibles pour l'admin qui valide** *(déjà connu, à traiter)*.

---

## 3. MOYENNE

**Serveur — logique** : le client peut se marquer « livré » dès que la commande est « en cours » ; le prix recalculé au paiement peut différer de celui affiché (sans alerte) ; aucune expiration des commandes impayées ; création des fiches de livraison hors transaction (doublons au nouvel essai) ; gain du livreur créé dans un bloc qui avale l'erreur ; un livreur peut être affecté à deux livraisons ; tâche d'auto-confirmation bus/taxi non sûre avec 2 instances ; montant de groupe non arrondi envoyé à FeexPay ; stock vendeur écrasé par une édition concurrente ; tableau de bord vendeur : « net » = total moins une commission toujours à 0.

**Serveur — sécurité** : `POST /products/:id/images` sans validation du corps (URL libre, `javascript:` possible) ; journaux de production trop bavards (corps brut FeexPay, numéros) ; adresse IP lue dans `X-Forwarded-For` falsifiable (peut faire échouer silencieusement le journal d'audit) ; énumération de comptes à l'inscription, au renvoi d'OTP et à la connexion ; anti-force-brute seulement par IP (partagée derrière un opérateur) ; `GET /delivery-agents/available` ouvert à tout compte connecté.

**Base de données** : `.env.example` incomplet (noms divergents : `MAIL_PASS` vs `MAIL_PASSWORD`, 13 clés manquantes) ; le journal d'activité avale l'échec d'enregistrement (valeur d'enum absente → trace perdue sans erreur) ; écarts entité / migration (type de `processedById`, noms d'index) ; fuseau horaire fragile (minuit pris en UTC par le tableau de bord, coupons qui expirent à 01 h locale, regroupement par jour UTC) → ajouter `TZ=Africa/Lagos` ; aucune suppression de compte (exigée par les stores d'applications) ; suppression de catégorie sans contrôle des produits ; purge des journaux après un an (perte de la piste d'audit financière).

**Application** : sondage du chat toutes les 5 s sans pause en arrière-plan et défilement forcé vers le bas ; permission `ACCESS_BACKGROUND_LOCATION` déclarée mais inutilisée (risque de refus par les stores) ; dates affichées en UTC dans plusieurs écrans (décalage d'une heure) ; l'expiration de session ne réinitialise pas tout (notifications, pastilles) ; abonnements de connectivité jamais annulés (plantages « setState après fermeture ») ; erreurs avalées : tableau de bord vendeur « 0 produit » quand le serveur est injoignable, actions admin sans retour ; liens profonds sans contrôle de rôle ; reprise après échec de paiement ; formatage des prix dupliqué ~15 fois et total calculé sur le téléphone.

**Site admin** : `?redirect=` sans contrôle (ouverture de `javascript:` ou site externe après connexion) ; aucun en-tête de sécurité (clickjacking possible) ; la déconnexion ne révoque pas le jeton ; toutes les requêtes partent de la même IP (limite de 5 connexions/minute partagée par tous les admins) ; aucune gestion centrale des erreurs 401 ni pages d'erreur ; actions financières sans confirmation (Marquer payée, Suspendre un vendeur, Bloquer) ; motif de refus de remboursement envoyé mais ignoré par le serveur ; page Messages signalés sans noms, sans images, sans action de modération ; recherche limitée aux 20 lignes affichées.

---

## 4. FAIBLE

- Serveur : 162 fichiers `*.bak*` dans `src`, dossiers `_to_delete/`, `.env.bak_feexpay*` contenant des clés (exclus de git mais à supprimer) ; `console.error` restants ; `AppController` mort ; `reviews.create` plante si un produit n'a aucune variante ; numéros Mobile Money des retraits non chiffrés ; refresh token émis mais jamais accepté ; énumération de type de véhicule en majuscules côté application ; faute de frappe `rejetté` dans le statut de remboursement ; enum de statuts de commande en doublon, mort.
- Application : `allowBackup` non désactivé ; build « release » signé avec la clé de debug si pas de keystore ; clé FeexPay en clair dans `run_sandbox.bat` et `lancer_wifi.bat` (hors dépôt git — remplacer si c'est une clé réelle) ; dépendance `feexpay_flutter` inutilisée ; messages techniques affichés à l'utilisateur ; textes d'erreur en anglais ; taille de police système ignorée ; images de secours tierces codées en dur.
- Site admin : liens morts du classement (`/dashboard/products/:id`, `/dashboard/vendors/:id`) ; `middleware.ts` déprécié en Next 16 ; `.env.local.example` faux (port, `/api/v1`) ; dates formatées sans fuseau (risque d'écart d'hydratation) ; devise écrite « F CFA », « FCFA » et « Fcfa ».

---

## 5. COMPLÉMENTARITÉ — ce qui existe d'un côté et manque de l'autre

**Pages admin manquantes alors que le serveur est prêt** : Retraits vendeurs (argent à verser, avec le minimum de retrait par vendeur), Paiements des livreurs (les gains restent « en attente » indéfiniment), Paiements / transactions, Livraisons, Alertes de sécurité utilisateur (« Ce n'est pas moi »), modération des produits, fiches détail (vendeur, utilisateur, commande). Absents des deux côtés : paramètres généraux, exports, rapports.

**Fonctions de l'application sans route serveur (erreur 404 garantie)** : course express (`/delivery-requests`), import assisté (`/import-products`, `/import-requests`, `/uploads/image`), presque tout l'écran admin intégré à l'application (`/admin/users`, `/admin/orders`, `/admin/banners`…), et l'application ne se connecte jamais comme admin (`/auth/admin/login`). À décider : retirer ces écrans ou construire les modules serveur.

**Notifications** : le serveur ne crée en pratique que les types commande (relances), livraison, chat et ticket. Jamais créés : paiement, avis, stock, validation, système. Retrait payé ou rejeté : ni e-mail ni notification. Décision vendeur / livreur : e-mail seulement. Signalement de message : aucun retour à celui qui signale, l'admin ne peut ni masquer ni bloquer. Compte suspendu en cours de session : déconnexion sans explication. Le client ne reçoit pas de notification dans l'application pour l'état de sa commande (e-mails seulement).

**Règles dupliquées qui divergent** : mot de passe (le serveur exige une minuscule, l'application non ; le site admin ne vérifie que 8 caractères) ; téléphone (espaces) ; 3 photos d'échantillon côté application contre 5 maximum côté serveur ; seuil de livraison gratuite de 50 000 écrit en dur dans l'application.

**Cohérent et vérifié** : tickets de support (statuts, catégories, limites, référence `TCK-`), statuts de commande côté application, statuts vendeur et livreur côté application et page Vendeurs, rôles, types d'upload, types de rayons de vitrine, chat (envoi, notification, signalement), préférences de notification, changement d'e-mail, mot de passe oublié.

---

## 6. Points sains vérifiés

Prix, totaux et commissions calculés côté serveur (le client n'envoie ni prix ni total) ; numéro de commande par séquence PostgreSQL ; stock décrémenté sous verrou en transaction ; coupon à usage unique par client ; contrôles de propriétaire sur commandes, adresses, panier, notifications, paiements, remboursements, avis, tickets, conversations, preuves ; aucune injection SQL trouvée ; mots de passe bcrypt (12 tours), OTP hachés, expirés et limités ; chiffrement AES-256-GCM ; en-têtes (helmet), CORS strict, Swagger fermé et `ValidationPipe` strict en production ; e-mails protégés contre l'injection ; stockage des jetons dans l'espace sécurisé du téléphone ; aucun jeton ni mot de passe dans les journaux de l'application ; HTTP en clair interdit sur Android ; aucun `dangerouslySetInnerHTML` sur le site admin ; cookie admin `httpOnly` / `secure` / `sameSite` ; route d'envoi du site admin bien protégée.

---

## 7. Plan de correction proposé (par lots)

| Lot | Contenu | Pourquoi d'abord |
|---|---|---|
| A — Argent | C1 commission, C2 remboursement, E1 retrait, E4 modes de paiement, C6 décision « en cours », notification nouvelle commande | Perte d'argent directe |
| B — Paiements Mobile Money | C3 webhook + rattrapage, annulation, E2, E23 panier vidé | Clients débités sans commande |
| C — Site admin | C4 statuts, E29–E37, pages Retraits vendeurs et Paiements livreurs, `/set-password` | Le site est inutilisable pour plusieurs métiers |
| D — Sécurité rapide | C5 code de remise, E9 coupons, E10 jetons, E12–E14 fichiers et vendeurs bloqués, E22 adresse du serveur | Petits changements, gros gain |
| E — Application | E19 session, E20 notifications, E21 chat, E24–E27, E28 si le test échoue | Expérience des utilisateurs |
| F — Déploiement | C7 migration de base, index, `.env.example`, `ENCRYPTION_KEY`, `TZ`, nettoyage des `.bak` | Avant l'installation sur un vrai serveur |

## 8. Décisions qui t'appartiennent

1. **Frais de livraison** : le vendeur touche-t-il une part ? (je recommande non : commission sur les produits seulement, frais de livraison pour la plateforme et le livreur).
2. **Commande payée par Mobile Money** : passage direct en « en cours », ou le vendeur doit-il confirmer ?
3. **Remboursements** : délai maximum après livraison ? Remboursement versé à la main ou via FeexPay ? Le gain du vendeur est repris ?
4. **Paiement à la livraison / carte** : on les ferme pour l'instant ?
5. **Course express, import assisté, écran admin dans l'application** : on les construit, on les cache, ou on les retire ?
6. **Suppression de compte** (exigence des stores) : on l'ajoute ?
7. **Application admin** : l'administration se fait uniquement sur le site, donc on retire l'écran admin de l'application ?

## 9. Qui a fait quoi

| Relecteur | Périmètre | Constats principaux |
|---|---|---|
| 1 | Sécurité du serveur | QR prévisible, coupons, jetons, URL d'upload, limites d'upload, vendeurs bloqués |
| 2 | Logique métier du serveur | Commission, remboursement, retrait, webhook, commandes bloquées, coupons, concurrence |
| 3 | Structure et base de données | Migration de base absente, index, `.env`, fuseau horaire, compilation OK |
| 4 | Contrat application ↔ serveur | ~224 appels analysés, 24 problèmes : upload, paiement annulé, panier, coupon, téléphone, routes inexistantes |
| 5 | Application mobile | Session, notifications, chat, adresse du serveur, permissions, fuites |
| 6 | Site admin | Statuts, pagination, création d'admin, redirections, pages manquantes, compilation OK |
| 7 | Complémentarité | Matrice des statuts, ruptures de parcours, fonctions orphelines, notifications |

Les relecteurs 1, 2, 3, 5 n'ont pas pu exécuter l'application ni se connecter à la base ; leurs points « à vérifier » nécessitent un test réel.
