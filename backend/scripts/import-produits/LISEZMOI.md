# Import des catégories et des produits (Boutique Annette / Honoré Shop)

À lancer sur TON PC (là où se trouve ta base de données), dans le dossier `backend`.

## Étape 1 — Les catégories (une seule fois)
1. Relis `LISTE_CATEGORIES_PROPOSEES.md` (293 catégories ; « existe déjà » = rien à faire).
2. Lance :  `npm run seed:categories`  (attention : `npm`, pas `pm`).

## Étape 2 — Vérifier sans rien créer (simulation)
Démarre le serveur (`npm run start:dev`) dans un 1er terminal, puis dans un 2e :

    node scripts/import-produits/import-produits.js --shop "Boutique Annette" --dry-run
    node scripts/import-produits/import-produits.js --shop "Honoré Shop" --dry-run

Tu vois la liste, les prix, le stock, les paliers et le nombre de photos. Aucun mot de passe demandé.

## Étape 3 — L'import réel (une fois par boutique)
    node scripts/import-produits/import-produits.js --shop "Boutique Annette"

Le script te demande l'e-mail/téléphone puis le mot de passe du compte VENDEUR de cette boutique
(la boutique doit être APPROUVÉE). Puis il fait tout seul : création → photos → stock → prix dégressifs → publication.
Refais la même chose avec `--shop "Honoré Shop"` et l'autre compte.

## Bon à savoir
- Le serveur peut limiter les photos (60 par heure par défaut) : si c'est le cas le script attend tout seul. Vitesse normale : 3 produits en parallèle, environ 80 requêtes par minute (limite du serveur : 100), soit 3 à 5 minutes pour 37 produits.
- Si le script s'arrête (coupure, Ctrl+C, quota), relance-le tel quel : les produits publiés sont ignorés et ceux restés en brouillon vides sont complétés, sans doublon.
- Le fichier `PRODUITS_A_IMPORTER.csv` se modifie avec Excel (séparateur « ; ») : prix, stock, paliers, boutique, catégorie.
- Le script vise `http://localhost:3001/api/v1` (port de ton `.env`). Autre serveur ou port : `--api https://ton-domaine/api/v1`. Dossier des photos : `--images "C:\chemin\IMAGES"`.
- Les prix 10–100 F sont des prix de TEST : vérifie que MTN/Moov acceptent un si petit montant sur FeexPay.
- Les descriptions sont des brouillons courts, sans caractéristiques inventées : à compléter.
- Journal de chaque import : `import-log-<boutique>.json`.
