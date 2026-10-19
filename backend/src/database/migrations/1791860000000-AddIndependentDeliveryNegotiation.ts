import { MigrationInterface, QueryRunner } from 'typeorm';

// Course express négociée : délai, prix proposé, contre-proposition du livreur,
// réservation de 15 min et paiement Mobile Money de la course.
// Idempotente. Les courses existantes ne sont pas modifiées.
export class AddIndependentDeliveryNegotiation1791860000000 implements MigrationInterface {
  name = 'AddIndependentDeliveryNegotiation1791860000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TYPE "public"."independent_deliveries_status_enum"
        ADD VALUE IF NOT EXISTS 'contre-proposition'
    `);
    await queryRunner.query(`
      ALTER TYPE "public"."independent_deliveries_status_enum"
        ADD VALUE IF NOT EXISTS 'paiement en attente'
    `);
    await queryRunner.query(`
      ALTER TABLE "independent_deliveries"
        ADD COLUMN IF NOT EXISTS "delai" varchar(20) NOT NULL DEFAULT 'normal',
        ADD COLUMN IF NOT EXISTS "notes" text NULL,
        ADD COLUMN IF NOT EXISTS "proposedPrice" numeric(12,2) NULL,
        ADD COLUMN IF NOT EXISTS "counterPrice" numeric(12,2) NULL,
        ADD COLUMN IF NOT EXISTS "refusedAgentIds" text NULL,
        ADD COLUMN IF NOT EXISTS "reservedUntil" timestamp NULL,
        ADD COLUMN IF NOT EXISTS "paymentStatus" varchar(20) NULL,
        ADD COLUMN IF NOT EXISTS "paymentRef" varchar(255) NULL,
        ADD COLUMN IF NOT EXISTS "paymentOperator" varchar(10) NULL,
        ADD COLUMN IF NOT EXISTS "paidAt" timestamp NULL,
        ADD COLUMN IF NOT EXISTS "paymentRequestedAt" timestamp NULL
    `);
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS "IDX_independent_deliveries_requesterId"
        ON "independent_deliveries" ("requesterId")
    `);
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS "IDX_independent_deliveries_status"
        ON "independent_deliveries" ("status")
    `);
  }

  // ADD VALUE ne peut pas être annulé : on retire seulement les colonnes.
  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_independent_deliveries_status"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_independent_deliveries_requesterId"`);
    await queryRunner.query(`
      ALTER TABLE "independent_deliveries"
        DROP COLUMN IF EXISTS "paymentRequestedAt",
        DROP COLUMN IF EXISTS "paidAt",
        DROP COLUMN IF EXISTS "paymentOperator",
        DROP COLUMN IF EXISTS "paymentRef",
        DROP COLUMN IF EXISTS "paymentStatus",
        DROP COLUMN IF EXISTS "reservedUntil",
        DROP COLUMN IF EXISTS "refusedAgentIds",
        DROP COLUMN IF EXISTS "counterPrice",
        DROP COLUMN IF EXISTS "proposedPrice",
        DROP COLUMN IF EXISTS "notes",
        DROP COLUMN IF EXISTS "delai"
    `);
  }
}
