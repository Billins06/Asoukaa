import { MigrationInterface, QueryRunner } from 'typeorm';

// Rend les colonnes de documents de vérification NULLABLE sur
// vendor_profiles et delivery_agent_profiles : l'inscription vendeur/
// livreur (POST /vendors/apply, POST /delivery-agents/apply) peut
// désormais se faire SANS documents. Les documents restent exigés avant
// que l'admin puisse approuver le dossier (voir reviewVendor/reviewAgent
// dans vendors.service.ts / delivery-agents.service.ts) et peuvent être
// complétés après coup via PATCH /vendors/me/documents ou
// PATCH /delivery-agents/me/documents tant que le dossier est en attente.
export class MakeVendorAgentDocsNullable1790500000000 implements MigrationInterface {
  name = 'MakeVendorAgentDocsNullable1790500000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`ALTER TABLE "vendor_profiles" ALTER COLUMN "idDocumentUrl" DROP NOT NULL`);
    await queryRunner.query(`ALTER TABLE "vendor_profiles" ALTER COLUMN "selfieUrl" DROP NOT NULL`);
    await queryRunner.query(`ALTER TABLE "delivery_agent_profiles" ALTER COLUMN "idDocumentUrl" DROP NOT NULL`);
    await queryRunner.query(`ALTER TABLE "delivery_agent_profiles" ALTER COLUMN "selfieUrl" DROP NOT NULL`);
    await queryRunner.query(`ALTER TABLE "delivery_agent_profiles" ALTER COLUMN "vehiclePhotoUrl" DROP NOT NULL`);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`ALTER TABLE "delivery_agent_profiles" ALTER COLUMN "vehiclePhotoUrl" SET NOT NULL`);
    await queryRunner.query(`ALTER TABLE "delivery_agent_profiles" ALTER COLUMN "selfieUrl" SET NOT NULL`);
    await queryRunner.query(`ALTER TABLE "delivery_agent_profiles" ALTER COLUMN "idDocumentUrl" SET NOT NULL`);
    await queryRunner.query(`ALTER TABLE "vendor_profiles" ALTER COLUMN "selfieUrl" SET NOT NULL`);
    await queryRunner.query(`ALTER TABLE "vendor_profiles" ALTER COLUMN "idDocumentUrl" SET NOT NULL`);
  }
}
