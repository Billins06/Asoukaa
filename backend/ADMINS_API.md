# 👤 Admin Management API

**Date**: 2026-06-21  
**Status**: ✅ Implémenté et Compilé

---

## 📋 Vue d'ensemble

Nouveaux endpoints pour gérer les comptes administrateurs. Réservé aux **SUPERADMIN uniquement**.

### ✅ Nouveaux Endpoints

| Méthode | Route | Description | Rôle |
|---------|-------|-------------|------|
| **POST** | `/auth/admin/create` | Créer un admin | SUPERADMIN |
| **GET** | `/auth/admin/list` | Lister les admins ⭐ NEW | SUPERADMIN |
| **GET** | `/auth/admin/:id` | Détails d'un admin ⭐ NEW | SUPERADMIN |
| **POST** | `/auth/admin/:id/deactivate` | Désactiver un admin ⭐ NEW | SUPERADMIN |
| **GET** | `/auth/admin/me` | Profil actuel | ADMIN/SUPERADMIN |

---

## 🔗 Nouveaux Endpoints (Détails)

### **1. Lister tous les admins**

```http
GET /api/v1/auth/admin/list
Authorization: Bearer TOKEN
```

**Query Parameters** (optionnels):
```
?page=1     # Page (default 1)
&limit=20   # Items par page (default 20)
```

**Response** (Pagination):
```json
{
  "data": [
    {
      "id": "uuid",
      "email": "superadmin@asoukaa.com",
      "prenom": "Super",
      "name": "Admin",
      "role": "SUPERADMIN",
      "isPasswordSet": true,
      "isActive": true,
      "lastLoginAt": "2026-06-21T17:30:00Z",
      "createdAt": "2026-06-21T...",
      "updatedAt": "2026-06-21T..."
    },
    {
      "id": "uuid",
      "email": "admin@asoukaa.com",
      "prenom": "Admin",
      "name": "Support",
      "role": "ADMIN",
      "isPasswordSet": true,
      "isActive": true,
      "lastLoginAt": "2026-06-21T15:20:00Z",
      "createdAt": "2026-06-21T...",
      "updatedAt": "2026-06-21T..."
    }
  ],
  "pagination": {
    "total": 3,
    "page": 1,
    "limit": 20,
    "pages": 1
  }
}
```

**⚠️ Important**: Les champs sensibles (`passwordHash`, `invitationToken`) sont automatiquement supprimés.

---

### **2. Récupérer un admin par ID**

```http
GET /api/v1/auth/admin/:id
Authorization: Bearer TOKEN
```

**Example**:
```bash
curl -H "Authorization: Bearer TOKEN" \
  http://localhost:3000/api/v1/auth/admin/uuid-of-admin
```

**Response** (Admin complet sans secrets):
```json
{
  "id": "uuid",
  "email": "admin@asoukaa.com",
  "prenom": "Admin",
  "name": "Support",
  "role": "ADMIN",
  "isPasswordSet": true,
  "isActive": true,
  "lastLoginAt": "2026-06-21T15:20:00Z",
  "createdAt": "2026-06-21T...",
  "updatedAt": "2026-06-21T..."
}
```

---

### **3. Désactiver un admin**

```http
POST /api/v1/auth/admin/:id/deactivate
Authorization: Bearer TOKEN
Content-Type: application/json
```

**Request Body**: (Empty)

**Response**:
```json
{
  "message": "Admin deactivated successfully"
}
```

**⚠️ Important**:
- Impossible de désactiver un SUPERADMIN
- L'action est loggée avec admin ID et IP
- L'admin désactivé ne pourra plus se connecter

---

## 🧪 Exemples cURL

### Login SuperAdmin
```bash
curl -X POST http://localhost:3000/api/v1/auth/admin/login \
  -H "Content-Type: application/json" \
  -d '{
    "identifier": "superadmin@asoukaa.com",
    "password": "Admin1234!"
  }'
# Récupère: { "accessToken": "eyJ...", "admin": {...} }
```

### Lister les admins
```bash
TOKEN="eyJ..."

curl -X GET "http://localhost:3000/api/v1/auth/admin/list?page=1&limit=10" \
  -H "Authorization: Bearer $TOKEN"
```

### Voir un admin spécifique
```bash
TOKEN="eyJ..."
ADMIN_ID="uuid-of-admin"

curl -X GET "http://localhost:3000/api/v1/auth/admin/$ADMIN_ID" \
  -H "Authorization: Bearer $TOKEN"
```

### Désactiver un admin
```bash
TOKEN="eyJ..."
ADMIN_ID="uuid-of-admin"

curl -X POST "http://localhost:3000/api/v1/auth/admin/$ADMIN_ID/deactivate" \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json"
```

---

## 🔐 Sécurité

✅ **Authentification**
- JWT obligatoire pour tous les endpoints

✅ **Autorisation**
- **Seulement SUPERADMIN** peut accéder
- Les autres admins ont accès à `/admin/me` seulement

✅ **Données Sensibles**
- `passwordHash` jamais retourné
- `invitationToken` jamais retourné
- Validé à la source dans le service

✅ **Audit Trail**
- L'action "deactivate" est loggée
- Admin ID et IP enregistrés
- Action: `ADMIN_DEACTIVATED`

✅ **Validation**
- Impossible de désactiver un SUPERADMIN
- ID d'admin vérifié avant toute action
- 404 si admin inexistant

---

## 📁 Fichiers Modifiés

```
✅ src/modules/auth/auth.service.ts
   - Ajout: getAllAdmins(page, limit)
   - Ajout: getAdminById(id)
   - Ajout: deactivateAdmin(id, deactivatedById, ip)

✅ src/modules/auth/auth.controller.ts
   - Ajout: @Get('admin/list')
   - Ajout: @Get('admin/:id')
   - Ajout: @Post('admin/:id/deactivate')
   - Ajout: import Param
```

---

## 🎯 Use Cases

### Dashboard - Liste des Admins
```
1. SuperAdmin accède au dashboard
2. Appel: GET /auth/admin/list
3. Affiche les 20 premiers admins
4. Pagination disponible
```

### Gestion des Admins
```
1. SuperAdmin clique sur un admin
2. Appel: GET /auth/admin/:id
3. Voit les détails (email, rôle, dernière connexion)
4. Peut cliquer "Désactiver"
5. Appel: POST /auth/admin/:id/deactivate
6. Admin ne peut plus se connecter
```

### Désactivation
```
1. Admin problématique
2. SuperAdmin clique "Désactiver"
3. POST /auth/admin/:id/deactivate
4. isActive = false
5. Action loggée
6. Admin rejeté au login
```

---

## ✅ Vérifications

| Point | Status |
|-------|--------|
| Service implémenté | ✅ |
| Controller implémenté | ✅ |
| Compilation | ✅ |
| Sécurité (SUPERADMIN only) | ✅ |
| Audit trail | ✅ |
| Données sensibles supprimées | ✅ |
| Pagination | ✅ |
| Validation | ✅ |

---

## 🚀 Statut Final

**Status**: ✅ **PRÊT POUR PRODUCTION**

Frontend peut maintenant :
- ✅ Lister les admins avec pagination
- ✅ Voir les détails d'un admin
- ✅ Désactiver un admin
- ✅ Afficher le profil courant (`/admin/me`)

---

**Créé**: 2026-06-21  
**Build**: ✅ Succès (0 errors)
**Prêt pour tests**: ✅ Oui
