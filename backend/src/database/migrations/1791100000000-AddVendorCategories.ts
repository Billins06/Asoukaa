import { MigrationInterface, QueryRunner } from 'typeorm';

// Catégories du vendeur : le champ texte libre « type d'activité » est
// remplacé, côté appli, par le choix de 1 à 5 vraies catégories de la
// plateforme (simple étiquette d'affichage, sans effet sur les catégories
// de publication des produits).
//  - vendor_profiles.categoryIds : uuid[] NOT NULL DEFAULT '{}' ;
//  - activityType est CONSERVÉ : texte dérivé (noms des catégories joints
//    par ", ", 100 caractères max) pour les écrans et anciens clients.
// Les vendeurs déjà inscrits gardent leur activityType et categoryIds = '{}'.
// Voir src/modules/vendors/.
export class AddVendorCategories1791100000000 implements MigrationInterface {
  name = 'AddVendorCategories1791100000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "vendor_profiles" ADD COLUMN IF NOT EXISTS "categoryIds" uuid[] NOT NULL DEFAULT '{}'`,
    );
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(
      `ALTER TABLE "vendor_profiles" DROP COLUMN IF EXISTS "categoryIds"`,
    );
  }
}
