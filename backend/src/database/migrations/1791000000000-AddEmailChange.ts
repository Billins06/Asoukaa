import { MigrationInterface, QueryRunner } from 'typeorm';

// Changement d'e-mail sécurisé (voir src/modules/users/email-change/) :
//  - table email_changes : une ligne par demande (code hashé, essais, jeton
//    de révocation hashé, statut) ;
//  - users.tokensValidAfter : tout JWT émis avant cette date est refusé
//    (« déconnecter tous les appareils ») ;
//  - users.securityAlertAt / securityAlertReason : alerte visible de l'admin
//    quand le propriétaire répond « Ce n'est pas moi » ;
//  - 3 nouvelles valeurs de l'enum activity_logs_action_enum (journal d'activité).
// Idempotente : peut être rejouée sans erreur.
export class AddEmailChange1791000000000 implements MigrationInterface {
  name = 'AddEmailChange1791000000000';

  public async up(queryRunner: QueryRunner): Promise<void> {
    // ── Colonnes de sécurité sur users ────────────────────
    await queryRunner.query(`
      ALTER TABLE "users"
      ADD COLUMN IF NOT EXISTS "tokensValidAfter" TIMESTAMP,
      ADD COLUMN IF NOT EXISTS "securityAlertAt" TIMESTAMP,
      ADD COLUMN IF NOT EXISTS "securityAlertReason" character varying(255)
    `);

    // ── Table des demandes de changement d'e-mail ─────────
    await queryRunner.query(`
      CREATE TABLE IF NOT EXISTS "email_changes" (
        "id" uuid NOT NULL DEFAULT uuid_generate_v4(),
        "userId" uuid NOT NULL,
        "oldEmail" character varying(255) NOT NULL,
        "newEmail" character varying(255) NOT NULL,
        "codeHash" character varying(255) NOT NULL,
        "attempts" integer NOT NULL DEFAULT 0,
        "sendCount" integer NOT NULL DEFAULT 1,
        "codeExpiresAt" TIMESTAMP NOT NULL,
        "lastSentAt" TIMESTAMP NOT NULL,
        "status" character varying(20) NOT NULL DEFAULT 'pending',
        "revertTokenHash" character varying(64),
        "revertExpiresAt" TIMESTAMP,
        "confirmedAt" TIMESTAMP,
        "revertedAt" TIMESTAMP,
        "createdAt" TIMESTAMP NOT NULL DEFAULT now(),
        CONSTRAINT "PK_email_changes" PRIMARY KEY ("id"),
        CONSTRAINT "FK_email_changes_user" FOREIGN KEY ("userId") REFERENCES "users"("id") ON DELETE CASCADE
      )
    `);

    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "IDX_email_changes_userId" ON "email_changes" ("userId")`);
    await queryRunner.query(`CREATE INDEX IF NOT EXISTS "IDX_email_changes_revertTokenHash" ON "email_changes" ("revertTokenHash")`);
    // Une seule demande active par utilisateur : verrou posé par la base,
    // pas seulement par le code (deux requêtes simultanées).
    await queryRunner.query(`
      CREATE UNIQUE INDEX IF NOT EXISTS "UQ_email_changes_one_pending_per_user"
      ON "email_changes" ("userId") WHERE "status" = 'pending'
    `);

    // ── Journal d'activité : nouvelles actions ────────────
    // ⚠️ ADD VALUE ne peut pas être annulé par down() — voir la note ci-dessous.
    // Le DO ... IF EXISTS évite d'échouer si l'enum porte un autre nom dans
    // une base installée autrement.
    await queryRunner.query(`
      DO $$ BEGIN
        IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'activity_logs_action_enum') THEN
          ALTER TYPE "activity_logs_action_enum" ADD VALUE IF NOT EXISTS 'Demande de changement d''e-mail';
          ALTER TYPE "activity_logs_action_enum" ADD VALUE IF NOT EXISTS 'Adresse e-mail modifiée';
          ALTER TYPE "activity_logs_action_enum" ADD VALUE IF NOT EXISTS 'E-mail annulé — compte potentiellement compromis';
        END IF;
      END $$;
    `);
  }

  public async down(queryRunner: QueryRunner): Promise<void> {
    await queryRunner.query(`DROP INDEX IF EXISTS "UQ_email_changes_one_pending_per_user"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_email_changes_revertTokenHash"`);
    await queryRunner.query(`DROP INDEX IF EXISTS "IDX_email_changes_userId"`);
    await queryRunner.query(`DROP TABLE IF EXISTS "email_changes"`);
    await queryRunner.query(`
      ALTER TABLE "users"
      DROP COLUMN IF EXISTS "securityAlertReason",
      DROP COLUMN IF EXISTS "securityAlertAt",
      DROP COLUMN IF EXISTS "tokensValidAfter"
    `);
    // Les 3 valeurs ajoutées à activity_logs_action_enum NE sont PAS retirées :
    // Postgres ne sait pas supprimer une valeur d'enum, et des lignes du
    // journal peuvent déjà les utiliser. Elles sont sans effet.
  }
}
