import { MigrationInterface, QueryRunner } from 'typeorm';

// Acquittement des alertes « Ce n'est pas moi » par l'administration :
//  - users.securityAlertAckedAt (timestamptz, nullable) : date à laquelle un
//    admin a pris connaissance de l'alerte. Une alerte est « non acquittée »
//    si securityAlertAt n'est pas nul ET (securityAlertAckedAt est nul OU
//    antérieur à securityAlertAt : une nouvelle alerte survenue après un
//    acquittement redevient active) ;
//  - index partiel pour compter rapidement les alertes actives (compteur du
//    menu du site admin) ;
//  - nouvelle valeur de l'enum activity_logs_action_enum (journal d'activité :
//    acquittement de l'alerte).
// Idempotente : peut être rejouée sans erreur.
export class AddSecurityAlertAck1791700000000 implements MigrationInterface {
  name = 'AddSecurityAlertAck1791700000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`
      ALTER TABLE "users"
      ADD COLUMN IF NOT EXISTS "securityAlertAckedAt" TIMESTAMPTZ
    `);

    await queryRunner.query(`
      CREATE INDEX IF NOT EXISTS "IDX_users_security_alert"
      ON "users" ("securityAlertAt")
      WHERE "securityAlertAt" IS NOT NULL
    `);

    // ⚠️ ADD VALUE ne peut pas être annulé par down() — voir la note ci-dessous.
    // Même technique que 1791000000000-AddEmailChange.
    await queryRunner.query(`
      DO $$ BEGIN
        IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'activity_logs_action_enum') THEN
          ALTER TYPE "activity_logs_action_enum" ADD VALUE IF NOT EXISTS 'Alerte de sécurité acquittée';
        END IF;
      END $$;
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_users_security_alert"`);
    await queryRunner.query(`
      ALTER TABLE "users"
      DROP COLUMN IF EXISTS "securityAlertAckedAt"
    `);
    // La valeur ajoutée à activity_logs_action_enum N'est PAS retirée :
    // Postgres ne sait pas supprimer une valeur d'enum, et des lignes du
    // journal peuvent déjà l'utiliser. Elle est sans effet.
  }
}
