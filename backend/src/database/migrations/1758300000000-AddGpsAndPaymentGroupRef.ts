import { MigrationInterface, QueryRunner } from 'typeorm';

// Trois ajouts liés au traitement du "panier multi-boutiques" (une
// commande par boutique, un seul paiement) et à la position GPS partagée
// par le client au paiement :
//  - addresses.latitude / longitude   : position GPS de l'adresse
//  - deliveries.latitude / longitude  : copie dénormalisée (comme
//    adresseLivraison) pour que le livreur l'ait directement sans join
//  - payments.groupRef                : relie les paiements créés
//    ensemble depuis un même paiement client multi-commandes
export class AddGpsAndPaymentGroupRef1758300000000
  implements MigrationInterface
{
  name = 'AddGpsAndPaymentGroupRef1758300000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "addresses"
      ADD COLUMN IF NOT EXISTS "latitude"  double precision,
      ADD COLUMN IF NOT EXISTS "longitude" double precision
    `);

    await queryRunner.query(`
      ALTER TABLE "deliveries"
      ADD COLUMN IF NOT EXISTS "latitude"  double precision,
      ADD COLUMN IF NOT EXISTS "longitude" double precision
    `);

    await queryRunner.query(`
      ALTER TABLE "payments"
      ADD COLUMN IF NOT EXISTS "groupRef" varchar(64)
    `);

    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS "IDX_payments_groupRef"
      ON "payments" ("groupRef")
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_payments_groupRef"`);
    await queryRunner.query(`
      ALTER TABLE "payments" DROP COLUMN IF EXISTS "groupRef"
    `);
    await queryRunner.query(`
      ALTER TABLE "deliveries"
      DROP COLUMN IF EXISTS "latitude",
      DROP COLUMN IF EXISTS "longitude"
    `);
    await queryRunner.query(`
      ALTER TABLE "addresses"
      DROP COLUMN IF EXISTS "latitude",
      DROP COLUMN IF EXISTS "longitude"
    `);
  }
}
