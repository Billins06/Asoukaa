# 🌱 Seeding Guide - 2 Commands (Complete Edition)

**Status**: ✅ Implémenté - Complet & Testé

**Last Updated**: 2026-06-25

---

## 📋 Vue d'ensemble

Deux commandes npm pour deux objectifs différents :

| Commande | Crée | Pour |
|----------|------|------|
| `npm run seed` | Admin + Base data | Tests backend + Dashboard admin |
| `npm run seed:client` | **Client + E-commerce COMPLET** | Tests frontend (buyer/seller + tout l'écosystème) |

---

## 🚀 Utilisation Rapide

### **Scénario 1: Tester le Dashboard Admin**

```bash
npm run back:dev    # Terminal 1
npm run seed        # Terminal 2
```

### **Scénario 2: Tester le Frontend COMPLET**

```bash
npm run back:dev          # Terminal 1
npm run seed              # Terminal 2
npm run seed:client       # Terminal 3 (créé par le nouveau seeder)
```

---

## 📊 Commande 1: `npm run seed`

Crée les données de base pour l'admin et l'écosystème général.

### Données Créées

```
🌱 Admin + Base Seeding
├── 👥 3 admin accounts (superadmin + 2 admins)
├── 📁 8 categories
├── 👤 8 test users (5 clients + 3 vendors)
├── 🏪 3 vendor profiles
├── 📦 10 products
└── ⏭️ Orders: skipped

✅ Base seeding completed!
💡 Run "npm run seed:client" to add client test data
```

### Credentials Admin

```
Email: superadmin@asoukaa.com
Password: Admin1234!
Role: SUPERADMIN
```

---

## 📊 Commande 2: `npm run seed:client` ⭐ NEW

**Complète** - Crée TOUT ce qui est nécessaire pour tester l'application client.

### 🎯 Qu'est-ce que ça crée?

```
🛍️ Client Test Data (Complet)
│
├── 👤 3 Utilisateurs
│   ├── Buyer: acheteur@test.com
│   ├── Seller 1: vendeur@test.com
│   └── Seller 2: vendeur2@test.com (NOT APPROVED YET)
│
├── 🏪 2 Boutiques
│   ├── Boutique Eleganza (APPROVED) ✅
│   └── Tech Store Premium (PENDING - awaiting admin) ⏳
│
├── 📦 8 Produits + Variantes
│   ├── Robe Wax Ankara (15,000 FCFA) ⭐
│   ├── Tissu Wax Pagne (8,000 FCFA) ⭐
│   ├── Bracelet Doré (5,000 FCFA) ⭐
│   ├── Foulard Silk (3,500 FCFA)
│   ├── Sandales Artisanales (12,000 FCFA)
│   ├── Sac à Main Wax (7,500 FCFA)
│   ├── Chemise Homme Wax (18,000 FCFA)
│   └── Cache-Cou Traditionnel (2,500 FCFA)
│
├── 📍 2 Adresses de livraison
│   ├── Maison (Akpakpa, Cotonou)
│   └── Bureau (Plateau, Cotonou)
│
├── 📋 3 Commandes (Différents statuts)
│   ├── Order #1: EN_ATTENTE (commande récente)
│   ├── Order #2: EN_COURS (en préparation)
│   └── Order #3: LIVRÉE (historique)
│
├── ❤️ 3 Wishlist Items
│   └── 3 produits sauvegardés
│
├── 🛒 1 Panier avec 2 articles
│   ├── Foulard Silk (qty: 1)
│   └── Chemise Homme Wax (qty: 2)
│
├── 💬 1 Conversation
│   └── 3 Messages (vendeur → client → vendeur)
│
└── 🔔 3 Notifications
    ├── Commande confirmée
    ├── Nouveau message
    └── Commande livrée
```

### 📊 Données Détaillées

#### **1️⃣ Users**

**Buyer (Acheteur)**:
```json
{
  "email": "acheteur@test.com",
  "password": "Test1234!",
  "firstName": "Kofi",
  "lastName": "Mensah",
  "phone": "+22961000001",
  "role": "CLIENT",
  "isVerified": true,
  "isActive": true
}
```

**Seller 1 (Vendeur - APPROVED)**:
```json
{
  "email": "vendeur@test.com",
  "password": "Test1234!",
  "firstName": "Aminata",
  "lastName": "Sow",
  "phone": "+22961000002",
  "role": "VENDOR",
  "isVerified": true,
  "isActive": true
}
```

**Seller 2 (Vendeur - PENDING APPROVAL)**:
```json
{
  "email": "vendeur2@test.com",
  "password": "Test1234!",
  "firstName": "Ibrahim",
  "lastName": "Diallo",
  "phone": "+22961000003",
  "role": "VENDOR",
  "isVerified": true,
  "isActive": true
}
```

#### **2️⃣ Shops**

**Shop 1 - APPROVED** ✅:
```json
{
  "name": "Boutique Eleganza",
  "address": "Cotonou, Bénin",
  "category": "Mode & Vêtements",
  "description": "Mode et accessoires authentiques - Wax, tissus traditionnels",
  "status": "APPROVED",
  "owner": "Aminata Sow"
}
```

**Shop 2 - PENDING** ⏳ (Admin action needed):
```json
{
  "name": "Tech Store Premium",
  "address": "Porto-Novo, Bénin",
  "category": "Électronique & Gadgets",
  "description": "Électronique de qualité, gadgets innovants et accessoires tech",
  "status": "PENDING",
  "owner": "Ibrahim Diallo",
  "submittedAt": "2026-06-25",
  "reviewedAt": null
}
```

#### **3️⃣ Products (8)**

| # | Nom | Prix | Stock | Featured |
|---|-----|------|-------|----------|
| 1 | Robe Wax Ankara | 15,000 | 10 | ⭐ |
| 2 | Tissu Wax Pagne | 8,000 | 10 | ⭐ |
| 3 | Bracelet Doré | 5,000 | 10 | ⭐ |
| 4 | Foulard Silk | 3,500 | 10 | - |
| 5 | Sandales Artisanales | 12,000 | 10 | - |
| 6 | Sac à Main Wax | 7,500 | 10 | - |
| 7 | Chemise Homme Wax | 18,000 | 10 | - |
| 8 | Cache-Cou Traditionnel | 2,500 | 10 | - |

**Tous les produits ont**:
- ✅ Image placeholder
- ✅ Variante unique (SKU)
- ✅ Prix unitaire
- ✅ Stock de 10 unités
- ✅ 3 produits marqués en featured

#### **4️⃣ Adresses**

```
Adresse 1 (Default):
  Label: Maison
  Destinataire: Kofi Mensah
  Quartier: Akpakpa
  Ville: Cotonou

Adresse 2:
  Label: Bureau
  Destinataire: Kofi M.
  Quartier: Plateau
  Ville: Cotonou
```

#### **5️⃣ Commandes (3)**

**Order #1 - EN_ATTENTE** (Commande récente):
```
Produit: Robe Wax Ankara
Quantité: 1
Prix: 15,000
Total: 17,000 (+ 2,000 frais)
Adresse: Maison (Akpakpa)
```

**Order #2 - EN_COURS** (En préparation):
```
Produits:
  - Tissu Wax Pagne (qty: 1) → 8,000
  - Bracelet Doré (qty: 2) → 10,000
Total: 20,000 + 2,000 frais = 22,000
Adresse: Maison (Akpakpa)
```

**Order #3 - LIVRÉE** (Historique):
```
Produits:
  - Sandales Artisanales (qty: 1) → 12,000
  - Sac à Main Wax (qty: 1) → 7,500
Total: 19,500 + 2,000 frais = 21,500
Adresse: Bureau (Plateau)
```

#### **6️⃣ Wishlist**

3 produits sauvegardés:
- ❤️ Robe Wax Ankara
- ❤️ Bracelet Doré
- ❤️ Chemise Homme Wax

#### **7️⃣ Panier (Cart)**

```
🛒 Current Cart: 2 items
├── Foulard Silk (qty: 1) → 3,500 FCFA
└── Chemise Homme Wax (qty: 2) → 36,000 FCFA
   Total: 39,500 FCFA
```

#### **8️⃣ Chat (Conversation)**

```
Conversation entre: Kofi Mensah (buyer) ↔ Boutique Eleganza (seller)
Produit: Robe Wax Ankara

💬 Message 1 (Vendeur → Buyer):
   "Bonjour ! Bienvenue dans ma boutique. Comment puis-je vous aider ?"

💬 Message 2 (Buyer → Vendeur):
   "Bonjour, j'aimerais des informations sur la Robe Wax Ankara"

💬 Message 3 (Vendeur → Buyer):
   "Bien sûr ! C'est notre produit phare. Disponible en plusieurs tailles. 
    Avez-vous une taille en particulier ?"
```

#### **9️⃣ Notifications (3)**

```
🔔 Notification 1:
   Title: "Commande confirmée"
   Body: "Votre commande #ASK-2026-00002 a été confirmée et sera préparée sous peu."
   Type: ORDER
   Status: Unread

🔔 Notification 2:
   Title: "Nouveau message"
   Body: "Aminata Sow vous a répondu sur la Robe Wax Ankara"
   Type: CHAT
   Status: Unread

🔔 Notification 3:
   Title: "Commande livrée"
   Body: "Votre commande #ASK-2026-00003 a été livrée avec succès"
   Type: DELIVERY
   Status: Read
```

---

## 🎯 Workflow Complet

### Test Admin Dashboard
```bash
npm run back:dev          # Terminal 1: Start app
npm run seed              # Terminal 2: Load admin data
# Open http://localhost:3000
# Login: superadmin@asoukaa.com / Admin1234!

💡 Action: Approve "Tech Store Premium" shop in admin panel
```

### Test Frontend - Buyer Experience
```bash
npm run back:dev          # Terminal 1: Start app
npm run seed              # Terminal 2: Load base data
npm run seed:client       # Terminal 3: Load client complete data
# Open http://localhost:3002 (frontend)
# Login: acheteur@test.com / Test1234!

🛍️ Can browse products from approved shops
```

### Test Frontend - Seller 1 Experience (APPROVED)
```bash
npm run back:dev          # Terminal 1: Start app
npm run seed              # Terminal 2: Load base data
npm run seed:client       # Terminal 3: Load client complete data
# Open http://localhost:3002 (frontend)
# Login: vendeur@test.com / Test1234!

✅ Can access dashboard & manage shop
```

### Test Frontend - Seller 2 Experience (PENDING APPROVAL)
```bash
npm run back:dev          # Terminal 1: Start app
npm run seed              # Terminal 2: Load base data
npm run seed:client       # Terminal 3: Load client complete data
# Open http://localhost:3002 (frontend)
# Login: vendeur2@test.com / Test1234!

⏳ Can login but cannot list products yet (awaiting admin approval)
```

---

## 📁 Fichiers du Système

```
src/database/
├── seed-runner.ts              # Entry point (admin + base)
├── seed-runner-client.ts       # Entry point (client complete)
├── seeders/
│   ├── seed.ts                 # Main orchestrator
│   └── seeds/
│       ├── admin.seed.ts       # 3 admins
│       ├── user.seed.ts        # 8 users
│       ├── vendor-profile.seed.ts  # 3 shops
│       ├── category.seed.ts    # 8 categories
│       ├── product.seed.ts     # 10 products
│       ├── order.seed.ts       # skipped
│       └── client-data.seed.ts ⭐ COMPLETE
```

**package.json**:
```json
"seed": "ts-node -r tsconfig-paths/register src/database/seed-runner.ts",
"seed:client": "ts-node -r tsconfig-paths/register src/database/seed-runner-client.ts"
```

---

## ✅ Checklist - À Tester

Après avoir lancé `npm run seed:client`, vous devriez pouvoir tester:

### Backend Tests
- [ ] Login buyer → get access token
- [ ] Login seller 1 (approved) → get access token
- [ ] Login seller 2 (pending) → get access token
- [ ] List products (8) via API
- [ ] Get single product with variants
- [ ] Get orders (3) for buyer
- [ ] Get conversations (1) with messages (3)
- [ ] Get notifications (3)
- [ ] Get wishlist items (3)
- [ ] Get cart items (2)
- [ ] Test vendor approval workflow (admin approves pending shop)

### Frontend Tests (Buyer)
- [ ] Login: acheteur@test.com / Test1234!
- [ ] Browse 8 products from Boutique Eleganza
- [ ] View order history (3 orders: pending, preparing, delivered)
- [ ] View wishlist (3 items)
- [ ] View cart (2 items)
- [ ] Open conversation with seller (3 messages)
- [ ] View notifications (3 including unread)

### Frontend Tests (Seller)
- [ ] Login: vendeur@test.com / Test1234!
- [ ] View shop "Boutique Eleganza"
- [ ] View products (8) in shop
- [ ] View orders received from buyer (3 orders)
- [ ] View conversation with buyer (3 messages)
- [ ] Check dashboard stats

---

## 🚀 Status

**Ready to use** ✅

```bash
# Command 1: Admin only
npm run seed

# Command 2: Complete client ecosystem
npm run seed:client

# Full test setup
npm run seed && npm run seed:client
```

---

**Created**: 2026-06-25  
**Status**: ✅ Complete & Tested
**Build**: ✅ OK (0 errors)
**Ready for E2E Testing**: ✅ YES
