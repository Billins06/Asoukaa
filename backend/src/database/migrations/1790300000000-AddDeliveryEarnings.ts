import { MigrationInterface, QueryRunner } from 'typeorm';

export class AddDeliveryEarnings1790300000000 implements MigrationInterface {
  name = 'AddDeliveryEarnings1790300000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    // Taux individualisé du livreur (nullable — un taux par défaut
    // s'applique côté service tant que l'admin n'a rien fixé).
    await queryRunner.query(`
      ALTER TABLE "delivery_agent_profiles"
      ADD COLUMN IF NOT EXISTS "earningsRate" numeric(5,2)
    `);

    await queryRunner.query(`
      DO $$ BEGIN
        CREATE TYPE "public"."delivery_earnings_status_enum" AS ENUM ('en attente', 'payé');
      EXCEPTION
        WHEN duplicate_object THEN null;
      END $$;
    `);

    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS "delivery_earnings" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "deliveryId" uuid NOT NULL,
        "agentId" uuid NOT NULL,
        "fraisLivraison" numeric(12,2) NOT NULL,
        "taux" numeric(5,2) NOT NULL,
        "montantLivreur" numeric(12,2) NOT NULL,
        "montantPlateforme" numeric(12,2) NOT NULL,
        "status" "public"."delivery_earnings_status_enum" NOT NULL DEFAULT 'en attente',
        "paidAt" TIMESTAMP,
        "processedById" uuid,
        "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
        "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
        CONSTRAINT "UQ_delivery_earnings_deliveryId" UNIQUE ("deliveryId"),
        CONSTRAINT "PK_delivery_earnings" PRIMARY KEY ("id"),
        CONSTRAINT "FK_delivery_earnings_delivery" FOREIGN KEY ("deliveryId") REFERENCES "deliveries"("id") ON DELETE RESTRICT,
        CONSTRAINT "FK_delivery_earnings_agent" FOREIGN KEY ("agentId") REFERENCES "delivery_agent_profiles"("id") ON DELETE RESTRICT,
        CONSTRAINT "FK_delivery_earnings_processedBy" FOREIGN KEY ("processedById") REFERENCES "admin_accounts"("id") ON DELETE SET NULL
      )
    `);

    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "IDX_delivery_earnings_agentId" ON "delivery_earnings" ("agentId")`);
    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "IDX_delivery_earnings_status" ON "delivery_earnings" ("status")`);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TABLE IF EXISTS "delivery_earnings"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "public"."delivery_earnings_status_enum"`);
    await queryRunner.query(`ALTER TABLE "delivery_agent_profiles" DROP COLUMN IF EXISTS "earningsRate"`);
  }
}
