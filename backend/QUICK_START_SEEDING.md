# 🚀 Quick Start - Seeders et Tests

**Contexte**: Tu utilises `npm run back:dev` pour développer. Voici comment ajouter des données de test.

---

## 📋 Option 1: Seeders Seulement (Recommandé pour Dev)

### Pas d'étape 1 nécessaire
Les seeders utilisent la configuration TypeORM de l'app qui est déjà en cours d'exécution.

### Étape: Lancer les Seeders
```bash
npm run seed
```

**Résultat attendu**:
```
🌱 Starting database seeding...

✅ Seeded 3 admin accounts
✅ Seeded 8 users (5 customers + 3 vendors)
✅ Seeded 3 vendor profiles
✅ Seeded 8 categories
✅ Seeded 10 products
⏭️ Orders seeding skipped (complex structure)

✅ Database seeding completed successfully!
```

### Données Créées
- 3 admins (superadmin + 2 admins)
- 8 users (5 clients + 3 vendors)
- 3 boutiques de vendors
- 8 catégories
- 10 produits
- **Total: ~32 enregistrements**

---

## 🔐 Credentials Après Seeding

### Admin Dashboard
```
Email: superadmin@asoukaa.com
Password: Admin1234!
```

### Customer App
```
Email: alice@test.com
Password: User1234!
```

### Vendor Dashboard
```
Email: vendor1@test.com
Password: User1234!
```

---

## ✅ Après les Seeders

### 1. Démarrer l'app (si pas déjà fait)
```bash
npm run back:dev
```

### 2. Tester les Connexions

**Tester Admin Login**:
```bash
curl -X POST http://localhost:3000/api/v1/auth/admin/login \
  -H "Content-Type: application/json" \
  -d '{"identifier":"superadmin@asoukaa.com","password":"Admin1234!"}'
```

**Tester Customer Login**:
```bash
curl -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"identifier":"alice@test.com","password":"User1234!"}'
```

### 3. Tester le Debug Token
```bash
# D'abord, récupère un token avec login
TOKEN=$(curl -s -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"identifier":"alice@test.com","password":"User1234!"}' | jq -r '.accessToken')

# Ensuite, teste le debug
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:3000/api/v1/auth/debug-token
```

**Résultat attendu**:
```json
{
  "headerFound": true,
  "tokenFound": true,
  "tokenLength": 150,
  "parts": 3,
  "isValid": true,
  "parts_lengths": [27, 100, 43]
}
```

---

## 🔄 Réinitialiser et Re-seeder

Si tu veux nettoyer et refaire:

```bash
# 1. Tuer l'app (Ctrl+C)

# 2. Supprimer tous les data (option A - via adminer/pgadmin)
# OU option B - via SQL:
# DELETE FROM typeorm_migrations;
# DELETE FROM order_items;
# DELETE FROM orders;
# DELETE FROM products;
# ... etc

# 3. Relancer l'app
npm run back:dev

# 4. Relancer les seeders
npm run seed
```

**Ou plus simple - via psql**:
```bash
# Drops et recreate la DB
psql -U postgres -h localhost -c "DROP DATABASE asoukaa;"
psql -U postgres -h localhost -c "CREATE DATABASE asoukaa;"

# Puis:
npm run back:dev &  # Démarrer en background
npm run seed        # Seeder immédiatement
```

---

## 📊 Vérifier les Données

### Via Adminer / pgAdmin
Ouvre ton interface de gestion de DB et vérifie:
- `users`: 8 enregistrements
- `admin_accounts`: 3 enregistrements
- `vendor_profiles`: 3 enregistrements
- `categories`: 8 enregistrements
- `products`: 10 enregistrements

### Via API
```bash
# Récupère un token
TOKEN=$(curl -s -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{"identifier":"alice@test.com","password":"User1234!"}' | jq -r '.accessToken')

# Consulte les produits (exemple)
curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:3000/api/v1/products
```

---

## 🧪 Tests Recommandés

### 1. Test Front → Back Liaison
- Login avec alice@test.com
- Voir la liste des produits
- Ajouter un produit au panier

### 2. Test Dashboard Admin
- Login avec superadmin@asoukaa.com
- Voir les commandes (ordres)
- Voir les utilisateurs

### 3. Test Vendor Dashboard
- Login avec vendor1@test.com
- Voir ses produits
- Voir ses statistiques

---

## ⚠️ Notes Importantes

### Seeders Idempotents
```typescript
// Chaque seeder vérifie avant d'insérer
const count = await repo.count();
if (count > 0) {
  console.log('✅ Already seeded, skipping...');
  return;
}
```

**Cela signifie**: Tu peux lancer `npm run seed` plusieurs fois sans créer de doublons.

### Commandes TypeORM (Pour Plus Tard)
```bash
# Voir les migrations disponibles
npm run typeorm migration:show -- -d src/database/data-source.ts

# Exécuter les migrations
npm run typeorm:run

# Revenir en arrière
npm run typeorm:revert

# Générer une nouvelle migration
npm run typeorm:generate -- -d src/database/data-source.ts -n CreateUsers
```

---

## 🛠️ Troubleshooting

### Erreur: "Database does not exist"
```bash
# Crée la DB
psql -U postgres -h localhost -c "CREATE DATABASE asoukaa;"

# Puis relance
npm run back:dev &
npm run seed
```

### Erreur: "connect ECONNREFUSED"
PostgreSQL n'est pas en cours d'exécution.
```bash
# Démarrer PostgreSQL (Windows)
pg_ctl -D "C:\Program Files\PostgreSQL\15\data" start

# Ou (Docker)
docker-compose up -d postgres
```

### Erreur: "Unknown database"
Les variables d'environnement `.env` ne sont pas chargées.
- Vérifie que `.env` existe dans le root du projet
- Contient: `DB_HOST`, `DB_PORT`, `DB_USER`, `DB_PASSWORD`, `DB_NAME`

### Orders Seeders Skipped
Orders nécessitent des Addresses et d'autres dépendances complexes.
- À faire manuellement ou via l'API si nécessaire

---

## ✅ Checklist Finale

- [ ] `.env` configuré avec `DB_*`
- [ ] PostgreSQL en cours d'exécution
- [ ] `npm run back:dev` lancé et fonctionnel
- [ ] `npm run seed` exécuté avec succès
- [ ] Credentials testés (login admin + customer)
- [ ] Debug token testé
- [ ] Prêt pour les tests d'intégration front/back

---

**Ready to test!** 🚀
