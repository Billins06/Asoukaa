import { MigrationInterface, QueryRunner } from 'typeorm';

// « Paiements à examiner » : bouton « Marquer comme traité ».
//  - 3 colonnes sur `payments` (reviewedAt, reviewedBy, reviewNote) ;
//  - nouvelle valeur d'action dans le journal d'activité.
// Idempotente : peut être rejouée sans erreur. Aucune donnée existante modifiée.
export class AddPaymentReviewed1791840000000 implements MigrationInterface {
  name = 'AddPaymentReviewed1791840000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "payments"
        ADD COLUMN IF NOT EXISTS "reviewedAt" TIMESTAMP NULL,
        ADD COLUMN IF NOT EXISTS "reviewedBy" uuid NULL,
        ADD COLUMN IF NOT EXISTS "reviewNote" varchar(500) NULL
    `);
    await queryRunner.query(`
      DO $$ BEGIN
        IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'activity_logs_action_enum') THEN
          ALTER TYPE "activity_logs_action_enum" ADD VALUE IF NOT EXISTS 'Paiement reçu examiné par un administrateur';
        END IF;
      END $$;
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "payments"
        DROP COLUMN IF EXISTS "reviewNote",
        DROP COLUMN IF EXISTS "reviewedBy",
        DROP COLUMN IF EXISTS "reviewedAt"
    `);
    // La valeur d'enum du journal reste (Postgres ne sait pas la retirer).
  }
}
