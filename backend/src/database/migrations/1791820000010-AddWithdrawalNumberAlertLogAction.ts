import { MigrationInterface, QueryRunner } from 'typeorm';

// Journal d'activité : nouvelle valeur d'action pour l'alerte « retrait vers
// un numéro Mobile Money inhabituel » (voir VendorWithdrawalsService).
// Idempotente. Même technique que 1791700000000-AddSecurityAlertAck.
export class AddWithdrawalNumberAlertLogAction1791820000010
  implements MigrationInterface
{
  name = 'AddWithdrawalNumberAlertLogAction1791820000010';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      DO $$ BEGIN
        IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'activity_logs_action_enum') THEN
          ALTER TYPE "activity_logs_action_enum" ADD VALUE IF NOT EXISTS 'Retrait vendeur : numéro Mobile Money inhabituel';
        END IF;
      END $$;
    `);
  }

  public async down(): Promise<void> {
    // Postgres ne sait pas retirer une valeur d'enum (et des lignes du journal
    // peuvent déjà l'utiliser) : la valeur reste, sans effet.
  }
}
