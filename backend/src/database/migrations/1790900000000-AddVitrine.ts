import { MigrationInterface, QueryRunner } from 'typeorm';

// Vitrine de la page d'accueil, pilotée depuis le back-office :
//  - vitrine_rayons         : rayons (ventes flash, tendances, succès,
//                             rayons libres), avec période de visibilité ;
//  - vitrine_rayon_produits : produits ORDONNÉS de chaque rayon ;
//  - vitrine_bandeau        : bandeau d'accueil (une seule ligne utilisée).
// Voir src/modules/vitrine/.
export class AddVitrine1790900000000 implements MigrationInterface {
  name = 'AddVitrine1790900000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      DO $$ BEGIN
        CREATE TYPE "public"."vitrine_rayons_type_enum" AS ENUM ('flash', 'tendance', 'succes', 'libre');
      EXCEPTION
        WHEN duplicate_object THEN null;
      END $$;
    `);

    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS "vitrine_rayons" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "nom" character varying(120) NOT NULL,
        "type" "public"."vitrine_rayons_type_enum" NOT NULL DEFAULT 'libre',
        "imageUrl" character varying(500),
        "sortOrder" integer NOT NULL DEFAULT 0,
        "isActive" boolean NOT NULL DEFAULT true,
        "startsAt" TIMESTAMP WITH TIME ZONE,
        "endsAt" TIMESTAMP WITH TIME ZONE,
        "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
        "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
        CONSTRAINT "PK_vitrine_rayons" PRIMARY KEY ("id")
      )
    `);

    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "IDX_vitrine_rayons_isActive_sortOrder" ON "vitrine_rayons" ("isActive", "sortOrder")`);

    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS "vitrine_rayon_produits" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "rayonId" uuid NOT NULL,
        "productId" uuid NOT NULL,
        "sortOrder" integer NOT NULL DEFAULT 0,
        CONSTRAINT "PK_vitrine_rayon_produits" PRIMARY KEY ("id"),
        CONSTRAINT "UQ_vitrine_rayon_produits_rayon_product" UNIQUE ("rayonId", "productId"),
        CONSTRAINT "FK_vitrine_rayon_produits_rayon" FOREIGN KEY ("rayonId") REFERENCES "vitrine_rayons"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_vitrine_rayon_produits_product" FOREIGN KEY ("productId") REFERENCES "products"("id") ON DELETE CASCADE
      )
    `);

    // L'index UNIQUE (rayonId, productId) couvre déjà les recherches par
    // rayon ; celui-ci sert à la suppression en cascade côté produit.
    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "IDX_vitrine_rayon_produits_productId" ON "vitrine_rayon_produits" ("productId")`);

    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS "vitrine_bandeau" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "titre" character varying(120) NOT NULL,
        "sousTitre" character varying(200),
        "imageUrl" character varying(500),
        "isActive" boolean NOT NULL DEFAULT true,
        "updatedAt" TIMESTAMP NOT NULL DEFAULT now(),
        CONSTRAINT "PK_vitrine_bandeau" PRIMARY KEY ("id")
      )
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TABLE IF EXISTS "vitrine_bandeau"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_vitrine_rayon_produits_productId"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "vitrine_rayon_produits"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_vitrine_rayons_isActive_sortOrder"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "vitrine_rayons"`);
    await queryRunner.query(`DROP TYPE IF EXISTS "public"."vitrine_rayons_type_enum"`);
  }
}
