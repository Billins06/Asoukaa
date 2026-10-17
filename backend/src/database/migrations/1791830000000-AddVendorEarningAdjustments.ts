import { MigrationInterface, QueryRunner } from 'typeorm';

// Reprise des gains vendeur lors d'un remboursement client approuvé :
// table `vendor_earning_adjustments` (le « carnet » des reprises).
// Une ligne par remboursement (index unique sur refundId = idempotence).
// Idempotente : peut être rejouée sans erreur. Aucune donnée existante n'est
// modifiée (pas de rétro-action sur les remboursements déjà approuvés).
export class AddVendorEarningAdjustments1791830000000 implements MigrationInterface {
  name = 'AddVendorEarningAdjustments1791830000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS "vendor_earning_adjustments" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "refundId" uuid NOT NULL,
        "orderId" uuid NOT NULL,
        "commissionId" uuid,
        "vendorId" uuid NOT NULL,
        "montantRembourse" numeric(12,2) NOT NULL,
        "totalPaye" numeric(12,2) NOT NULL,
        "proportion" numeric(8,6) NOT NULL,
        "montantVendeur" numeric(12,2) NOT NULL DEFAULT 0,
        "montantCommission" numeric(12,2) NOT NULL DEFAULT 0,
        "note" text,
        "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
        CONSTRAINT "PK_vendor_earning_adjustments" PRIMARY KEY ("id"),
        CONSTRAINT "FK_vendor_earning_adjustments_refund" FOREIGN KEY ("refundId") REFERENCES "refunds"("id") ON DELETE RESTRICT,
        CONSTRAINT "FK_vendor_earning_adjustments_order" FOREIGN KEY ("orderId") REFERENCES "orders"("id") ON DELETE RESTRICT,
        CONSTRAINT "FK_vendor_earning_adjustments_commission" FOREIGN KEY ("commissionId") REFERENCES "commissions"("id") ON DELETE RESTRICT,
        CONSTRAINT "FK_vendor_earning_adjustments_vendor" FOREIGN KEY ("vendorId") REFERENCES "vendor_profiles"("id") ON DELETE RESTRICT
      )
    `);

    await queryRunner.query(`CREATE UNIQUE INDEX IF NOT EXISTS "UQ_vendor_earning_adjustments_refund" ON "vendor_earning_adjustments" ("refundId")`);
    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "IDX_vendor_earning_adjustments_vendor" ON "vendor_earning_adjustments" ("vendorId")`);
    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "IDX_vendor_earning_adjustments_order" ON "vendor_earning_adjustments" ("orderId")`);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TABLE IF EXISTS "vendor_earning_adjustments"`);
  }
}
