import { MigrationInterface, QueryRunner } from 'typeorm';

// Livres numériques (PDF).
//  - products   : type numérique + fiche du livre + chemin du fichier privé ;
//  - categories : marque « numérique » (catégories réservées aux livres) ;
//  - orders     : drapeau isDigital + adresse devenue facultative (panier 100 % livres) ;
//  - commissions: date de disponibilité du gain (retenue de 24 h) ;
//  - payments   : méthode « free » (livre à 0 F) ;
//  - library_items : la Bibliothèque (un livre par client, compteur de téléchargements) ;
//  - journal d'activité : 2 nouvelles actions.
// Idempotente : peut être rejouée sans erreur. Aucune donnée existante n'est modifiée
// (les produits, catégories et commandes existants restent « physiques »).
export class AddDigitalBooks1791850000000 implements MigrationInterface {
  name = 'AddDigitalBooks1791850000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "products"
        ADD COLUMN IF NOT EXISTS "isDigital" boolean NOT NULL DEFAULT false,
        ADD COLUMN IF NOT EXISTS "author" varchar(200) NULL,
        ADD COLUMN IF NOT EXISTS "pageCount" integer NULL,
        ADD COLUMN IF NOT EXISTS "language" varchar(50) NULL,
        ADD COLUMN IF NOT EXISTS "fileSizeBytes" bigint NULL,
        ADD COLUMN IF NOT EXISTS "filePath" varchar(500) NULL
    `);
    await queryRunner.query(`
      ALTER TABLE "categories"
        ADD COLUMN IF NOT EXISTS "isDigital" boolean NOT NULL DEFAULT false
    `);
    await queryRunner.query(`
      ALTER TABLE "orders"
        ADD COLUMN IF NOT EXISTS "isDigital" boolean NOT NULL DEFAULT false
    `);
    await queryRunner.query(`ALTER TABLE "orders" ALTER COLUMN "addressId" DROP NOT NULL`);
    await queryRunner.query(`
      ALTER TABLE "commissions"
        ADD COLUMN IF NOT EXISTS "availableAt" TIMESTAMP NULL
    `);
    await queryRunner.query(`
      DO $$ BEGIN
        IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'payments_method_enum') THEN
          ALTER TYPE "payments_method_enum" ADD VALUE IF NOT EXISTS 'free';
        END IF;
      END $$;
    `);
    await queryRunner.query(`
      DO $$ BEGIN
        IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'activity_logs_action_enum') THEN
          ALTER TYPE "activity_logs_action_enum" ADD VALUE IF NOT EXISTS 'Livre numérique téléchargé';
          ALTER TYPE "activity_logs_action_enum" ADD VALUE IF NOT EXISTS 'Livre numérique remboursé';
        END IF;
      END $$;
    `);
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS "library_items" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "userId" uuid NOT NULL,
        "productId" uuid NOT NULL,
        "orderId" uuid NOT NULL,
        "downloadCount" integer NOT NULL DEFAULT 0,
        "firstDownloadedAt" TIMESTAMP NULL,
        "lastDownloadedAt" TIMESTAMP NULL,
        "revokedAt" TIMESTAMP NULL,
        "revokedReason" varchar(300) NULL,
        "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
        CONSTRAINT "PK_library_items" PRIMARY KEY ("id"),
        CONSTRAINT "UQ_library_items_user_product" UNIQUE ("userId", "productId"),
        CONSTRAINT "FK_library_items_user" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_library_items_product" FOREIGN KEY ("productId") REFERENCES "products"("id") ON DELETE CASCADE,
        CONSTRAINT "FK_library_items_order" FOREIGN KEY ("orderId") REFERENCES "orders"("id") ON DELETE CASCADE
      )
    `);
    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "IDX_library_items_orderId" ON "library_items" ("orderId")`);
    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "IDX_products_isDigital" ON "products" ("isDigital")`);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP TABLE IF EXISTS "library_items"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_products_isDigital"`);
    await queryRunner.query(`ALTER TABLE "commissions" DROP COLUMN IF EXISTS "availableAt"`);
    await queryRunner.query(`ALTER TABLE "orders" DROP COLUMN IF EXISTS "isDigital"`);
    await queryRunner.query(`ALTER TABLE "categories" DROP COLUMN IF EXISTS "isDigital"`);
    await queryRunner.query(`
      ALTER TABLE "products"
        DROP COLUMN IF EXISTS "filePath",
        DROP COLUMN IF EXISTS "fileSizeBytes",
        DROP COLUMN IF EXISTS "language",
        DROP COLUMN IF EXISTS "pageCount",
        DROP COLUMN IF EXISTS "author",
        DROP COLUMN IF EXISTS "isDigital"
    `);
    // orders.addressId reste facultative, et les valeurs d'enum ('free', actions du journal)
    // restent : Postgres ne sait pas les retirer et des lignes peuvent les utiliser.
  }
}
