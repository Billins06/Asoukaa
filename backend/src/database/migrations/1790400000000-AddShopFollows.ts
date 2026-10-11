import { MigrationInterface, QueryRunner } from 'typeorm';

// Crée la table shop_follows : abonnements réels des utilisateurs aux
// boutiques (bouton "Suivre la boutique" côté Flutter, stat "Abonnés"
// = stats.followersCount dans GET /vendors/me et GET /vendors/:id/public).
// Remplace l'ancien booléen purement local côté appli.
export class AddShopFollows1790400000000 implements MigrationInterface {
  name = 'AddShopFollows1790400000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS "shop_follows" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "userId" uuid NOT NULL,
        "vendorId" uuid NOT NULL,
        "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
        CONSTRAINT "PK_shop_follows" PRIMARY KEY ("id"),
        CONSTRAINT "UQ_shop_follows_user_vendor" UNIQUE ("userId", "vendorId"),
        CONSTRAINT "FK_shop_follows_user" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_shop_follows_vendor" FOREIGN KEY ("vendorId") REFERENCES "vendor_profiles"("id") ON DELETE CASCADE
      )
    `);

    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "IDX_shop_follows_vendorId" ON "shop_follows" ("vendorId")`);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_shop_follows_vendorId"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "shop_follows"`);
  }
}
