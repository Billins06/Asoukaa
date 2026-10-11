import { MigrationInterface, QueryRunner } from 'typeorm';

// « Meilleures boutiques » de la page d'accueil : boutiques choisies
// MANUELLEMENT par l'admin (table featured_shops), affichées dans l'ordre de
// `position`. Une boutique ne peut figurer qu'une fois (UNIQUE vendorId) et
// disparaît de la liste si le profil vendeur est supprimé (ON DELETE CASCADE).
// Voir src/modules/vitrine/ (GET /vitrine/best-shops, /admin/vitrine/best-shops).
// Migration idempotente : peut être rejouée sans erreur.
export class AddFeaturedShops1791400000000 implements MigrationInterface {
  name = 'AddFeaturedShops1791400000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS "featured_shops" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "vendorId" uuid NOT NULL,
        "position" integer NOT NULL DEFAULT 0,
        "isActive" boolean NOT NULL DEFAULT true,
        "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
        "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
        CONSTRAINT "PK_featured_shops" PRIMARY KEY ("id"),
        CONSTRAINT "UQ_featured_shops_vendorId" UNIQUE ("vendorId"),
        CONSTRAINT "FK_featured_shops_vendor" FOREIGN KEY ("vendorId") REFERENCES "vendor_profiles"("id") ON DELETE CASCADE
      )
    `);

    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "IDX_featured_shops_isActive_position" ON "featured_shops" ("isActive", "position")`);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_featured_shops_isActive_position"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "featured_shops"`);
  }
}
