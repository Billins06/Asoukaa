import { MigrationInterface, QueryRunner } from 'typeorm';

// Motif du refus d'un remboursement saisi par l'admin :
//  - refunds.motifRejet (text, nullable). Distinct de refunds.motif, qui
//    contient la raison donnée par le CLIENT à sa demande.
// Idempotente : peut être rejouée sans erreur.
export class AddRefundRejectionReason1791700000001 implements MigrationInterface {
  name = 'AddRefundRejectionReason1791700000001';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "refunds"
      ADD COLUMN IF NOT EXISTS "motifRejet" text
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "refunds"
      DROP COLUMN IF EXISTS "motifRejet"
    `);
  }
}
