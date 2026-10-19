import { MigrationInterface, QueryRunner } from 'typeorm';

// Désactivation d'un produit par l'administration (page « Produits » du dashboard).
// Idempotente. Aucun produit existant n'est modifié (tous « non bloqués »).
export class AddProductAdminBlock1791870000000 implements MigrationInterface {
  name = 'AddProductAdminBlock1791870000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "products"
        ADD COLUMN IF NOT EXISTS "isBlockedByAdmin" boolean NOT NULL DEFAULT false,
        ADD COLUMN IF NOT EXISTS "adminBlockReason" varchar(500) NULL,
        ADD COLUMN IF NOT EXISTS "adminBlockedAt" timestamp NULL,
        ADD COLUMN IF NOT EXISTS "adminBlockedFromStatus" varchar(30) NULL
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "products"
        DROP COLUMN IF EXISTS "adminBlockedFromStatus",
        DROP COLUMN IF EXISTS "adminBlockedAt",
        DROP COLUMN IF EXISTS "adminBlockReason",
        DROP COLUMN IF EXISTS "isBlockedByAdmin"
    `);
  }
}
