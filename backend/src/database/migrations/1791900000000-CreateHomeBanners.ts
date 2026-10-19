import { MigrationInterface, QueryRunner } from 'typeorm';

// Bannières d'accueil gérées par l'admin (image, cible du clic, durée,
// ordre, période). Idempotente : peut être rejouée sans erreur.
export class CreateHomeBanners1791900000000 implements MigrationInterface {
  name = 'CreateHomeBanners1791900000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS "home_banners" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "imageUrl" varchar(500) NOT NULL,
        "titre" varchar(120) NULL,
        "sousTitre" varchar(200) NULL,
        "targetType" varchar(10) NOT NULL,
        "targetId" uuid NULL,
        "targetUrl" varchar(500) NULL,
        "durationSeconds" integer NOT NULL DEFAULT 4,
        "sortOrder" integer NOT NULL DEFAULT 0,
        "isActive" boolean NOT NULL DEFAULT true,
        "startsAt" timestamptz NULL,
        "endsAt" timestamptz NULL,
        "createdAt" timestamp NOT NULL DEFAULT now(),
        "updatedAt" timestamp NOT NULL DEFAULT now(),
        CONSTRAINT "PK_home_banners" PRIMARY KEY ("id")
      )
    `);
    await queryRunner.query(`
      DO $$ BEGIN
        ALTER TABLE "home_banners"
          ADD CONSTRAINT "CHK_home_banners_targetType"
          CHECK ("targetType" IN ('category', 'product', 'shop', 'link'));
      EXCEPTION WHEN duplicate_object THEN null;
      END $$;
    `);
    await queryRunner.query(`
      DO $$ BEGIN
        ALTER TABLE "home_banners"
          ADD CONSTRAINT "CHK_home_banners_target"
          CHECK (
            ("targetType" = 'link' AND "targetUrl" IS NOT NULL AND "targetId" IS NULL)
            OR ("targetType" <> 'link' AND "targetId" IS NOT NULL AND "targetUrl" IS NULL)
          );
      EXCEPTION WHEN duplicate_object THEN null;
      END $$;
    `);
    await queryRunner.query(`
      DO $$ BEGIN
        ALTER TABLE "home_banners"
          ADD CONSTRAINT "CHK_home_banners_duration"
          CHECK ("durationSeconds" BETWEEN 2 AND 30);
      EXCEPTION WHEN duplicate_object THEN null;
      END $$;
    `);
    await queryRunner.query(`
      DO $$ BEGIN
        ALTER TABLE "home_banners"
          ADD CONSTRAINT "CHK_home_banners_period"
          CHECK ("startsAt" IS NULL OR "endsAt" IS NULL OR "endsAt" > "startsAt");
      EXCEPTION WHEN duplicate_object THEN null;
      END $$;
    `);
    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS "IDX_home_banners_isActive_sortOrder"
        ON "home_banners" ("isActive", "sortOrder")
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_home_banners_isActive_sortOrder"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "home_banners"`);
  }
}
