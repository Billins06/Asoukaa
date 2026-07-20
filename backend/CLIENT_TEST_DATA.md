# 🛍️ Client Test Data - Seeder Complet

**Date**: 2026-06-21  
**Status**: ✅ Implémenté et Prêt

---

## 📋 Vue d'ensemble

Un **seeder unifié** qui crée toutes les données nécessaires pour tester le frontend client.

### ✅ Données Créées

| Élément | Quantité | Détails |
|---------|----------|---------|
| **Buyers** | 1 | acheteur@test.com |
| **Sellers** | 1 | vendeur@test.com |
| **Shops** | 1 | Boutique Eleganza |
| **Products** | 8 | Mode, wax, accessoires |
| **Categories** | Auto | 8 catégories (créées) |
| **Orders** | ⏭️ | À ajouter en Phase 2 |
| **Wishlist** | ⏭️ | À ajouter en Phase 2 |
| **Conversations** | ⏭️ | À ajouter en Phase 2 |
| **Notifications** | ⏭️ | À ajouter en Phase 2 |

---

## 🚀 Utilisation

### **Étape 1: Démarrer l'app**
```bash
npm run back:dev
```

### **Étape 2: Lancer le seeder**
```bash
npm run seed
```

**Output attendu** ✅:
```
🌱 Starting database seeding...

✅ Seeded 3 admin accounts
✅ Seeded 8 categories
✅ Seeded 8 users (5 customers + 3 vendors)
✅ Seeded 3 vendor profiles
✅ Seeded 10 products

🛍️ Seeding Client Test Data...

👤 Creating users...
✅ Created: acheteur@test.com | vendeur@test.com

🏪 Creating shop...
✅ Created: Boutique Eleganza

📦 Creating products...
✅ Created: 8 products

✨ Client Test Data Seeding Complete!

📝 Credentials:
   Buyer:  acheteur@test.com / Test1234!
   Seller: vendeur@test.com / Test1234!

✅ Database seeding completed successfully!
```

---

## 🧪 Données Créées

### **1. Buyer (Acheteur)**
```json
{
  "email": "acheteur@test.com",
  "password": "Test1234!",
  "prenom": "Kofi",
  "name": "Mensah",
  "phone": "+22961000001",
  "role": "CLIENT",
  "isVerified": true,
  "isActive": true
}
```

### **2. Seller (Vendeur)**
```json
{
  "email": "vendeur@test.com",
  "password": "Test1234!",
  "prenom": "Aminata",
  "name": "Sow",
  "phone": "+22961000002",
  "role": "VENDOR",
  "isVerified": true,
  "isActive": true
}
```

### **3. Shop (Boutique du Vendeur)**
```json
{
  "shopName": "Boutique Eleganza",
  "shopAddress": "Cotonou, Bénin",
  "activityType": "Mode & Vêtements",
  "description": "Mode et accessoires authentiques - Wax, tissus traditionnels",
  "status": "APPROVED",
  "owner": "Aminata Sow"
}
```

### **4. Products (8 produits)**

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

**Détails**:
- Tous les produits ont des images placeholder
- Prix en FCFA
- 3 produits marqués comme "Featured" pour la home
- Description détaillée pour chaque produit

---

## 🧪 Test Rapide

### Login Buyer
```bash
curl -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "identifier": "acheteur@test.com",
    "password": "Test1234!"
  }'
```

### Login Seller
```bash
curl -X POST http://localhost:3000/api/v1/auth/login \
  -H "Content-Type: application/json" \
  -d '{
    "identifier": "vendeur@test.com",
    "password": "Test1234!"
  }'
```

### Lister les produits
```bash
TOKEN="eyJ..."

curl -H "Authorization: Bearer $TOKEN" \
  http://localhost:3000/api/v1/products
```

---

## 📋 Phase 2 - À Ajouter

Les éléments suivants peuvent être ajoutés au seeder (ou via l'API):

### **Orders (Commandes)**
```json
{
  "userId": "buyer_id",
  "vendorId": "shop_id",
  "status": "confirmed",
  "totalAmount": 25000,
  "items": [
    { "productId": "robe_id", "quantity": 1, "price": 15000 }
  ]
}
```

### **Wishlist**
```json
{
  "userId": "buyer_id",
  "productId": "product_id"
}
```

### **Conversation + Messages**
```json
{
  "buyerId": "buyer_id",
  "sellerId": "vendor_id",
  "messages": [
    { "senderId": "vendor_id", "content": "Bonjour!" },
    { "senderId": "buyer_id", "content": "J'ai une question" }
  ]
}
```

### **Notifications**
```json
{
  "userId": "buyer_id",
  "title": "Commande confirmée",
  "body": "Votre commande a été confirmée",
  "type": "order",
  "isRead": false
}
```

---

## 🔍 Vérifier les Données

### Via DB (Adminer/pgAdmin)
```
Users table:        2 ligne client (acheteur + vendeur)
VendorProfiles:     1 boutique
Products:           8 produits
Categories:         8 catégories (créées automatiquement)
```

### Via API
```bash
# Produits
GET /api/v1/products

# Vendeur
GET /api/v1/vendors/vendeur@test.com

# Boutique
GET /api/v1/shops/boutique-eleganza
```

---

## 📁 Fichier du Seeder

```
src/database/seeders/seeds/client-data.seed.ts
```

**Contenu**:
- Fonction `seedClientData(dataSource)` 
- Exécutée automatiquement par `npm run seed`
- Crée users, shop, et 8 produits
- Affiche les credentials à la fin

---

## ✅ Status

| Élément | Status |
|---------|--------|
| Users (Buyer) | ✅ |
| Users (Seller) | ✅ |
| Shop | ✅ |
| Products (8) | ✅ |
| Categories | ✅ |
| Compilation | ✅ |

**Phase 2 Items** (Orders, Wishlist, Chat, Notifications):
- Peuvent être ajoutés au seeder
- Ou créés via l'API directement
- Ou faire des seeders séparés

---

## 🚀 Frontend Ready

Frontend peut maintenant tester:
- ✅ Login (buyer + seller)
- ✅ Browse products
- ✅ View shop
- ✅ Product details
- ✅ Add to cart
- ⏭️ Checkout (pour Phase 2)
- ⏭️ Order tracking (pour Phase 2)
- ⏭️ Chat (pour Phase 2)

---

## 🎯 Prochaines Étapes

### Option A: Extend Seeder
Ajouter au `client-data.seed.ts`:
- Orders avec statuts variés
- Wishlist items
- Conversations + Messages
- Notifications

### Option B: Create via API
Frontend crée les données en testant:
- Add to cart → Checkout → Order
- Add to wishlist
- Start conversation

---

**Créé**: 2026-06-21  
**Prêt pour tests**: ✅ Oui
**Build Status**: ✅ OK
