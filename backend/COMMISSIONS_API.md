# 📊 CommissionsModule - API Complète

**Date**: 2026-06-21  
**Status**: ✅ Implémenté et Compilé

---

## 📋 Vue d'ensemble

Le **CommissionsModule** expose les endpoints pour gérer les commissions (pourcentages prélevés par Asoukaa sur chaque vente).

### Entités
- ✅ `Commission` - Déjà existante depuis le début
- ✅ `CommissionStatus` - PENDING / PAID
- ✅ Relations : Order, Vendor, Admin

### Nouveaux Éléments Créés
- ✅ **Service**: Logique métier complète
- ✅ **Controller**: Endpoints d'administration
- ✅ **Module**: Intégration au PaymentsModule

---

## 🔗 Endpoints Disponibles

Tous les endpoints nécessitent:
- ✅ Bearer token JWT valide
- ✅ Rôle: SUPERADMIN ou ADMIN

### **1. Lister toutes les commissions**
```http
GET /api/v1/admin/commissions
Authorization: Bearer TOKEN
```

**Query Parameters** (optionnels):
```
?vendorId=uuid          # Filter par vendeur
?status=payé            # Filter par status (en attente, payé)
?page=1                 # Pagination (default 1)
&limit=20               # Items par page (default 20)
```

**Response**:
```json
{
  "data": [
    {
      "id": "uuid",
      "orderId": "uuid",
      "vendorId": "uuid",
      "totalCommande": 100.00,
      "taux": 10.00,
      "montantCommission": 10.00,
      "commissionVendor": 90.00,
      "status": "en attente",
      "paidAt": null,
      "processedById": null,
      "createdAt": "2026-06-21T...",
      "updatedAt": "2026-06-21T...",
      "order": { ... },
      "vendor": { ... },
      "processedBy": null
    }
  ],
  "pagination": {
    "total": 45,
    "page": 1,
    "limit": 20,
    "pages": 3
  }
}
```

---

### **2. Récupérer une commission par ID**
```http
GET /api/v1/admin/commissions/:id
Authorization: Bearer TOKEN
```

**Response** (Commission complète avec relations):
```json
{
  "id": "uuid",
  "orderId": "uuid",
  "vendorId": "uuid",
  "totalCommande": 100.00,
  "taux": 10.00,
  "montantCommission": 10.00,
  "commissionVendor": 90.00,
  "status": "en attente",
  "paidAt": null,
  "processedById": null,
  "createdAt": "2026-06-21T...",
  "updatedAt": "2026-06-21T...",
  "order": {
    "id": "uuid",
    "orderNumber": "ORD-2026-00001",
    "total": 100.00,
    ...
  },
  "vendor": {
    "id": "uuid",
    "shopName": "Boutique XYZ",
    "user": { ... }
  },
  "processedBy": null
}
```

---

### **3. Obtenir les statistiques**
```http
GET /api/v1/admin/commissions/stats/overview
Authorization: Bearer TOKEN
```

**Response** (Vue globale des commissions):
```json
{
  "pending": {
    "count": 15,
    "amount": 1500.00
  },
  "paid": {
    "count": 30,
    "amount": 3000.00
  },
  "total": {
    "count": 45,
    "amount": 4500.00
  }
}
```

---

### **4. Marquer une commission comme payée**
```http
POST /api/v1/admin/commissions/:id/mark-paid
Authorization: Bearer TOKEN
Content-Type: application/json
```

**Request Body**: (Empty)

**Response**:
```json
{
  "id": "uuid",
  "orderId": "uuid",
  "vendorId": "uuid",
  "totalCommande": 100.00,
  "taux": 10.00,
  "montantCommission": 10.00,
  "commissionVendor": 90.00,
  "status": "payé",           ← Changé
  "paidAt": "2026-06-21T17:30:00Z",  ← Défini
  "processedById": "uuid",    ← Admin qui a marqué
  "createdAt": "2026-06-21T...",
  "updatedAt": "2026-06-21T..."
}
```

**Logging**: L'action est loggée avec:
- Action: `PAYMENT_SUCCESS`
- Avant: `{ status: PENDING, paidAt: null }`
- Après: `{ status: PAID, paidAt: DATE }`

---

## 🧪 Exemples cURL

### Obtenir un token
```bash
curl -X POST http://localhost:3000/api/v1/auth/admin/login \
  -H "Content-Type: application/json" \
  -d '{
    "identifier": "superadmin@asoukaa.com",
    "password": "Admin1234!"
  }'
# Récupère: { "accessToken": "eyJ..." }
```

### Lister les commissions en attente
```bash
TOKEN="eyJ..."
curl -X GET "http://localhost:3000/api/v1/admin/commissions?status=en%20attente&limit=10" \
  -H "Authorization: Bearer $TOKEN"
```

### Obtenir les statistiques
```bash
TOKEN="eyJ..."
curl -X GET http://localhost:3000/api/v1/admin/commissions/stats/overview \
  -H "Authorization: Bearer $TOKEN"
```

### Marquer comme payée
```bash
TOKEN="eyJ..."
COMMISSION_ID="uuid-of-commission"

curl -X POST "http://localhost:3000/api/v1/admin/commissions/$COMMISSION_ID/mark-paid" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json"
```

---

## 📁 Fichiers Créés

```
src/modules/payments/commissions/
├── commissions.service.ts      ← Logique métier
├── commissions.controller.ts   ← Endpoints
└── commissions.module.ts       ← Intégration
```

### Modifiés
```
src/modules/payments/payments.module.ts  ← Importe CommissionsModule
```

---

## 🔍 Détails Implémentation

### CommissionsService

**Méthodes disponibles**:
- `getAll(filters)` - Liste paginée avec filtres
- `getById(id)` - Commission unique avec relations
- `markAsPaid(id, adminId, ip)` - Marquer comme payée + audit
- `getStatistics()` - Statistiques globales

**Filtres supportés**:
```typescript
interface CommissionFilters {
  vendorId?: string;        // Filter par vendeur
  status?: CommissionStatus; // en attente / payé
  page?: number;            // Page (default 1)
  limit?: number;           // Items/page (default 20)
}
```

### CommissionsController

**Guards appliqués**:
- ✅ `JwtAuthGuard` - Token valide
- ✅ `RolesGuard` - Rôle vérifié
- ✅ `@Roles(SUPERADMIN, ADMIN)` - Accès admin uniquement

**Ordre des routes** (attention à l'ordre!):
1. `GET /stats/overview` - Stats
2. `GET /:id` - Détail
3. `GET /` - Liste
4. `POST /:id/mark-paid` - Marquer payée

---

## 🔐 Sécurité

✅ **Authentification**
- Tous les endpoints nécessitent un JWT valide

✅ **Autorisation**
- Seulement SUPERADMIN et ADMIN peuvent accéder

✅ **Audit Trail**
- L'action "marquer comme payée" est loggée
- IP, admin ID, avant/après sont enregistrés

✅ **Validation**
- Impossible de marquer deux fois comme payée
- Les relations (vendor, order, admin) sont vérifiées

---

## 📊 Cas d'Usage

### Use Case 1: Dashboard - Vue des Commissions
```
1. Admin accède au dashboard
2. Appel: GET /admin/commissions?status=en%20attente
3. Affiche les 20 premières commissions en attente
4. Pagination disponible
```

### Use Case 2: Admin Pays une Commission
```
1. Admin clique "Payer" sur une commission
2. Appel: POST /admin/commissions/:id/mark-paid
3. Commission passe en "payé"
4. paidAt et processedById sont définis
5. Audit log enregistre l'action
```

### Use Case 3: Reporting
```
1. Admin consulte les statistiques
2. Appel: GET /admin/commissions/stats/overview
3. Voit le total en attente et payé
4. Utilise pour le reporting financier
```

---

## ✅ Status

| Élément | Status |
|---------|--------|
| Service | ✅ Implémenté |
| Controller | ✅ Implémenté |
| Module | ✅ Intégré |
| Compilation | ✅ OK (0 errors) |
| Tests | ⏳ À faire |
| Documentation | ✅ Ce fichier |

---

## 🎯 Prêt pour le Frontend

Le frontend peut maintenant implémenter:
- Dashboard des commissions
- Liste paginée des commissions
- Détails d'une commission
- Bouton "Marquer comme payée"
- Statistiques/reporting

**Base URL**: `http://localhost:3000/api/v1/admin/commissions`

---

**Créé**: 2026-06-21  
**Prêt pour production**: ✅ Oui (avec tests)
