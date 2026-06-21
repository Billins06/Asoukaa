# 🌱 Database Seeders - Résumé Complet

**Date**: 2026-06-12  
**Status**: ✅ Prêt à utiliser

---

## 📋 Contenu des Seeders

### 1️⃣ Admin Accounts (3)
```
Superadmin:
  Email: superadmin@asoukaa.com
  Password: Admin1234!
  Role: SUPERADMIN

Admin 1:
  Email: admin@asoukaa.com
  Password: Admin1234!
  Role: ADMIN

Admin 2:
  Email: manager@asoukaa.com
  Password: Admin1234!
  Role: ADMIN
```

### 2️⃣ Users (8 total)

**Customers (5)**:
- alice@test.com
- bob@test.com
- carol@test.com
- david@test.com
- emma@test.com

**Vendors (3)**:
- vendor1@test.com
- vendor2@test.com
- vendor3@test.com

Password (all): `User1234!`

### 3️⃣ Vendor Profiles (3)
Chaque vendor a une boutique approuvée avec:
- ✅ Shop name unique
- ✅ Shop description
- ✅ Documents (mock URLs)
- ✅ Status: APPROVED
- ✅ Payment method configured

### 4️⃣ Categories (8)
1. Électronique
2. Mode
3. Maison
4. Beauté
5. Sports
6. Alimentation
7. Livres
8. Jouets

### 5️⃣ Products (10)
Produits distribuées entre les vendors:
- Laptop Pro 15 ($1,299.99)
- Smartphone X ($899.99)
- T-Shirt Cotton ($29.99)
- Jeans Classic ($79.99)
- Coffee Maker ($59.99)
- Wall Clock ($39.99)
- Face Cream ($49.99)
- Yoga Mat ($39.99)
- Organic Coffee ($12.99)
- JavaScript Book ($39.99)

Tous les produits sont en status **ACTIVE**.

### 6️⃣ Orders (3)
- 3 commandes complétées
- 1 par customer
- Chacune contient 2 items
- Avec prix total, frais de port, taxes

---

## 🚀 Comment Utiliser

### Prérequis
- ✅ Base de données créée (avec migrations appliquées)
- ✅ `.env` configuré avec `DB_*` variables
- ✅ Application démarrée une fois (pour initialiser le DataSource)

### Commande de Seeding

```bash
# Option 1: Commande npm
npm run seed

# Option 2: Direct ts-node
ts-node -r tsconfig-paths/register src/database/seed-runner.ts
```

### Output Attendu
```
🌱 Starting database seeding...

✅ Seeded 3 admin accounts
   Credentials: email + password: Admin1234!
✅ Seeded 8 users (5 customers + 3 vendors)
   Customer credentials: email + password: User1234!
   Vendor credentials: email + password: User1234!
✅ Seeded 3 vendor profiles
✅ Seeded 8 categories
✅ Seeded 10 products
✅ Seeded 3 orders with 6 items

✅ Database seeding completed successfully!
```

---

## 🔄 Idempotent Seeding

Chaque seeder vérifie si les données existent déjà:
```typescript
const count = await repo.count();
if (count > 0) {
  console.log('✅ Already seeded, skipping...');
  return;
}
```

✅ **Sûr de lancer plusieurs fois** - Pas de doublons créés.

---

## 🗂️ Fichiers Créés

```
src/database/
├── seed-runner.ts                    # Entry point (lancé par npm run seed)
├── SEEDING.md                        # Documentation détaillée
├── seeders/
│   ├── seed.ts                       # Orchestrateur principal
│   └── seeds/
│       ├── admin.seed.ts             # Seeders pour les admins
│       ├── user.seed.ts              # Seeders pour les users
│       ├── vendor-profile.seed.ts    # Seeders pour les boutiques
│       ├── category.seed.ts          # Seeders pour les catégories
│       ├── product.seed.ts           # Seeders pour les produits
│       └── order.seed.ts             # Seeders pour les commandes

Mise à jour:
├── package.json                      # Commande "seed" ajoutée
```

---

## 🎯 Ordre d'Exécution (Dépendances)

```
1️⃣ Admins (pas de dépendances)
   ↓
2️⃣ Users (pas de dépendances)
   ↓
3️⃣ Vendor Profiles (dépend de Users)
   ↓
4️⃣ Categories (pas de dépendances)
   ↓
5️⃣ Products (dépend de Vendors + Categories)
   ↓
6️⃣ Orders (dépend de Users + Products)
```

---

## 🧪 Cas d'Usage pour les Tests

### Frontend Integration Tests
```
✅ Teste avec utilisateurs réels (alice@test.com, etc.)
✅ Commandes pour tester les détails
✅ Produits multiples pour tester les listes
```

### Admin Dashboard Tests
```
✅ Connexion avec superadmin@asoukaa.com
✅ Voir les commandes de clients
✅ Voir les produits des vendors
```

### Vendor Dashboard Tests
```
✅ Connexion avec vendor1@test.com
✅ Voir ses 3-4 produits
✅ Voir ses commandes
```

---

## ⚠️ Troubleshooting

### Erreur: "User not found"
**Cause**: Seeders n'ont pas exécuté dans le bon ordre.  
**Solution**: Vérifier que l'ordre dans `seed.ts` est correct.

### Erreur: "Column not found"
**Cause**: Migrations n'ont pas été appliquées.  
**Solution**: 
```bash
npm run typeorm migration:run
npm run seed
```

### "Already seeded" pour tous les seeders
**Cause**: Données existent déjà.  
**Solution**: Réinitialiser la DB:
```bash
npm run typeorm migration:revert
npm run typeorm migration:run
npm run seed
```

### Connection refused
**Cause**: Base de données non disponible.  
**Solution**: Vérifier que PostgreSQL/MySQL tourne et que `.env` est correct.

---

## 📊 Vue d'Ensemble des Données

| Entity | Count | Relations |
|--------|-------|-----------|
| Admins | 3 | - |
| Users | 8 | 5 customers + 3 vendors |
| Vendor Profiles | 3 | 1:1 with Users |
| Categories | 8 | - |
| Products | 10 | Linked to vendors + categories |
| Orders | 3 | Linked to customers |
| Order Items | 6 | 2 items per order |
| **TOTAL** | **39** | **Interconnected** |

---

## ✅ Prêt pour l'Intégration

Les seeders sont maintenant prêts à:
- ✅ Remplir la base de données rapidement
- ✅ Tester les connexions front/back
- ✅ Tester les dashboards
- ✅ Générer des rapports de test
- ✅ Valider les workflows complets

**Procédure**:
1. Appliquer les migrations: `npm run typeorm migration:run`
2. Lancer les seeders: `npm run seed`
3. Tester l'API et les interfaces

---

**Créé**: 2026-06-12  
**Prêt pour production**: ✅ (utiliser des vraies données ensuite)
