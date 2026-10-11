import { MigrationInterface, QueryRunner } from 'typeorm';

// Compteur de vues des produits.
//
// Jusqu'ici l'onglet "Statistiques" du vendeur affichait toujours 0 vue :
// aucune colonne n'existait côté base (l'application Flutter avait même un
// commentaire "pas encore fourni par le backend"). Les ventes, elles,
// avaient bien une colonne mais personne ne l'incrémentait — c'est corrigé
// côté code (OrdersService.incrementProductSales), sans migration.
export class AddProductViewCount1790700000000 implements MigrationInterface {
  name = 'AddProductViewCount1790700000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "products"
      ADD COLUMN IF NOT EXISTS "nombreVues" integer NOT NULL DEFAULT 0
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "products" DROP COLUMN IF EXISTS "nombreVues"
    `);
  }
}
