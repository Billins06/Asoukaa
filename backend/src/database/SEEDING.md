# 🌱 Database Seeding Guide

## Overview

This directory contains database seeding scripts to populate your development database with test data.

## Seeded Data

The seeding process creates the following test data:

### 1. Admin Accounts (3)
- **Superadmin**: superadmin@asoukaa.com
- **Admin 1**: admin@asoukaa.com  
- **Admin 2**: manager@asoukaa.com
- Password: `Admin1234!`

### 2. Users (5 Customers + 3 Vendors = 8 total)

**Customers:**
- alice@test.com
- bob@test.com
- carol@test.com
- david@test.com
- emma@test.com

**Vendors:**
- vendor1@test.com
- vendor2@test.com
- vendor3@test.com

Password (all users): `User1234!`

### 3. Vendor Profiles (3)
Each vendor has an approved shop profile with:
- Shop name
- Shop description
- Documents (mock URLs)
- Payment method configured

### 4. Categories (8)
- Électronique
- Mode
- Maison
- Beauté
- Sports
- Alimentation
- Livres
- Jouets

### 5. Products (10)
- 10 products distributed across vendors
- Prices ranging from $12.99 to $1,299.99
- Various categories
- All in ACTIVE status

### 6. Orders (3)
- 3 completed orders (one per customer)
- Each order contains 2 order items
- With total prices, shipping costs, and tax

## How to Run

### Option 1: Direct TypeORM CLI
```bash
npx ts-node src/database/seed-runner.ts
```

### Option 2: Using NestJS CLI (Recommended)
Add to `package.json`:
```json
{
  "scripts": {
    "seed": "ts-node -r tsconfig-paths/register src/database/seed-runner.ts"
  }
}
```

Then run:
```bash
npm run seed
```

## Important Notes

⚠️ **Idempotent Seeding**: Each seeder checks if data already exists before inserting:
- Running seeders multiple times won't create duplicates
- Safe to run repeatedly

✅ **Dependency Order**: Seeders run in correct order:
1. Admins (no dependencies)
2. Users (no dependencies)
3. Vendor Profiles (depends on Users)
4. Categories (no dependencies)
5. Products (depends on Vendors + Categories)
6. Orders (depends on Users + Products)

## Test Credentials

After seeding, you can login with:

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

## Customization

To modify seed data:
1. Edit the individual seed files in `seeds/` directory
2. Modify arrays and data templates
3. Run seeders again (they check for existing data)

## Troubleshooting

**"User not found" error**: Seeders run in dependency order. Ensure User seeder ran before running Vendor Profile seeder.

**"Already seeded" message**: Data already exists. To reseed:
```bash
npm run typeorm migration:revert  # Reset database
npm run seed                       # Reseed
```

**Connection errors**: Ensure your database is running and `.env` has correct `DB_*` variables.

## Files

```
src/database/
├── seed-runner.ts           # Entry point
├── seeders/
│   ├── seed.ts              # Main orchestrator
│   └── seeds/
│       ├── admin.seed.ts
│       ├── user.seed.ts
│       ├── vendor-profile.seed.ts
│       ├── category.seed.ts
│       ├── product.seed.ts
│       └── order.seed.ts
└── README.md
```
