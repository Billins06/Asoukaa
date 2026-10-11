import { MigrationInterface, QueryRunner } from 'typeorm';

// Ajoute tout ce qui est nécessaire au nouveau système de suivi de
// commande à 3 chemins (Cas A = livreur interne, Cas B = retrait en
// boutique, Cas C = bus/taxi) et à ses preuves de livraison :
//
//  - orders.status : deux nouvelles valeurs, "livreur affecté" et
//    "en transit" (Cas A uniquement — voir order.entity.ts)
//  - orders.expedieAt / disputeOuverte / confirmationAutomatique :
//    gèrent le délai de confirmation automatique à 3 jours (Cas C)
//  - delivery_proofs : nouvelle table — une preuve = un évènement
//    immuable (photo, scan QR, GPS, signature selon l'étape) capturé
//    à un moment précis du parcours, réutilisée pour les 3 chemins
export class AddDeliveryProofsAndOrderStatuses1790100000000
  implements MigrationInterface
{
  name = 'AddDeliveryProofsAndOrderStatuses1790100000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    // ── Nouveaux statuts de commande ──────────────────────
    // ⚠️ ADD VALUE ne peut pas être annulé par down() — voir la note
    // dans down() ci-dessous.
    await queryRunner.query(`
      ALTER TYPE "orders_status_enum" ADD VALUE IF NOT EXISTS 'livreur affecté'
    `);
    await queryRunner.query(`
      ALTER TYPE "orders_status_enum" ADD VALUE IF NOT EXISTS 'en transit'
    `);

    // ── Colonnes Cas C (bus/taxi) sur orders ──────────────
    await queryRunner.query(`
      ALTER TABLE "orders"
      ADD COLUMN IF NOT EXISTS "expedieAt" timestamp,
      ADD COLUMN IF NOT EXISTS "disputeOuverte" boolean NOT NULL DEFAULT false,
      ADD COLUMN IF NOT EXISTS "confirmationAutomatique" boolean NOT NULL DEFAULT false
    `);

    // ── Table des preuves de livraison ────────────────────
    // uuid_generate_v4() : même mécanisme de génération d'id que
    // toutes les autres tables du projet (orders, deliveries, users…)
    // — voir PostgresDriver.uuidGenerator dans typeorm.
    await queryRunner.query(`CREATE EXTENSION IF NOT EXISTS "uuid-ossp"`);

    await queryRunner.query(`
      DO $$ BEGIN
        CREATE TYPE "delivery_proofs_role_enum" AS ENUM ('livreur', 'vendeur', 'client');
      EXCEPTION WHEN duplicate_object THEN NULL; END $$;
    `);
    await queryRunner.query(`
      DO $$ BEGIN
        CREATE TYPE "delivery_proofs_stage_enum" AS ENUM (
          'ramassage_livreur',
          'remise_client',
          'retrait_boutique',
          'remise_transporteur',
          'reception_client'
        );
      EXCEPTION WHEN duplicate_object THEN NULL; END $$;
    `);

    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS "delivery_proofs" (
        "id"              uuid NOT NULL DEFAULT uuid_generate_v4(),
        "orderId"         uuid NOT NULL,
        "deliveryId"      uuid,
        "role"            "delivery_proofs_role_enum" NOT NULL,
        "stage"           "delivery_proofs_stage_enum" NOT NULL,
        "photoUrl"        varchar(500),
        "etatColis"       text,
        "qrScanValue"     varchar(255),
        "latitude"        double precision,
        "longitude"       double precision,
        "signatureData"   text,
        "createdByUserId" uuid NOT NULL,
        "createdAt"       timestamp NOT NULL DEFAULT now(),
        CONSTRAINT "PK_delivery_proofs" PRIMARY KEY ("id"),
        CONSTRAINT "FK_delivery_proofs_order" FOREIGN KEY ("orderId")
          REFERENCES "orders"("id") ON DELETE RESTRICT,
        CONSTRAINT "FK_delivery_proofs_delivery" FOREIGN KEY ("deliveryId")
          REFERENCES "deliveries"("id") ON DELETE RESTRICT,
        CONSTRAINT "FK_delivery_proofs_created_by" FOREIGN KEY ("createdByUserId")
          REFERENCES "users"("id") ON DELETE RESTRICT
      )
    `);

    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "IDX_delivery_proofs_orderId" ON "delivery_proofs" ("orderId")`);
    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "IDX_delivery_proofs_deliveryId" ON "delivery_proofs" ("deliveryId")`);
    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "IDX_delivery_proofs_stage" ON "delivery_proofs" ("stage")`);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_delivery_proofs_stage"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_delivery_proofs_deliveryId"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_delivery_proofs_orderId"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "delivery_proofs"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "delivery_proofs_stage_enum"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "delivery_proofs_role_enum"`);

    await queryRunner.query(`
      ALTER TABLE "orders"
      DROP COLUMN IF EXISTS "confirmationAutomatique",
      DROP COLUMN IF EXISTS "disputeOuverte",
      DROP COLUMN IF EXISTS "expedieAt"
    `);

    // ⚠️ Postgres ne permet pas de retirer une valeur d'un type enum
    // directement (il faudrait recréer tout le type en excluant ces
    // valeurs, ce qui casserait toute commande déjà dans ce statut).
    // On ne retire donc pas 'livreur affecté' / 'en transit' ici — si
    // un vrai rollback est nécessaire, le faire manuellement après
    // avoir vérifié qu'aucune commande n'est dans ces statuts.
  }
}
