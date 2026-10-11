import { MigrationInterface, QueryRunner } from 'typeorm';

// Retraits de gains vendeurs (pendant de delivery_earnings côté livreur).
// Règles métier fixées par Collins :
//  - l'admin valide et paie à la main, rien ne part automatiquement ;
//  - le solde retirable ne compte que les commandes LIVRÉES ;
//  - pas de minimum global, mais un minimum possible PAR vendeur
//    (vendor_profiles."minWithdrawalAmount", 0 = aucun minimum).
export class AddVendorWithdrawals1790600000000 implements MigrationInterface {
  name = 'AddVendorWithdrawals1790600000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    // Seuil minimum individualisé du vendeur (0 = pas de minimum).
    await queryRunner.query(`
      ALTER TABLE "vendor_profiles"
      ADD COLUMN IF NOT EXISTS "minWithdrawalAmount" numeric(12,2) NOT NULL DEFAULT 0
    `);

    await queryRunner.query(`
      DO $$ BEGIN
        CREATE TYPE "public"."vendor_withdrawals_status_enum" AS ENUM ('en attente', 'payé', 'rejeté');
      EXCEPTION
        WHEN duplicate_object THEN null;
      END $$;
    `);

    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS "vendor_withdrawals" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "vendorId" uuid NOT NULL,
        "montant" numeric(12,2) NOT NULL,
        "status" "public"."vendor_withdrawals_status_enum" NOT NULL DEFAULT 'en attente',
        "paymentMethod" character varying(50) NOT NULL,
        "mobileNumber" character varying(20) NOT NULL,
        "noteAdmin" text,
        "paidAt" TIMESTAMP,
        "processedById" uuid,
        "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
        "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
        CONSTRAINT "PK_vendor_withdrawals" PRIMARY KEY ("id"),
        CONSTRAINT "FK_vendor_withdrawals_vendor" FOREIGN KEY ("vendorId") REFERENCES "vendor_profiles"("id") ON DELETE RESTRICT,
        CONSTRAINT "FK_vendor_withdrawals_processedBy" FOREIGN KEY ("processedById") REFERENCES "admin_accounts"("id") ON DELETE SET NULL
      )
    `);

    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "IDX_vendor_withdrawals_vendorId" ON "vendor_withdrawals" ("vendorId")`);
    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "IDX_vendor_withdrawals_status" ON "vendor_withdrawals" ("status")`);
    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "IDX_vendor_withdrawals_createdAt" ON "vendor_withdrawals" ("createdAt")`);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TABLE IF EXISTS "vendor_withdrawals"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "public"."vendor_withdrawals_status_enum"`);
    await queryRunner.query(`ALTER TABLE "vendor_profiles" DROP COLUMN IF EXISTS "minWithdrawalAmount"`);
  }
}
