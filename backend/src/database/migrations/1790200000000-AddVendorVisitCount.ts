import { MigrationInterface, QueryRunner } from 'typeorm';

// Ajoute vendor_profiles.visitCount : compteur réel du nombre de fois
// où un acheteur a ouvert la page boutique d'un vendeur (voir
// GET /vendors/:id/public dans vendors.controller.ts). Remplace
// l'ancienne estimation inventée côté Flutter (totalViews * 3 / 2)
// dans l'onglet "Statistiques" du tableau de bord vendeur.
export class AddVendorVisitCount1790200000000 implements MigrationInterface {
  name = 'AddVendorVisitCount1790200000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "vendor_profiles"
      ADD COLUMN IF NOT EXISTS "visitCount" integer NOT NULL DEFAULT 0
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "vendor_profiles"
      DROP COLUMN IF EXISTS "visitCount"
    `);
  }
}
