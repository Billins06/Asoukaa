import { MigrationInterface, QueryRunner } from 'typeorm';

// 1) Gain du livreur sur une course express (80 % / 20 % comme les autres livraisons) :
//    delivery_earnings.deliveryId devient facultatif et on ajoute independentDeliveryId.
// 2) Administration des courses express : motif d'annulation, remboursement, note interne.
// Idempotente ; aucune donnée existante n'est modifiée.
export class AddExpressEarningsAndAdmin1791880000000 implements MigrationInterface {
  name = 'AddExpressEarningsAndAdmin1791880000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`ALTER TABLE "delivery_earnings" ALTER COLUMN "deliveryId" DROP NOT NULL`);
    await queryRunner.query(`ALTER TABLE "delivery_earnings" ADD COLUMN IF NOT EXISTS "independentDeliveryId" uuid NULL`);
    await queryRunner.query(`
      DO $$ BEGIN
        ALTER TABLE "delivery_earnings"
          ADD CONSTRAINT "UQ_delivery_earnings_independentDeliveryId" UNIQUE ("independentDeliveryId");
      EXCEPTION WHEN duplicate_object OR duplicate_table THEN null;
      END $$;
    `);
    await queryRunner.query(`
      DO $$ BEGIN
        ALTER TABLE "delivery_earnings"
          ADD CONSTRAINT "FK_delivery_earnings_independentDelivery"
          FOREIGN KEY ("independentDeliveryId") REFERENCES "independent_deliveries"("id") ON DELETE RESTRICT;
      EXCEPTION WHEN duplicate_object THEN null;
      END $$;
    `);
    await queryRunner.query(`
      DO $$ BEGIN
        ALTER TABLE "delivery_earnings"
          ADD CONSTRAINT "CHK_delivery_earnings_one_source"
          CHECK (("deliveryId" IS NOT NULL) <> ("independentDeliveryId" IS NOT NULL));
      EXCEPTION WHEN duplicate_object THEN null;
      END $$;
    `);

    await queryRunner.query(`
      ALTER TABLE "independent_deliveries"
        ADD COLUMN IF NOT EXISTS "cancelReason" text NULL,
        ADD COLUMN IF NOT EXISTS "refundStatus" varchar(20) NULL,
        ADD COLUMN IF NOT EXISTS "refundedAt" timestamp NULL,
        ADD COLUMN IF NOT EXISTS "adminNote" text NULL
    `);
    // Rattrapage : courses express déjà livrées avant cette migration (80 % par défaut).
    await queryRunner.query(`
      INSERT INTO "delivery_earnings"
        ("independentDeliveryId", "agentId", "fraisLivraison", "taux", "montantLivreur", "montantPlateforme", "status")
      SELECT d."id", d."agentId", d."tarifConvenu",
             COALESCE(a."earningsRate", 80),
             ROUND(d."tarifConvenu" * COALESCE(a."earningsRate", 80) / 100, 2),
             d."tarifConvenu" - ROUND(d."tarifConvenu" * COALESCE(a."earningsRate", 80) / 100, 2),
             'en attente'
        FROM "independent_deliveries" d
        JOIN "delivery_agent_profiles" a ON a."id" = d."agentId"
       WHERE d."status" = 'livré' AND d."tarifConvenu" IS NOT NULL AND d."agentId" IS NOT NULL
      ON CONFLICT ("independentDeliveryId") DO NOTHING
    `);
    await queryRunner.query(
      `CREATE INDEX IF NOT EXISTS "IDX_independent_deliveries_refundStatus" ON "independent_deliveries" ("refundStatus") WHERE "refundStatus" IS NOT NULL`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_independent_deliveries_refundStatus"`);
    await queryRunner.query(`
      ALTER TABLE "independent_deliveries"
        DROP COLUMN IF EXISTS "adminNote",
        DROP COLUMN IF EXISTS "refundedAt",
        DROP COLUMN IF EXISTS "refundStatus",
        DROP COLUMN IF EXISTS "cancelReason"
    `);
    const paid = await queryRunner.query(
      `SELECT 1 FROM "delivery_earnings" WHERE "independentDeliveryId" IS NOT NULL AND "status" = 'payé' LIMIT 1`,
    );
    if (paid.length) {
      throw new Error('Retour arrière refusé : des gains de courses express ont déjà été payés aux livreurs.');
    }
    await queryRunner.query(`DELETE FROM "delivery_earnings" WHERE "independentDeliveryId" IS NOT NULL`);
    await queryRunner.query(`ALTER TABLE "delivery_earnings" DROP CONSTRAINT IF EXISTS "CHK_delivery_earnings_one_source"`);
    await queryRunner.query(`ALTER TABLE "delivery_earnings" DROP CONSTRAINT IF EXISTS "FK_delivery_earnings_independentDelivery"`);
    await queryRunner.query(`ALTER TABLE "delivery_earnings" DROP CONSTRAINT IF EXISTS "UQ_delivery_earnings_independentDeliveryId"`);
    await queryRunner.query(`ALTER TABLE "delivery_earnings" DROP COLUMN IF EXISTS "independentDeliveryId"`);
    await queryRunner.query(`ALTER TABLE "delivery_earnings" ALTER COLUMN "deliveryId" SET NOT NULL`);
  }
}
