import { MigrationInterface, QueryRunner } from 'typeorm';

// Commission propre à chaque vendeur (pourcentage ou montant fixe par commande),
// fixée par l'admin. Idempotente. Aucun vendeur existant n'est modifié : sans
// réglage, la commission par défaut (10 %) continue de s'appliquer.
export class AddVendorCommissionSettings1791890000000 implements MigrationInterface {
  name = 'AddVendorCommissionSettings1791890000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "vendor_profiles"
        ADD COLUMN IF NOT EXISTS "commissionType" varchar(10) NULL,
        ADD COLUMN IF NOT EXISTS "commissionValue" numeric(12,2) NULL
    `);
    await queryRunner.query(`
      DO $$ BEGIN
        ALTER TABLE "vendor_profiles"
          ADD CONSTRAINT "CHK_vendor_profiles_commissionType"
          CHECK ("commissionType" IS NULL OR "commissionType" IN ('percent', 'fixed'));
      EXCEPTION WHEN duplicate_object THEN null;
      END $$;
    `);
    await queryRunner.query(`
      DO $$ BEGIN
        ALTER TABLE "vendor_profiles"
          ADD CONSTRAINT "CHK_vendor_profiles_commissionValue"
          CHECK ("commissionValue" IS NULL OR ("commissionValue" >= 0
                 AND ("commissionType" IS DISTINCT FROM 'percent' OR "commissionValue" <= 100)));
      EXCEPTION WHEN duplicate_object THEN null;
      END $$;
    `);
    await queryRunner.query(`
      ALTER TABLE "commissions"
        ADD COLUMN IF NOT EXISTS "typeCommission" varchar(10) NOT NULL DEFAULT 'percent'
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`ALTER TABLE "commissions" DROP COLUMN IF EXISTS "typeCommission"`);
    await queryRunner.query(`ALTER TABLE "vendor_profiles" DROP CONSTRAINT IF EXISTS "CHK_vendor_profiles_commissionValue"`);
    await queryRunner.query(`ALTER TABLE "vendor_profiles" DROP CONSTRAINT IF EXISTS "CHK_vendor_profiles_commissionType"`);
    await queryRunner.query(`
      ALTER TABLE "vendor_profiles"
        DROP COLUMN IF EXISTS "commissionValue",
        DROP COLUMN IF EXISTS "commissionType"
    `);
  }
}
